address marketplace {
module historical_volatility_calculator {
    use std::vector;

    // Fixed-point scale (18 decimals)
    const SCALE: u256 = 1000000000000000000;
    const HALF: u256 = SCALE / 2;
    const THREE_HALVES: u256 = SCALE + HALF;

    // ln(2) scaled by 1e18
    const LN2: u256 = 693147180559945309;

    // Number of terms in ln(1+z) series; increase for more precision if needed.
    const LN_SERIES_TERMS: u256 = 18;

    // Error codes
    const E_TOO_FEW_PRICES: u64 = 1;
    const E_ZERO_PRICE: u64 = 2;

    // Signed fixed-point number: value = (neg ? -mag : mag), 18 decimals
    struct SignedFixed has copy, drop, store {
        neg: bool,
        mag: u256,
    }

    // Public API: annualized historical volatility of prices, using log returns.
    // - prices: vector<u256> of prices scaled by 1e18
    // - periods_per_year: e.g., 252 for trading days, 365 for daily data, etc.
    // Returns u256 volatility scaled by 1e18
    public fun calculate_historical_volatility(
        prices: vector<u256>, 
        periods_per_year: u64
    ): u256 {
        let n_prices = vector::length(&prices);
        assert!(n_prices >= 2, E_TOO_FEW_PRICES);

        let i: u64 = 0;
        while (i < n_prices) {
            let p = *vector::borrow(&prices, i);
            assert!(p > 0, E_ZERO_PRICE);
            i = i + 1;
        };

        let sum_r = signed_zero();
        let sum_r2: u256 = 0;

        let idx: u64 = 1;
        while (idx < n_prices) {
            let p_prev = *vector::borrow(&prices, idx - 1);
            let p_curr = *vector::borrow(&prices, idx);

            let ln_prev = ln_fixed(p_prev);
            let ln_curr = ln_fixed(p_curr);
            let r = signed_sub(ln_curr, ln_prev); // log return

            sum_r = signed_add(sum_r, r);
            let r2 = mul_scale_down(r.mag, r.mag); // r^2 (scaled)
            sum_r2 = sum_r2 + r2;

            idx = idx + 1;
        };

        let n_ret_u64 = n_prices - 1;
        let n_ret = (n_ret_u64 as u256);

        // Mean of r^2
        let mean_r2 = sum_r2 / n_ret;

        // Mean of r
        let mean_r = signed_div_u(sum_r, n_ret);
        let mean_r_sq = mul_scale_down(mean_r.mag, mean_r.mag);

        // Population variance = E[r^2] - (E[r])^2 (clamp at 0 due to rounding)
        let var_pop = if (mean_r2 > mean_r_sq) { mean_r2 - mean_r_sq } else { 0 };

        // Unbiased sample variance: var_sample = var_pop * n / (n - 1) for n > 1
        let var_sample = if (n_ret_u64 > 1) {
            (var_pop * n_ret) / (n_ret - 1)
        } else {
            // With exactly one return, population == sample
            var_pop
        };

        // Annualize variance and take sqrt
        let ann_factor = (periods_per_year as u256);
        let var_annual = var_sample * ann_factor;

        sqrt_fixed(var_annual)
    }

    // =========================
    // Helpers: signed arithmetic
    // =========================

    fun signed_zero(): SignedFixed {
        SignedFixed { neg: false, mag: 0 }
    }

    fun signed_neg(a: SignedFixed): SignedFixed {
        if (a.mag == 0) SignedFixed { neg: false, mag: 0 } else SignedFixed { neg: !a.neg, mag: a.mag }
    }

    fun signed_add(a: SignedFixed, b: SignedFixed): SignedFixed {
        if (a.neg == b.neg) {
            SignedFixed { neg: a.neg, mag: a.mag + b.mag }
        } else {
            if (a.mag >= b.mag) {
                SignedFixed { neg: a.neg, mag: a.mag - b.mag }
            } else {
                SignedFixed { neg: b.neg, mag: b.mag - a.mag }
            }
        }
    }

    fun signed_sub(a: SignedFixed, b: SignedFixed): SignedFixed {
        signed_add(a, signed_neg(b))
    }

    // Multiply two fixed-point values and scale down by 1e18
    fun signed_mul_scaled(a: SignedFixed, b: SignedFixed): SignedFixed {
        let sign = (a.neg != b.neg);
        let mag = mul_scale_down(a.mag, b.mag);
        if (mag == 0) SignedFixed { neg: false, mag } else SignedFixed { neg: sign, mag }
    }

    // Divide signed by positive u256 (floor)
    fun signed_div_u(a: SignedFixed, d: u256): SignedFixed {
        if (a.mag == 0) {
            SignedFixed { neg: false, mag: 0 }
        } else {
            SignedFixed { neg: a.neg, mag: a.mag / d }
        }
    }

    // (a * b) / SCALE with floor
    fun mul_scale_down(a: u256, b: u256): u256 {
        (a * b) / SCALE
    }

    // =========================
    // sqrt for 18-dec fixed: sqrt(x_real) scaled to 1e18
    // Compute floor(sqrt(x_scaled * SCALE))
    // =========================
    fun sqrt_fixed(x_scaled: u256): u256 {
        let v = x_scaled * SCALE;
        sqrt_u256(v)
    }

    fun sqrt_u256(x: u256): u256 {
        if (x == 0) return 0;
        let r = x;
        let y = (r + 1) / 2;
        while (y < r) {
            r = y;
            y = (r + (x / r)) / 2;
        };
        r
    }

    // =========================
    // ln(x) for x>0, x is 18-dec fixed. Returns SignedFixed (scaled 1e18).
    // ln(x) = k*ln(2) + ln(1+z), where y = x adjusted into [0.5, 1.5], z = (y - 1).
    // =========================
    fun ln_fixed(x: u256): SignedFixed {
        assert!(x > 0, E_ZERO_PRICE);

        let y = x;
        let k_pos: u64 = 0;
        let k_neg: u64 = 0;

        while (y < HALF) {
            // y *= 2, k--
            y = y * 2;
            k_neg = k_neg + 1;
        };
        while (y > THREE_HALVES) {
            // y /= 2, k++
            y = y / 2;
            k_pos = k_pos + 1;
        };

        // z = y - 1 (signed, scaled 1e18)
        let z = if (y >= SCALE) {
            SignedFixed { neg: false, mag: y - SCALE }
        } else {
            SignedFixed { neg: true, mag: SCALE - y }
        };

        // ln(1+z) series: sum_{n=1..N} (-1)^{n+1} z^n / n
        let sum = z;
        let power = z; // z^1
        let n: u256 = 2;
        while (n <= LN_SERIES_TERMS) {
            power = signed_mul_scaled(power, z); // z^n
            let term_neg = power.neg;
            if ((n % 2) == 0) { term_neg = !term_neg }; // flip sign for even n
            let term_mag = power.mag / n;
            let term = SignedFixed { neg: term_neg, mag: term_mag };
            sum = signed_add(sum, term);
            n = n + 1;
        };

        // k * ln(2)
        let k_term = if (k_pos >= k_neg) {
            let diff = ((k_pos - k_neg) as u256) * LN2;
            SignedFixed { neg: false, mag: diff }
        } else {
            let diff = ((k_neg - k_pos) as u256) * LN2;
            SignedFixed { neg: true, mag: diff }
        };

        signed_add(sum, k_term)
    }
}
}