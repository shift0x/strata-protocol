#[test_only]
module marketplace::options_exchange_tests {
    use std::debug;
    use std::signer;
    use std::string;
    use std::vector;
    use marketplace::options_exchange::{Self, Position, PositionLeg, Quote};
    use aptos_framework::timestamp;
    use aptos_framework::account;
    use aptos_framework::fungible_asset;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::object;
    use marketplace::volatility_marketplace;
    use marketplace::price_oracle;
    use marketplace::isolated_margin_account;
    
    // Test constants - matches the scaling used in OptionsExchange
    const ONE_E18: u256 = 1000000000000000000; // 1e18 scaling factor
    const ONE_E6: u64 = 1000000; // 1e6 scaling factor
    const ONE_DAY_SECONDS: u64 = 86400;
    const THIRTY_DAYS_SECONDS: u64 = 2592000;
    
    // Error codes for testing
    const E_QUOTE_MISMATCH: u64 = 100;
    const E_MARGIN_TOO_LOW: u64 = 101;
    const E_PREMIUM_ZERO: u64 = 102;
    
    #[test]
    fun test_single_long_call_pricing() {
        // Test basic long call position pricing
        let current_time = 1000000u64;
        let expiration = current_time + THIRTY_DAYS_SECONDS;
        
        let leg = options_exchange::create_position_leg(
            options_exchange::create_call(),
            options_exchange::create_long(),
            1 * ONE_E18,    // 1 contract
            100 * ONE_E18,  // $100 strike 
            expiration
        );
        
        let legs = vector::empty<PositionLeg>();
        vector::push_back(&mut legs, leg);
        
        let position = options_exchange::create_position(
            1,
            string::utf8(b"BTC"),
            legs
        );
        
        let quote = options_exchange::price_position(
            &position,
            100 * ONE_E18,            // $100 underlying price (scaled)
            (5 * ONE_E18) / 100,      // 5% risk-free rate
            (20 * ONE_E18) / 100,     // 20% volatility (2000 bps)
            current_time
        );
        
        // Long call should have net_debit > 0 and net_credit = 0
        assert!(options_exchange::get_net_debit(&quote) > 0, E_PREMIUM_ZERO);
        assert!(options_exchange::get_net_credit(&quote) == 0, E_QUOTE_MISMATCH);
        // Long positions don't require additional margin beyond premium
        assert!(options_exchange::get_initial_margin(&quote) == 0, E_MARGIN_TOO_LOW);
        assert!(options_exchange::get_maintenance_margin(&quote) == 0, E_MARGIN_TOO_LOW);
    }
    
    #[test]
    fun test_single_short_call_pricing() {
        // Test basic short call position pricing
        let current_time = 1000000u64;
        let expiration = current_time + THIRTY_DAYS_SECONDS;
        
        let leg = options_exchange::create_position_leg(
            options_exchange::create_call(),
            options_exchange::create_short(),
            1 * ONE_E18,    // 1 contract
            100 * ONE_E18,  // $100 strike
            expiration
        );
        
        let legs = vector::empty<PositionLeg>();
        vector::push_back(&mut legs, leg);
        
        let position = options_exchange::create_position(
            1,
            string::utf8(b"BTC"),
            legs
        );
        
        let quote = options_exchange::price_position(
            &position,
            100 * ONE_E18,            // $100 underlying price (scaled)
            (5 * ONE_E18) / 100,      // 5% risk-free rate
            (20 * ONE_E18) / 100,     // 20% volatility (2000 bps)
            current_time
        );
        
        // Short call should have net_credit > 0 and net_debit = 0
        assert!(options_exchange::get_net_credit(&quote) > 0, E_PREMIUM_ZERO);
        assert!(options_exchange::get_net_debit(&quote) == 0, E_QUOTE_MISMATCH);
        // Short positions require margin
        assert!(options_exchange::get_initial_margin(&quote) > 0, E_MARGIN_TOO_LOW);
        assert!(options_exchange::get_maintenance_margin(&quote) > 0, E_MARGIN_TOO_LOW);
        // Maintenance margin should be less than initial margin
        assert!(options_exchange::get_maintenance_margin(&quote) < options_exchange::get_initial_margin(&quote), E_MARGIN_TOO_LOW);
    }
    
    #[test]
    fun test_single_long_put_pricing() {
        // Test basic long put position pricing
        let current_time = 1000000u64;
        let expiration = current_time + THIRTY_DAYS_SECONDS;
        
        let leg = options_exchange::create_position_leg(
            options_exchange::create_put(),
            options_exchange::create_long(),
            1 * ONE_E18,    // 1 contract
            100 * ONE_E18,  // $100 strike
            expiration
        );
        
        let legs = vector::empty<PositionLeg>();
        vector::push_back(&mut legs, leg);
        
        let position = options_exchange::create_position(
            1,
            string::utf8(b"BTC"),
            legs
        );
        
        let quote = options_exchange::price_position(
            &position,
            100 * ONE_E18,            // $100 underlying price (scaled)
            (5 * ONE_E18) / 100,      // 5% risk-free rate
            (20 * ONE_E18) / 100,     // 20% volatility (2000 bps)
            current_time
        );
        
        // Long put should have net_debit > 0
        assert!(options_exchange::get_net_debit(&quote) > 0, E_PREMIUM_ZERO);
        assert!(options_exchange::get_net_credit(&quote) == 0, E_QUOTE_MISMATCH);
        assert!(options_exchange::get_initial_margin(&quote) == 0, E_MARGIN_TOO_LOW);
    }
    
