address marketplace {
module binomial_option_pricing {
    use std::vector;

    // Fixed-point scale: values are scaled by 1e18
    const PRECISION: u256 = 1000000000000000000;
    const DAYS_PER_YEAR: u256 = 365;

    // Default finite-difference bump sizes (all scaled by 1e18)
    // Choose epsilons large enough to overcome integer rounding noise but small enough to be local
    const EPS_REL_PRICE: u256 = 1000000000000000;  // 0.001 = 0.1% relative bump on S
    const EPS_VOL_ABS: u256   = 1000000000000000;  // 0.001 = 0.1% absolute vol bump
    const EPS_RATE_ABS: u256  = 100000000000000;   // 0.0001 = 1 bp absolute rate bump

    // Signed fixed-point number: value = (neg ? -mag : mag) with 1e18 scaling
    struct Signed has copy, drop, store { 
        neg: bool, 
        mag: u256 
    }

    // Group of Greeks
    struct Greeks has drop, copy, store {
        delta: Signed,
        gamma: Signed,
        vega: Signed,
        theta: Signed,
        rho: Signed,
    }

    // Integer square root (Babylonian method) for u256
    fun sqrt(x: u256): u256 {
        if (x == 0) return 0;
        if (x <= 3) return 1;
        let z = x;
        let y = (x + 1) / 2;
        while (y < z) {
            z = y;
            y = (x / y + y) / 2;
        };
        z
    }

    // Fixed-point exp for small x (Taylor up to 10 terms).
    // x is scaled by PRECISION; result scaled by PRECISION.
    fun exp(x: u256): u256 {
        if (x == 0) return PRECISION;
        let result = PRECISION;
        let term = PRECISION;
        let i = 1u256;
        while (i <= 10) {
            term = (term * x) / (i * PRECISION);
            result = result + term;
            i = i + 1;
        };
        result
    }

    fun max_u256(a: u256, b: u256): u256 { if (a > b) a else b }

    // Exponentiation by squaring for fixed-point base
    fun pow_fp(base: u256, exp: u64): u256 {
        let result = PRECISION;
        let b = base;
        let e = exp;
        while (e > 0) {
            if (e % 2 == 1) {
                result = (result * b) / PRECISION;
            };
            b = (b * b) / PRECISION;
            e = e / 2;
        };
        result
    }

    // Helper: choose steps the same way as get_option_price
    fun choose_num_steps(days: u64): u64 {
        if (days <= 30) 30u64 else 50u64
    }

    // Core pricer with explicit step count (used by greeks to keep steps constant)
    fun price_core(
        underlying_price: u256,
        strike_price: u256,
        risk_free_rate: u256,
        volatility: u256,
        days_to_expiration: u64,
        num_steps: u64,
        is_call: bool
    ): u256 {
        // T = 0 => intrinsic value
        if (days_to_expiration == 0) {
            return if (is_call) {
                max_u256(
                    if (underlying_price > strike_price) underlying_price - strike_price else 0,
                    0
                )
            } else {
                max_u256(
                    if (strike_price > underlying_price) strike_price - underlying_price else 0,
                    0
                )
            }
        };

        let time_to_expiration_days = days_to_expiration as u256;

        // dt (in years) per step, scaled by PRECISION
        let denom = (DAYS_PER_YEAR * (num_steps as u256));
        let dt_years_scaled = (time_to_expiration_days * PRECISION) / denom;

        // sqrt(dt) with correct scaling:
        let sqrt_dt = sqrt(dt_years_scaled * PRECISION);

        // Up/down factors: u = exp(σ√dt), d = 1/u
        let vol_sqrt_dt = (volatility * sqrt_dt) / PRECISION;
        let u = exp(vol_sqrt_dt);
        let d = (PRECISION * PRECISION) / u;

        // Per-step risk-free factor
        let r_dt = (risk_free_rate * dt_years_scaled) / PRECISION;
        let exp_r_dt = exp(r_dt);
        let inv_exp_r_dt = (PRECISION * PRECISION) / exp_r_dt;

        // Degenerate/near-degenerate volatility
        if (volatility == 0 || u == PRECISION) {
            let discount_T = pow_fp(inv_exp_r_dt, num_steps);
            if (is_call) {
                return max_u256(
                    if (underlying_price > (strike_price * discount_T) / PRECISION) {
                        underlying_price - (strike_price * discount_T) / PRECISION
                    } else { 0 },
                    0
                )
            } else {
                return max_u256(
                    if ((strike_price * discount_T) / PRECISION > underlying_price) {
                        (strike_price * discount_T) / PRECISION - underlying_price
                    } else { 0 },
                    0
                )
            }
        };

        // Risk-neutral probability with clamping-by-construction
        let p = if (exp_r_dt <= d) {
            0
        } else if (exp_r_dt >= u) {
            PRECISION
        } else {
            ((exp_r_dt - d) * PRECISION) / (u - d)
        };

        // Build payoffs at maturity using O(n) rolling stock price
        let option_values = vector::empty<u256>();

        let s0 = underlying_price;
        let s_node = s0;
        let k = 0u64;
        while (k < num_steps) {
            s_node = (s_node * d) / PRECISION;
            k = k + 1;
        };

        let leaf0 = if (is_call) {
            if (s_node > strike_price) s_node - strike_price else 0
        } else {
            if (strike_price > s_node) strike_price - s_node else 0
        };
        vector::push_back(&mut option_values, leaf0);

        let i = 1u64;
        while (i <= num_steps) {
            s_node = (s_node * u) / d; // move to next leaf level
            let payoff = if (is_call) {
                if (s_node > strike_price) s_node - strike_price else 0
            } else {
                if (strike_price > s_node) strike_price - s_node else 0
            };
            vector::push_back(&mut option_values, payoff);
            i = i + 1;
        };

        // Backward induction
        let step = num_steps;
        while (step > 0) {
            let j = 0u64;
            let new_values = vector::empty<u256>();
            while (j < step) {
                let up_value = *vector::borrow(&option_values, j + 1);
                let down_value = *vector::borrow(&option_values, j);
                let expected = (p * up_value + (PRECISION - p) * down_value) / PRECISION;
                let present = (expected * inv_exp_r_dt) / PRECISION;
                vector::push_back(&mut new_values, present);
                j = j + 1;
            };
            option_values = new_values;
            step = step - 1;
        };

        *vector::borrow(&option_values, 0)
    }

    #[view]
    public fun get_option_price(
        underlying_price: u256,   // scaled by 1e18
        strike_price: u256,       // scaled by 1e18
        risk_free_rate: u256,     // annual r, scaled by 1e18
        volatility: u256,         // annual σ, scaled by 1e18
        days_to_expiration: u64,
        is_call: bool
    ): u256 {
        let steps = choose_num_steps(days_to_expiration);
        price_core(
            underlying_price,
            strike_price,
            risk_free_rate,
            volatility,
            days_to_expiration,
            steps,
            is_call
        )
    }

    // ============== Signed helpers ==============

    fun signed_from_diff(a: u256, b: u256): Signed {
        if (a >= b) Signed { neg: false, mag: a - b } else Signed { neg: true, mag: b - a }
    }

    fun signed_from_pos(x: u256): Signed { Signed { neg: false, mag: x } }

    // Divide Signed by a positive denominator and keep 1e18 scaling in the result:
    // returns (x / den) scaled by PRECISION
    fun signed_div_to_fp(x: Signed, den: u256): Signed {
        // Note: floor division; for better rounding you could add den/2 before dividing
        let mag_scaled = (x.mag * PRECISION) / den;
        Signed { neg: x.neg, mag: mag_scaled }
    }

    // Multiply Signed by a small u256 factor (no re-scaling)
    fun signed_mul_small(x: Signed, m: u256): Signed {
        Signed { neg: x.neg, mag: x.mag * m }
    }

    // Add two Signed values
    fun signed_add(a: Signed, b: Signed): Signed {
        if (a.neg == b.neg) {
            Signed { neg: a.neg, mag: a.mag + b.mag }
        } else {
            if (a.mag >= b.mag) { Signed { neg: a.neg, mag: a.mag - b.mag } }
            else { Signed { neg: b.neg, mag: b.mag - a.mag } }
        }
    }

    // ============== Utility bumps ==============

    // value * (1 ± eps) where both are scaled by PRECISION
    fun apply_rel_bump(value: u256, eps: u256, up: bool): u256 {
        let factor = if (up) PRECISION + eps else PRECISION - eps;
        (value * factor) / PRECISION
    }

    fun clamp_sub(a: u256, b: u256): u256 { if (a > b) a - b else 0 }

    // ============== Greeks (finite differences, fixed steps) ==============

    #[view]
    public fun get_greeks(
        underlying_price: u256,
        strike_price: u256,
        risk_free_rate: u256,
        volatility: u256,
        days_to_expiration: u64,
        is_call: bool
    ): Greeks {
        let steps = choose_num_steps(days_to_expiration);

        // Base price
        let p0 = price_core(
            underlying_price, strike_price, risk_free_rate, volatility,
            days_to_expiration, steps, is_call
        );

        // ----- Delta and Gamma (bump S relatively) -----
        let s_up = apply_rel_bump(underlying_price, EPS_REL_PRICE, true);
        let s_dn = apply_rel_bump(underlying_price, EPS_REL_PRICE, false);
        let p_s_up = price_core(s_up, strike_price, risk_free_rate, volatility, days_to_expiration, steps, is_call);
        let p_s_dn = price_core(s_dn, strike_price, risk_free_rate, volatility, days_to_expiration, steps, is_call);

        // Delta ≈ (P(S+) - P(S-)) / (S+ - S-)
        let delta_num = signed_from_diff(p_s_up, p_s_dn);
        let delta_den = if (s_up >= s_dn) s_up - s_dn else 1; // safety
        let delta = signed_div_to_fp(delta_num, delta_den);

        // Gamma ≈ (P(S+) - 2 P(S0) + P(S-)) / ( (S0*eps)^2 )
        let two_p0 = p0 * 2;
        let gamma_num = signed_add(signed_add(signed_from_pos(p_s_up), Signed { neg: true, mag: two_p0 }), signed_from_pos(p_s_dn));

        // h = S0 * eps
        let h = (underlying_price * EPS_REL_PRICE) / PRECISION;
        let h_sq = if (h == 0) 1 else (h * h) / PRECISION;
        let gamma = signed_div_to_fp(gamma_num, h_sq);

        // ----- Vega (absolute bump σ) -----
        let sigma_up = volatility + EPS_VOL_ABS;
        let sigma_dn = clamp_sub(volatility, EPS_VOL_ABS);
        let p_v_up = price_core(underlying_price, strike_price, risk_free_rate, sigma_up, days_to_expiration, steps, is_call);
        let p_v_dn = price_core(underlying_price, strike_price, risk_free_rate, sigma_dn, days_to_expiration, steps, is_call);
        // Vega per 1.0 volatility unit (multiply by 0.01 for per 1% vol)
        let vega_num = signed_from_diff(p_v_up, p_v_dn);
        let vega_den = (EPS_VOL_ABS * 2);
        let vega = signed_div_to_fp(vega_num, vega_den);

        // ----- Rho (absolute bump r) -----
        let r_up = risk_free_rate + EPS_RATE_ABS;
        let r_dn = clamp_sub(risk_free_rate, EPS_RATE_ABS);
        let p_r_up = price_core(underlying_price, strike_price, r_up, volatility, days_to_expiration, steps, is_call);
        let p_r_dn = price_core(underlying_price, strike_price, r_dn, volatility, days_to_expiration, steps, is_call);
        // Rho per 1.0 rate unit (multiply by 0.01 for per 1% rate)
        let rho_num = signed_from_diff(p_r_up, p_r_dn);
        let rho_den = (EPS_RATE_ABS * 2);
        let rho = signed_div_to_fp(rho_num, rho_den);

        // ----- Theta (bump days; keep steps constant). Result = price units per year
        // Use central difference when possible; otherwise forward difference
        let theta = if (days_to_expiration >= 2) {
            let p_t_up = price_core(underlying_price, strike_price, risk_free_rate, volatility, days_to_expiration + 1, steps, is_call);
            let p_t_dn = price_core(underlying_price, strike_price, risk_free_rate, volatility, days_to_expiration - 1, steps, is_call);
            // dP/dT_years ≈ (P(T+1d) - P(T-1d)) / (2/365) = (P+ - P-) * (365/2)
            let num = signed_from_diff(p_t_up, p_t_dn);
            // multiply by 365 then divide by 2
            let num_times_365 = Signed { neg: num.neg, mag: num.mag * 365u256 };
            Signed { neg: num_times_365.neg, mag: num_times_365.mag / 2 }
        } else {
            // Forward difference near T=0 or T=1
            let p_t_up = price_core(underlying_price, strike_price, risk_free_rate, volatility, days_to_expiration + 1, steps, is_call);
            // dP/dT_years ≈ (P(T+1d) - P(T)) / (1/365) = (P+ - P0) * 365
            let num = signed_from_diff(p_t_up, p0);
            Signed { neg: num.neg, mag: num.mag * 365u256 }
        };

        Greeks { delta, gamma, vega, theta, rho }
    }

    // Optional convenience getters (one Greek at a time)

    #[view]
    public fun get_delta(
        underlying_price: u256, 
        strike_price: u256, 
        risk_free_rate: u256,
        volatility: u256, 
        days_to_expiration: u64, 
        is_call: bool
    ): Signed {
        let g = get_greeks(underlying_price, strike_price, risk_free_rate, volatility, days_to_expiration, is_call);
        g.delta
    }

    #[view]
    public fun get_gamma(
        underlying_price: u256, 
        strike_price: u256, 
        risk_free_rate: u256,
        volatility: u256, 
        days_to_expiration: u64, 
        is_call: bool
    ): Signed {
        let g = get_greeks(underlying_price, strike_price, risk_free_rate, volatility, days_to_expiration, is_call);
        g.gamma
    }

    #[view]
    public fun get_vega(
        underlying_price: u256, 
        strike_price: u256, 
        risk_free_rate: u256,
        volatility: u256, 
        days_to_expiration: u64, 
        is_call: bool
    ): Signed {
        let g = get_greeks(underlying_price, strike_price, risk_free_rate, volatility, days_to_expiration, is_call);
        g.vega
    }

    #[view]
    public fun get_theta(
        underlying_price: u256, 
        strike_price: u256, 
        risk_free_rate: u256,
        volatility: u256, 
        days_to_expiration: u64, 
        is_call: bool
    ): Signed {
        let g = get_greeks(underlying_price, strike_price, risk_free_rate, volatility, days_to_expiration, is_call);
        g.theta
    }

    #[view]
    public fun get_rho(
        underlying_price: u256, 
        strike_price: u256, 
        risk_free_rate: u256,
        volatility: u256,
        days_to_expiration: u64, 
        is_call: bool
    ): Signed {
        let g = get_greeks(underlying_price, strike_price, risk_free_rate, volatility, days_to_expiration, is_call);
        g.rho
    }

    public fun new_option_greeks() : Greeks {
        Greeks {
            delta: Signed { neg: false, mag: 0 },
            gamma: Signed { neg: false, mag: 0 },
            vega: Signed { neg: false, mag: 0 },
            theta: Signed { neg: false, mag: 0 },
            rho: Signed { neg: false, mag: 0 }
        }
    }

    public fun get_signed_values(
        value: &Signed
    ) : (bool, u256) {
        (value.neg, value.mag)
    }


}
}