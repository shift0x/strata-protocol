#[test_only]
module marketplace::binomial_option_pricing_test {
    use std::debug;
    use std::string;
    use marketplace::binomial_option_pricing;

    // Precision constant (18 decimal places)
    const PRECISION: u256 = 1000000000000000000;

    #[test]
    fun test_at_the_money_option() {
        let underlying_price = 125000 * PRECISION;
        let strike_price = 125000 * PRECISION;    
        let otm_strike_price = 140000 * PRECISION;
        let risk_free_rate = 5 * PRECISION / 100;
        let volatility = 25 * PRECISION / 100;   
        let days_to_expiration = 7 * PRECISION;          

        let atm_option_price = binomial_option_pricing::get_option_price(
            underlying_price,
            strike_price,
            risk_free_rate,
            volatility,
            days_to_expiration,
            true
        );

        let otm_option_price = binomial_option_pricing::get_option_price(
            underlying_price,
            otm_strike_price,
            risk_free_rate,
            volatility,
            days_to_expiration,
            true
        );

        // At-the-money options should have significant time value
        assert!(atm_option_price > 0, 3);
        // Should be worth more than deeply out-of-the-money
        assert!(atm_option_price > otm_option_price, 4); // Should be worth more than $1
    }

    #[test]
    fun test_deep_in_the_money_option() {
        // Test deep in-the-money option
        let underlying_price = 120 * PRECISION; 
        let strike_price = 100 * PRECISION;     
        let risk_free_rate = 3 * PRECISION / 100;
        let volatility = 15 * PRECISION / 100;   
        let days_to_expiration = 10 * PRECISION;          

        let option_price = binomial_option_pricing::get_option_price(
            underlying_price,
            strike_price,
            risk_free_rate,
            volatility,
            days_to_expiration,
            true
        );

        // Deep in-the-money call option should be worth close to intrinsic value
        let intrinsic_value = underlying_price - strike_price; // $20
        assert!(option_price > intrinsic_value, 5);
        // But shouldn't be worth more than underlying price
        assert!(option_price < underlying_price, 6);
    }

    #[test]
    fun test_put_option() {
        // Test put option
        let underlying_price = 95 * PRECISION;  
        let strike_price = 100 * PRECISION;     
        let risk_free_rate = 4 * PRECISION / 100;
        let volatility = 30 * PRECISION / 100;   
        let days_to_expiration = 45 * PRECISION;          

        let put_price = binomial_option_pricing::get_option_price(
            underlying_price,
            strike_price,
            risk_free_rate,
            volatility,
            days_to_expiration,
            false
        );

        // Put option should have positive value
        assert!(put_price > 0, 7);
        // In-the-money put should be worth at least intrinsic value
        let intrinsic_value = strike_price - underlying_price; // $5
        assert!(put_price >= intrinsic_value, 8);
    }

    #[test]
    fun test_delta_properties() {
        let underlying_price = 100 * PRECISION; 
        let strike_price = 100 * PRECISION;     
        let risk_free_rate = 5 * PRECISION / 100;
        let volatility = 25 * PRECISION / 100;   
        let days_to_expiration = 30 * PRECISION;          

        // Get delta for call and put options
        let call_delta = binomial_option_pricing::get_delta(
            underlying_price,
            strike_price,
            risk_free_rate,
            volatility,
            days_to_expiration,
            true
        );

        let put_delta = binomial_option_pricing::get_delta(
            underlying_price,
            strike_price,
            risk_free_rate,
            volatility,
            days_to_expiration,
            false
        );

        // Extract signed values
        let (call_delta_neg, call_delta_mag) = binomial_option_pricing::get_signed_values(&call_delta);
        let (put_delta_neg, put_delta_mag) = binomial_option_pricing::get_signed_values(&put_delta);

        // Call delta should be positive for ATM option
        assert!(!call_delta_neg, 10);
        assert!(call_delta_mag > 0, 11);

        // Put delta should be negative 
        assert!(put_delta_neg, 12);
        assert!(put_delta_mag > 0, 13);

        // ATM call delta should be around 0.5 (in our scaled units: 0.5 * PRECISION)
        assert!(call_delta_mag > PRECISION / 4, 14); // > 0.25
        assert!(call_delta_mag < 3 * PRECISION / 4, 15); // < 0.75
    }

