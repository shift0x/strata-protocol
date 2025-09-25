#[test_only]
module marketplace::implied_volatility_market_test {
    use std::string;
    use std::signer;
    use aptos_framework::timestamp;
    use aptos_framework::primary_fungible_store;
    use marketplace::implied_volatility_market;

    #[test(creator = @0x123, framework = @aptos_framework)]
    fun test_init_volatility_market_creates_pool_correctly(creator: signer, framework: signer) {
        // Setup test environment
        timestamp::set_time_has_started_for_testing(&framework);
        
        // Test parameters
        let asset_symbol = string::utf8(b"BTC");
        let initial_volatility = 25; // 25 USDC per IV token
        let expiration_timestamp = timestamp::now_seconds() + 86400; // 1 day from now
        
        // Initialize the market
        let market_addr = implied_volatility_market::init_volatility_market(
            &creator,
            asset_symbol,
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
        assert!(market_iv_balance == expected_iv_supply, 9);
        
        // Verify price ratio (25 USDC per 1 IV token)
        let price_ratio = usdc_reserves / iv_reserves; // Both have same decimals (6)
        assert!(price_ratio == initial_volatility, 10); // Should equal 25
    }

}
