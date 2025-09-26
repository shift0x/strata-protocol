#[test_only]
module marketplace::implied_volatility_market_test {
    use std::string;
    use std::signer;
    use aptos_framework::timestamp;
    use aptos_framework::object::{Self};
    use aptos_framework::fungible_asset::{Metadata};
    use aptos_framework::primary_fungible_store;
    use marketplace::implied_volatility_market;
    use marketplace::volatility_marketplace;

    #[test(creator = @0x123, framework = @aptos_framework)]
    fun test_init_volatility_market_creates_pool_correctly(creator: signer, framework: signer) {
        // Setup test environment
        timestamp::set_time_has_started_for_testing(&framework);

        // create marketplace
        volatility_marketplace::create_marketplace(&creator);
        
        // Get TestUSDC address from marketplace
        let marketplace_addr = signer::address_of(&creator);
        let usdc_metadata = volatility_marketplace::get_test_usdc_metadata(marketplace_addr);
        let usdc_address = object::object_address(&usdc_metadata);
        
        // Test parameters
        let asset_symbol = string::utf8(b"BTC");
        let initial_volatility = 25; // 25 USDC per IV token
        let expiration_timestamp = timestamp::now_seconds() + 86400; // 1 day from now
        
        // Initialize the market
        let market_addr = implied_volatility_market::init_volatility_market(
            &creator,
            asset_symbol,
            usdc_address,
            initial_volatility,
            expiration_timestamp
        );
        
        // Verify market was created
        assert!(market_addr != @0x0, 1);
        
        // Verify market metadata
        assert!(implied_volatility_market::get_owner(market_addr) == signer::address_of(&creator), 2);
        assert!(implied_volatility_market::get_asset_symbol(market_addr) == asset_symbol, 3);
        assert!(implied_volatility_market::get_volatility(market_addr) == initial_volatility, 4);
        assert!(implied_volatility_market::get_expiration(market_addr) == expiration_timestamp, 5);
        assert!(!implied_volatility_market::is_settled(market_addr), 6);
        
        // Verify AMM reserves
        let (iv_reserves, usdc_reserves) = implied_volatility_market::get_amm_reserves(market_addr);
        let expected_iv_supply = 1000000 * 1000000; // 1M tokens with 6 decimals
        let expected_usdc_reserves = expected_iv_supply * initial_volatility; // 25M USDC equivalent
        
        assert!(iv_reserves == expected_iv_supply, 7);
        assert!(usdc_reserves == expected_usdc_reserves, 8);
        
        // Verify tokens were minted to market object
        let iv_token_metadata = implied_volatility_market::get_iv_token_metadata(market_addr);
        let market_iv_balance = primary_fungible_store::balance(market_addr, iv_token_metadata);
        assert!((market_iv_balance as u256) == expected_iv_supply, 9);
        
        // Verify price ratio (25 USDC per 1 IV token)
        let price_ratio = usdc_reserves / iv_reserves; // Both have same decimals (6)
        assert!(price_ratio == initial_volatility, 10); // Should equal 25
    }

    #[test(creator = @0x123, framework = @aptos_framework)]
    fun test_get_swap_amount_out(creator: signer, framework: signer) {
        // Setup test environment
        timestamp::set_time_has_started_for_testing(&framework);

        // create marketplace
        volatility_marketplace::create_marketplace(&creator);
        
        // Get TestUSDC address from marketplace
        let marketplace_addr = signer::address_of(&creator);
        let usdc_metadata = volatility_marketplace::get_test_usdc_metadata(marketplace_addr);
        let usdc_address = object::object_address(&usdc_metadata);
        
        // Test parameters
        let asset_symbol = string::utf8(b"BTC");
        let initial_volatility = 25; // 25 USDC per IV token
        let expiration_timestamp = timestamp::now_seconds() + 86400;
        
        // Initialize the market
        let market_addr = implied_volatility_market::init_volatility_market(
            &creator,
            asset_symbol,
            usdc_address,
            initial_volatility,
            expiration_timestamp
        );
        
        // Get initial reserves
        let (iv_reserves, usdc_reserves) = implied_volatility_market::get_amm_reserves(market_addr);
        
        // Test buying IV tokens (USDC -> IV, swap_type = 0)
        let usdc_amount_in = 1000000; // 1 USDC (with 6 decimals)
        let iv_amount_out = implied_volatility_market::get_swap_amount_out(market_addr, 0, usdc_amount_in);
        
        // Verify constant product formula: amount_out = (amount_in * reserve_out) / (reserve_in + amount_in)
        let expected_iv_out = (usdc_amount_in * iv_reserves) / (usdc_reserves + usdc_amount_in);
        assert!(iv_amount_out == expected_iv_out, 1);
        
        // Test selling IV tokens (IV -> USDC, swap_type = 1)
        let iv_amount_in = 40000; // 0.04 IV tokens (with 6 decimals)  
        let usdc_amount_out = implied_volatility_market::get_swap_amount_out(market_addr, 1, iv_amount_in);
        
        // Verify constant product formula
        let expected_usdc_out = (iv_amount_in * usdc_reserves) / (iv_reserves + iv_amount_in);
        assert!(usdc_amount_out == expected_usdc_out, 2);
        
        // Test edge case: zero input should return zero output
        let zero_out_buy = implied_volatility_market::get_swap_amount_out(market_addr, 0, 0);
        let zero_out_sell = implied_volatility_market::get_swap_amount_out(market_addr, 1, 0);
        assert!(zero_out_buy == 0, 3);
        assert!(zero_out_sell == 0, 4);
        
        // Test that buying reduces price (more expensive for larger amounts)
        let small_buy_amount_in = 500000; // 0.5 USDC
        let large_buy_amount_in = 200000000; // 200 USDC
        let factor = 1000000;
        let small_buy_amount_out = implied_volatility_market::get_swap_amount_out(market_addr, 0, small_buy_amount_in);
        let large_buy_amount_out = implied_volatility_market::get_swap_amount_out(market_addr, 0, large_buy_amount_in);
        
        let small_buy_exchange_rate = (small_buy_amount_in*factor) / small_buy_amount_out;
        let large_buy_exchange_rate = (large_buy_amount_in * factor) / large_buy_amount_out;

        // Price impact: large buy should get worse rate than small buy
        assert!(large_buy_exchange_rate < small_buy_exchange_rate, 5);
    }

