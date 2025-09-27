#[test_only]
module marketplace::implied_volatility_market_test {
    use std::string;
    use std::signer;
    use std::debug;
    use aptos_framework::timestamp;
    use aptos_framework::object::{Self};
    use aptos_framework::fungible_asset::{Metadata};
    use aptos_framework::primary_fungible_store;
    use marketplace::implied_volatility_market;
    use marketplace::volatility_marketplace;
    use marketplace::isolated_margin_account;
    use marketplace::staking_vault;

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
        let vault_address = volatility_marketplace::get_staking_vault_address(marketplace_addr);
        let market_addr = implied_volatility_market::init_volatility_market(
            &creator,
            asset_symbol,
            usdc_address,
            initial_volatility,
            expiration_timestamp,
            vault_address
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

        let (market_id, market_address) = volatility_marketplace::create_market(
            &creator,
            asset_symbol,
            initial_volatility,
            expiration_timestamp,
            marketplace_addr
        );

        // get the iv token address associated with the market
        let iv_metadata = implied_volatility_market::get_iv_token_metadata(market_address);
        
        // Mint test USDC to trader
        let usdc_amount = 10000000; // 10 USDC
        let trader_addr = signer::address_of(&trader);

        volatility_marketplace::mint_test_usdc(usdc_amount, trader_addr, marketplace_addr);
        
        // Verify trader has USDC balance
        let usdc_metadata = volatility_marketplace::get_test_usdc_metadata(marketplace_addr);
        
        let initial_usdc_balance = primary_fungible_store::balance(trader_addr, usdc_metadata);
        assert!(initial_usdc_balance == usdc_amount, 1);

        // determine the expected output amount
        let usdc_input = 1000000; // 1 USDC
        let (expected_amount_out, expected_fee) = implied_volatility_market::get_swap_amount_out(
            market_address,
            0, // swap_type: USDC -> IV
            usdc_input
        );
        
        implied_volatility_market::swap(
            &trader,
            market_address,
            0, // swap_type: USDC -> IV
            usdc_input
        );
        
        // Verify swap balances
        let final_usdc_balance = primary_fungible_store::balance(trader_addr, usdc_metadata);
        let final_iv_balance = primary_fungible_store::balance(trader_addr, iv_metadata);
        let final_pool_usdc_balance = primary_fungible_store::balance(market_address, usdc_metadata);

        assert!(final_usdc_balance == initial_usdc_balance - usdc_input, 3);
        assert!(final_iv_balance == expected_amount_out, 4);
        assert!(final_pool_usdc_balance == usdc_input - expected_fee, 5);
        
        // Test swap: Sell IV tokens for USDC (swap_type = 1)
        let iv_input = (final_iv_balance / 2) as u64; // Sell half the IV tokens
        let (expected_usdc_output, expected_fee) = implied_volatility_market::get_swap_amount_out(
            market_address,
            1, // swap_type: IV -> USDC
            iv_input
        );

        let expected_trader_usdc_balance = expected_usdc_output + final_usdc_balance;
        let expected_pool_usdc_balance = final_pool_usdc_balance - expected_usdc_output - expected_fee;
        
        implied_volatility_market::swap(
            &trader,
            market_address,
            1, // swap_type: IV -> USDC
            iv_input
        );

        // Verify swap balances
        let actual_trader_usdc_balance = primary_fungible_store::balance(trader_addr, usdc_metadata);
        let actual_pool_usdc_balance = primary_fungible_store::balance(market_address, usdc_metadata);
        
        assert!(actual_trader_usdc_balance == expected_trader_usdc_balance, 6);
        assert!(actual_pool_usdc_balance == expected_pool_usdc_balance, 6);
    }

    #[test(creator = @0x123, framework = @aptos_framework)]
    fun test_get_quote(creator: signer, framework: signer) {
        // Setup test environment
        timestamp::set_time_has_started_for_testing(&framework);

        // Create marketplace
        volatility_marketplace::create_marketplace(&creator);
        let marketplace_addr = signer::address_of(&creator);
        
        // Create a volatility market
        let asset_symbol = string::utf8(b"ETH");
        let initial_volatility = 30; 
        let expiration_timestamp = timestamp::now_seconds() + 86400;
        
        let (market_id, market_address) = volatility_marketplace::create_market(
            &creator,
            asset_symbol,
            initial_volatility,
            expiration_timestamp,
            marketplace_addr
        );

        // Test get_quote
        let factor = 1000000; // 10^6
        let quote = implied_volatility_market::get_quote(market_address);
        let expected_quote = (initial_volatility as u64) * factor;

        assert!(quote == expected_quote, 1);
    }

    #[test(creator = @0x123, trader = @0x456, staker = @0x789, framework = @aptos_framework)]
    fun test_open_short_position(creator: signer, trader: signer, staker: signer, framework: signer) {
        // Setup test environment
        timestamp::set_time_has_started_for_testing(&framework);

        // Create marketplace
        volatility_marketplace::create_marketplace(&creator);
        let marketplace_addr = signer::address_of(&creator);

        // Mint test tokens to the staker signer
        let staking_amount = 100000 * 1000000; // 100K USDC
        let staker_address = signer::address_of(&staker);
        volatility_marketplace::mint_test_usdc(staking_amount, staker_address, marketplace_addr);

        // Stake tokens to faciliate borrows
        let vault_address = volatility_marketplace::get_staking_vault_address(marketplace_addr);
        staking_vault::stake(&staker, vault_address, staking_amount);
        
        // Create a volatility market
        let asset_symbol = string::utf8(b"BTC");
        let initial_volatility = 25; // 25 USDC per IV token
        let expiration_timestamp = timestamp::now_seconds() + 86400;
        
        let (market_id, market_address) = volatility_marketplace::create_market(
            &creator,
            asset_symbol,
            initial_volatility,
            expiration_timestamp,
            marketplace_addr
        );

        // Mint test USDC to trader for collateral
        let collateral_amount = 5000000; // 5 USDC
        let trader_addr = signer::address_of(&trader);

        volatility_marketplace::mint_test_usdc(collateral_amount, trader_addr, marketplace_addr);

        // Mint test USDC to liquidity pool
        let usdc_amount = 1000 *1000000; // 1000 USDC
        let usdc_metadata = volatility_marketplace::get_test_usdc_metadata(marketplace_addr);

        volatility_marketplace::mint_test_usdc(usdc_amount, market_address, marketplace_addr);

        // Get initial AMM reserves
        let starting_quote = implied_volatility_market::get_quote(market_address);
        
        // Open short position
        implied_volatility_market::open_short_position(
            &trader,
            market_address,
            collateral_amount
        );
        
        // Verify AMM pool price has moved lower because of the short sale
        let ending_quote = implied_volatility_market::get_quote(market_address);
        assert!(ending_quote < starting_quote, 1);

        // Verify that we have properly created the short position in the margin account
        let expected_iv_units_borrowed = (collateral_amount * 1000000) / starting_quote;
        let account_state = implied_volatility_market::get_margin_account_state(market_address, trader_addr);

        let actual_collateral = isolated_margin_account::get_collateral(&account_state);
        let actual_iv_units_borrowed = isolated_margin_account::get_iv_units_borrowed(&account_state);

        assert!(actual_collateral == collateral_amount, 2);
        assert!(actual_iv_units_borrowed == expected_iv_units_borrowed, 3);
    }



}
