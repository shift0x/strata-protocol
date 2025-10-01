#[test_only]
module marketplace::volatility_marketplace_test {
    use std::string;
    use std::signer;
    use std::debug;
    use aptos_framework::timestamp;
    use marketplace::volatility_marketplace;

    // Test constants - matches the scaling used in OptionsExchange
    const ONE_E6: u256 = 1000000; // 1e6 scaling factor
    const ONE_E12: u256 = 1000000000000; // 1e12 scaling factor

    #[test(creator = @0x123, framework = @aptos_framework)]
    fun test_get_implied_volatility(creator: signer, framework: signer) {
        // Setup test environment
        timestamp::set_time_has_started_for_testing(&framework);

        // Create marketplace
        volatility_marketplace::create_marketplace(&creator);
        let marketplace_addr = signer::address_of(&creator);
        
        // Test parameters
        let asset_symbol = string::utf8(b"BTC");
        let expiration_timestamp = timestamp::now_seconds() + 86400; // 1 day from now
        
        // Create first market with volatility 25
        let volatility_25 = 25 * ONE_E6;
        let (market_id_1, market_addr_1) = volatility_marketplace::create_market(
            &creator,
            asset_symbol,
            volatility_25,
            expiration_timestamp,
            marketplace_addr
        );

        // Get implied volatility for one market - should be 25
        let implied_vol = volatility_marketplace::get_implied_volatility(marketplace_addr, asset_symbol);
        let expected_vol_25 = volatility_25 * ONE_E12;
        assert!(implied_vol == expected_vol_25, 1);
        
        // Create second market with volatility 35
        let expiration_timestamp_2 = timestamp::now_seconds() + 172800; // 2 days from now
        let (market_id_2, market_addr_2) = volatility_marketplace::create_market(
            &creator,
            asset_symbol,
            35 * ONE_E6,
            expiration_timestamp_2,
            marketplace_addr
        );
        
        // Get implied volatility for two markets - should be average (25+35)/2 = 30
        let implied_vol_avg = volatility_marketplace::get_implied_volatility(marketplace_addr, asset_symbol);
        let expected_vol_30 = 30 * ONE_E12 * ONE_E6;
        assert!(implied_vol_avg == expected_vol_30, 2);
    }
}