    #[test(creator = @0x123, trader = @0x456, framework = @aptos_framework)]
    fun test_marketplace_swap(creator: signer, trader: signer, framework: signer) {
        // Setup test environment
        timestamp::set_time_has_started_for_testing(&framework);

        // Create marketplace
        volatility_marketplace::create_marketplace(&creator);
        let marketplace_addr = signer::address_of(&creator);
        
        // Create a volatility market
        let asset_symbol = string::utf8(b"BTC");
        let initial_volatility = 25; // 25 USDC per IV token
        let expiration_timestamp = timestamp::now_seconds() + 86400;
        
        let market_id = volatility_marketplace::create_market(
            &creator,
            asset_symbol,
            initial_volatility,
            expiration_timestamp,
            marketplace_addr
        );

        // get the iv token address associated with the market
        let iv_metadata = volatility_marketplace::get_iv_token_metadata(marketplace_addr, market_id);

        // get the market address
        let market_address = volatility_marketplace::get_market_address(marketplace_addr, market_id);
        
        // Mint test USDC to trader
        let usdc_amount = 10000000; // 10 USDC
        volatility_marketplace::mint_test_usdc(&trader, usdc_amount, marketplace_addr);
        
        // Verify trader has USDC balance
        let usdc_metadata = volatility_marketplace::get_test_usdc_metadata(marketplace_addr);
        let trader_addr = signer::address_of(&trader);
        let initial_usdc_balance = primary_fungible_store::balance(trader_addr, usdc_metadata);
        assert!(initial_usdc_balance == usdc_amount, 1);

        // determine the expected output amount
        let usdc_input = 1000000; // 1 USDC
        let expected_amount_out = volatility_marketplace::get_swap_amount_out(
            marketplace_addr,
            market_id,
            0, // swap_type: USDC -> IV
            usdc_input
        );
        
        volatility_marketplace::swap(
            &trader,
            marketplace_addr,
            market_id,
            0, // swap_type: USDC -> IV
            usdc_input
        );
        
        // Verify swap balances
        let final_usdc_balance = primary_fungible_store::balance(trader_addr, usdc_metadata);
        let final_iv_balance = primary_fungible_store::balance(trader_addr, iv_metadata);
        let final_pool_usdc_balance = primary_fungible_store::balance(market_address, usdc_metadata);

        assert!(final_usdc_balance == initial_usdc_balance - usdc_input, 3);
        assert!(final_iv_balance == expected_amount_out, 4);
        assert!(final_pool_usdc_balance == usdc_input, 5);
        
        // Test swap: Sell IV tokens for USDC (swap_type = 1)
        let iv_input = final_iv_balance / 2; // Sell half the IV tokens
        let expected_usdc_output = volatility_marketplace::get_swap_amount_out(
            marketplace_addr,
            market_id,
            1, // swap_type: IV -> USDC
            iv_input
        );

        let expected_trader_usdc_balance = expected_usdc_output + final_usdc_balance;
        let expected_pool_usdc_balance = final_pool_usdc_balance - expected_usdc_output;
        
        volatility_marketplace::swap(
            &trader,
            marketplace_addr,
            market_id,
            1, // swap_type: IV -> USDC
            iv_input
        );

        // Verify swap balances
        let actual_trader_usdc_balance = primary_fungible_store::balance(trader_addr, usdc_metadata);
        let actual_pool_usdc_balance = primary_fungible_store::balance(market_address, usdc_metadata);
        
        assert!(actual_trader_usdc_balance == expected_trader_usdc_balance, 6);
        assert!(actual_pool_usdc_balance == expected_pool_usdc_balance, 6);
    }

}