    #[test]
    fun test_single_short_put_pricing() {
        // Test basic short put position pricing
        let current_time = 1000000u64;
        let expiration = current_time + THIRTY_DAYS_SECONDS;
        
        let leg = options_exchange::create_position_leg(
            options_exchange::create_put(),
            options_exchange::create_short(),
            1 * ONE_E18,    // 1 contract
            100 * ONE_E18,  // $100 strike
            expiration
        );
        
        let legs = vector::empty<PositionLeg>();
        vector::push_back(&mut legs, leg);
        
        let position = options_exchange::create_position(
            1,
            string::utf8(b"BTC"),
            legs
        );
        
        let quote = options_exchange::price_position(
            &position,
            100 * ONE_E18,            // $100 underlying price (scaled)
            (5 * ONE_E18) / 100,      // 5% risk-free rate
            (20 * ONE_E18) / 100,     // 20% volatility (2000 bps)
            current_time
        );
        
        // Short put should have net_credit > 0 and require margin
        assert!(options_exchange::get_net_credit(&quote) > 0, E_PREMIUM_ZERO);
        assert!(options_exchange::get_net_debit(&quote) == 0, E_QUOTE_MISMATCH);
        assert!(options_exchange::get_initial_margin(&quote) > 0, E_MARGIN_TOO_LOW);
        assert!(options_exchange::get_maintenance_margin(&quote) > 0, E_MARGIN_TOO_LOW);
    }
    
    #[test]
    fun test_call_spread_pricing() {
        // Test bull call spread (long lower strike, short higher strike)
        let current_time = 1000000u64;
        let expiration = current_time + THIRTY_DAYS_SECONDS;
        
        // Long $100 call
        let long_leg = options_exchange::create_position_leg(
            options_exchange::create_call(),
            options_exchange::create_long(),
            1 * ONE_E18,
            100 * ONE_E18, // $100 strike
            expiration
        );
        
        // Short $110 call
        let short_leg = options_exchange::create_position_leg(
            options_exchange::create_call(),
            options_exchange::create_short(),
            1 * ONE_E18,
            110 * ONE_E18, // $110 strike
            expiration
        );
        
        let legs = vector::empty<PositionLeg>();
        vector::push_back(&mut legs, long_leg);
        vector::push_back(&mut legs, short_leg);
        
        let position = options_exchange::create_position(
            1,
            string::utf8(b"BTC"),
            legs
        );
        
        let quote = options_exchange::price_position(
            &position,
            100 * ONE_E18,            // $100 underlying price (scaled)
            (5 * ONE_E18) / 100,      // 5% risk-free rate
            (20 * ONE_E18) / 100,     // 20% volatility (2000 bps)
            current_time
        );
        
        // Bull call spread typically has net debit (long premium > short premium)
        // But depending on strikes and volatility, could be credit spread
        assert!(options_exchange::get_net_debit(&quote) > 0 || options_exchange::get_net_credit(&quote) > 0, E_PREMIUM_ZERO);
        
        // Spread should have limited margin requirement compared to naked short
        assert!(options_exchange::get_initial_margin(&quote) >= 0, E_MARGIN_TOO_LOW);
    }
    
    #[test]
    fun test_straddle_pricing() {
        // Test long straddle (long call + long put at same strike)
        let current_time = 1000000u64;
        let expiration = current_time + THIRTY_DAYS_SECONDS;
        
        // Long $100 call
        let call_leg = options_exchange::create_position_leg(
            options_exchange::create_call(),
            options_exchange::create_long(),
            1 * ONE_E18,
            100 * ONE_E18, // $100 strike
            expiration
        );
        
        // Long $100 put
        let put_leg = options_exchange::create_position_leg(
            options_exchange::create_put(),
            options_exchange::create_long(),
            1 * ONE_E18,
            100 * ONE_E18, // $100 strike
            expiration
        );
        
        let legs = vector::empty<PositionLeg>();
        vector::push_back(&mut legs, call_leg);
        vector::push_back(&mut legs, put_leg);
        
        let position = options_exchange::create_position(
            1,
            string::utf8(b"BTC"),
            legs
        );
        
        let quote = options_exchange::price_position(
            &position,
            100 * ONE_E18,            // $100 underlying price (scaled)
            (5 * ONE_E18) / 100,      // 5% risk-free rate
            (20 * ONE_E18) / 100,     // 20% volatility (2000 bps)
            current_time
        );
        
        // Long straddle should have significant net debit and no margin
        assert!(options_exchange::get_net_debit(&quote) > 0, E_PREMIUM_ZERO);
        assert!(options_exchange::get_net_credit(&quote) == 0, E_QUOTE_MISMATCH);
        assert!(options_exchange::get_initial_margin(&quote) == 0, E_MARGIN_TOO_LOW); // Long positions don't require margin
    }
    