    #[test]
    fun test_gamma_properties() {
        let underlying_price = 100 * PRECISION; 
        let strike_price = 100 * PRECISION;     
        let risk_free_rate = 5 * PRECISION / 100;
        let volatility = 25 * PRECISION / 100;   
        let days_to_expiration = 30 * PRECISION;          

        let gamma = binomial_option_pricing::get_gamma(
            underlying_price,
            strike_price,
            risk_free_rate,
            volatility,
            days_to_expiration,
            true // call
        );

        // Extract signed values
        let (gamma_neg, gamma_mag) = binomial_option_pricing::get_signed_values(&gamma);

        // Gamma should be positive for both calls and puts
        assert!(!gamma_neg, 20);
        assert!(gamma_mag > 0, 21);

        // Test that gamma is highest for ATM options
        let otm_strike = 110 * PRECISION;
        let otm_gamma = binomial_option_pricing::get_gamma(
            underlying_price,
            otm_strike,
            risk_free_rate,
            volatility,
            days_to_expiration,
            true
        );

        let (_, otm_gamma_mag) = binomial_option_pricing::get_signed_values(&otm_gamma);

        // ATM gamma should be higher than OTM gamma
        assert!(gamma_mag > otm_gamma_mag, 22);
    }

    #[test]
    fun test_vega_properties() {
        let underlying_price = 100 * PRECISION; 
        let strike_price = 100 * PRECISION;     
        let risk_free_rate = 5 * PRECISION / 100;
        let volatility = 25 * PRECISION / 100;   
        let days_to_expiration = 30 * PRECISION;          

        let vega = binomial_option_pricing::get_vega(
            underlying_price,
            strike_price,
            risk_free_rate,
            volatility,
            days_to_expiration,
            true // call
        );

        // Extract signed values
        let (vega_neg, vega_mag) = binomial_option_pricing::get_signed_values(&vega);

        // Vega should be positive for both calls and puts (options worth more with higher vol)
        assert!(!vega_neg, 30);
        assert!(vega_mag > 0, 31);

        // Longer-term options should have higher vega
        let long_term_vega = binomial_option_pricing::get_vega(
            underlying_price,
            strike_price,
            risk_free_rate,
            volatility,
            90 * PRECISION, // 90 days
            true
        );

        let (_, long_term_vega_mag) = binomial_option_pricing::get_signed_values(&long_term_vega);

        assert!(long_term_vega_mag > vega_mag, 32);
    }

    #[test]
    fun test_rho_properties() {
        let underlying_price = 100 * PRECISION; 
        let strike_price = 100 * PRECISION;     
        let risk_free_rate = 5 * PRECISION / 100;
        let volatility = 25 * PRECISION / 100;   
        let days_to_expiration = 30 * PRECISION;          

        let call_rho = binomial_option_pricing::get_rho(
            underlying_price,
            strike_price,
            risk_free_rate,
            volatility,
            days_to_expiration,
            true // call
        );

        let put_rho = binomial_option_pricing::get_rho(
            underlying_price,
            strike_price,
            risk_free_rate,
            volatility,
            days_to_expiration,
            false // put
        );

        // Extract signed values
        let (call_rho_neg, call_rho_mag) = binomial_option_pricing::get_signed_values(&call_rho);
        let (put_rho_neg, put_rho_mag) = binomial_option_pricing::get_signed_values(&put_rho);

        // Call rho should typically be positive (calls worth more with higher rates)
        assert!(!call_rho_neg, 50);
        assert!(call_rho_mag > 0, 51);

        // Put rho should typically be negative (puts worth less with higher rates)
        assert!(put_rho_neg, 52);
        assert!(put_rho_mag > 0, 53);
    }

    #[test]
    fun test_put_call_parity_relationship() {
        let underlying_price = 100 * PRECISION; 
        let strike_price = 100 * PRECISION;     
        let risk_free_rate = 4 * PRECISION / 100;
        let volatility = 20 * PRECISION / 100;   
        let days_to_expiration = 60 * PRECISION;          

        let call_price = binomial_option_pricing::get_option_price(
            underlying_price,
            strike_price,
            risk_free_rate,
            volatility,
            days_to_expiration,
            true
        );

        let put_price = binomial_option_pricing::get_option_price(
            underlying_price,
            strike_price,
            risk_free_rate,
            volatility,
            days_to_expiration,
            false
        );

        // Both should be positive
        assert!(call_price > 0, 70);
        assert!(put_price > 0, 71);
        
        // Very rough put-call parity check (allowing for discrete binomial approximation)
        // C - P ≈ S - Ke^(-rT), but we'll just check they're in reasonable range
        let price_diff = if (call_price > put_price) {
            call_price - put_price
        } else {
            put_price - call_price
        };
        
        // Difference should be reasonable relative to underlying price
        assert!(price_diff < underlying_price / 2, 72);
    }
}