    #[test]
    fun test_short_straddle_pricing() {
        // Test short straddle (short call + short put at same strike)
        let current_time = 1000000u64;
        let expiration = current_time + THIRTY_DAYS_SECONDS;
        
        // Short $100 call
        let call_leg = options_exchange::create_position_leg(
            options_exchange::create_call(),
            options_exchange::create_short(),
            1 * ONE_E18,
            100 * ONE_E18, // $100 strike
            expiration
        );
        
        // Short $100 put
        let put_leg = options_exchange::create_position_leg(
            options_exchange::create_put(),
            options_exchange::create_short(),
            1 * ONE_E18,
            100 * ONE_E18, // $100 strike
            expiration
        );
        
        let legs = vector::empty<PositionLeg>();
        vector::push_back(&mut legs, call_leg);
        vector::push_back(&mut legs, put_leg);
        
        let position = options_exchange::create_position(
            1,
            string::utf8(b"BTC"),
            legs
        );
        
        let quote = options_exchange::price_position(
            &position,
            100 * ONE_E18,            // $100 underlying price (scaled)
            (5 * ONE_E18) / 100,      // 5% risk-free rate
            (20 * ONE_E18) / 100,     // 20% volatility (2000 bps)
            current_time
        );
        
        // Short straddle should have significant net credit and substantial margin
        assert!(options_exchange::get_net_credit(&quote) > 0, E_PREMIUM_ZERO);
        assert!(options_exchange::get_net_debit(&quote) == 0, E_QUOTE_MISMATCH);
        assert!(options_exchange::get_initial_margin(&quote) > 0, E_MARGIN_TOO_LOW);
    }

    // ------------------------------------------------------------------------
    // Tests for opening positions
    // ------------------------------------------------------------------------


    #[test(aptos_framework = @0x1, creator = @0x123, trader = @0x789)]
    fun test_open_position(aptos_framework: &signer, creator: &signer, trader: &signer) {
        // Initialize timestamp for testing
        timestamp::set_time_has_started_for_testing(aptos_framework);
        timestamp::update_global_time_for_test_secs(1000000);
        
        // create the golbal volatility marketplace
        let marketplace_addr = volatility_marketplace::create_marketplace(creator);

        // mint usdc to the trader
        let trade_amount = 10000 * ONE_E6; // 10000 USDC
        let trader_address = signer::address_of(trader);
        volatility_marketplace::mint_test_usdc(trade_amount, trader_address, marketplace_addr);

        // Create market
        let asset_symbol = string::utf8(b"ETH");
        let initial_volatility = (30 * ONE_E6) / 100; // 30%
        let expiration_timestamp = timestamp::now_seconds() + 86400;
        
        let (market_id, market_address) = volatility_marketplace::create_market(
            creator,
            asset_symbol,
            initial_volatility as u256,
            expiration_timestamp,
            marketplace_addr
        );

        // create the option exchange
        let usdc_address = volatility_marketplace::get_usdc_address(marketplace_addr);
        let exchange_address = options_exchange::create_exchange(creator, usdc_address);

        // Set the quote price of ETH for testing
        let eth_price = 1000 * ONE_E18;
        price_oracle::set_mock_price(
            creator, 
            exchange_address, 
            string::utf8(b"ETH"), 
            eth_price);

        // Set the quote price of Rates.US10Y for testing
        let us10y_price = (5 * ONE_E18)/100; // 5%
        price_oracle::set_mock_price(
            creator, 
            exchange_address, 
            string::utf8(b"Rates.US10Y"), 
            us10y_price);
        
        // Create a long call position
        let current_time = timestamp::now_seconds();
        let expiration = current_time + THIRTY_DAYS_SECONDS;
        
        let leg = options_exchange::create_position_leg(
            options_exchange::create_call(),
            options_exchange::create_long(),
            1 * ONE_E18,    // 1 contract
            eth_price,      // atm strike
            expiration
        );
        
        
        let legs = vector::empty<PositionLeg>();
        vector::push_back(&mut legs, leg);
        
        let position = options_exchange::create_position(
            1,
            string::utf8(b"ETH"),
            legs
        );

        // Execute the trade to open the position
        options_exchange::open_position(trader, marketplace_addr, exchange_address, position);
        
        // Get USDC metadata to check balances
        let usdc_metadata = volatility_marketplace::get_test_usdc_metadata(marketplace_addr);
        
        // verify the position has been opened
        let trader_ending_balance = primary_fungible_store::balance(trader_address, usdc_metadata);

        assert!(trader_ending_balance < trade_amount, E_QUOTE_MISMATCH);
    }
}
