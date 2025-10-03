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
        let marketplace_addr = volatility_marketplace::create_marketplace(&creator);
        
        // Get TestUSDC address from marketplace
        let usdc_metadata = volatility_marketplace::get_test_usdc_metadata(marketplace_addr);
        let usdc_address = object::object_address(&usdc_metadata);
        
        // Test parameters
        let asset_symbol = string::utf8(b"BTC");
        let initial_volatility = 25 * 1000000; // 25 USDC per IV token
        let expiration_timestamp = timestamp::now_seconds() + 86400; // 1 day from now
        
        // Initialize the market
        let vault_address = volatility_marketplace::get_staking_vault_address(marketplace_addr);
        let (market_id, market_addr) = volatility_marketplace::create_market(
            &creator,
            asset_symbol,
            initial_volatility,
            expiration_timestamp,
            marketplace_addr
        );
        
        // Verify market metadata
        assert!(implied_volatility_market::get_owner(market_addr) == signer::address_of(&creator), 2);
        assert!(implied_volatility_market::get_asset_symbol(market_addr) == asset_symbol, 3);
        assert!(implied_volatility_market::get_quote(market_addr) == (initial_volatility as u64), 4);
        assert!(implied_volatility_market::get_expiration(market_addr) == expiration_timestamp, 5);
        assert!(!implied_volatility_market::is_settled(market_addr), 6);
        
        // Verify AMM reserves
        let (iv_reserves, usdc_reserves) = implied_volatility_market::get_amm_reserves(market_addr);
        let expected_iv_supply = 10000 * 1000000; // 10K tokens with 6 decimals
        let expected_usdc_reserves = (expected_iv_supply * initial_volatility) / 1000000; // 25M USDC equivalent
        
        assert!(iv_reserves == expected_iv_supply, 7);
        assert!(usdc_reserves == expected_usdc_reserves, 8);
        
        // Verify tokens were minted to market object
        let iv_token_metadata = implied_volatility_market::get_iv_token_metadata(market_addr);
        let market_iv_balance = primary_fungible_store::balance(market_addr, iv_token_metadata);
        assert!((market_iv_balance as u256) == expected_iv_supply, 9);
    }

    #[test(creator = @0x123, trader = @0x456, framework = @aptos_framework)]
    fun test_marketplace_swap(creator: signer, trader: signer, framework: signer) {
        // Setup test environment
        timestamp::set_time_has_started_for_testing(&framework);

        // Create marketplace
        let marketplace_addr = volatility_marketplace::create_marketplace(&creator);
        
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
        let marketplace_addr = volatility_marketplace::create_marketplace(&creator);
        
        // Create a volatility market
        let asset_symbol = string::utf8(b"ETH");
        let initial_volatility = 30 * 1000000; 
        let expiration_timestamp = timestamp::now_seconds() + 86400;
        
        let (market_id, market_address) = volatility_marketplace::create_market(
            &creator,
            asset_symbol,
            initial_volatility,
            expiration_timestamp,
            marketplace_addr
        );

        // Test get_quote
        let quote = implied_volatility_market::get_quote(market_address);
        let expected_quote = (initial_volatility as u64);

        assert!(quote == expected_quote, 1);
    }

    #[test(creator = @0x123, trader = @0x456, staker = @0x789, framework = @aptos_framework)]
    fun test_open_short_position(creator: signer, trader: signer, staker: signer, framework: signer) {
        // Setup test environment
        timestamp::set_time_has_started_for_testing(&framework);

        // Create marketplace
        let marketplace_addr = volatility_marketplace::create_marketplace(&creator);

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

    #[test(creator = @0x123, trader = @0x456, staker = @0x789, framework = @aptos_framework)]
    fun test_settlement_basic(creator: signer, trader: signer, staker: signer, framework: signer) {
        // Setup test environment
        timestamp::set_time_has_started_for_testing(&framework);

        // Create marketplace
        let marketplace_addr = volatility_marketplace::create_marketplace(&creator);

        // Stake tokens to facilitate borrows
        let staking_amount = 100000 * 1000000; // 100K USDC
        let staker_address = signer::address_of(&staker);
        volatility_marketplace::mint_test_usdc(staking_amount, staker_address, marketplace_addr);
        let vault_address = volatility_marketplace::get_staking_vault_address(marketplace_addr);
        staking_vault::stake(&staker, vault_address, staking_amount);

        // Create a volatility market
        let asset_symbol = string::utf8(b"BTC");
        let initial_volatility = 25 * 1000000; // 25 USDC per IV token
        let expiration_timestamp = timestamp::now_seconds() + 86400;
        
        let (market_id, market_address) = volatility_marketplace::create_market(
            &creator,
            asset_symbol,
            initial_volatility,
            expiration_timestamp,
            marketplace_addr
        );

        // Verify market is not settled initially
        assert!(!implied_volatility_market::is_settled(market_address), 1);

        // Fast-forward past expiration
        timestamp::fast_forward_seconds(86401);

        // Settle the market at a specific price
        let settlement_price = 20 * 1000000; // 20 USDC per IV token
        volatility_marketplace::settle_market(&creator, marketplace_addr, market_id, settlement_price);

        // Verify market is now settled
        assert!(implied_volatility_market::is_settled(market_address), 2);
    }

    #[test(creator = @0x123, trader = @0x456, staker = @0x789, framework = @aptos_framework)]
    #[expected_failure(abort_code = 0x50001, location = marketplace::implied_volatility_market)]
    fun test_settlement_unauthorized(creator: signer, trader: signer, staker: signer, framework: signer) {
        // Setup test environment
        timestamp::set_time_has_started_for_testing(&framework);

        // Create marketplace
        let marketplace_addr = volatility_marketplace::create_marketplace(&creator);

        // Create a volatility market
        let asset_symbol = string::utf8(b"BTC");
        let initial_volatility = 25 * 1000000; 
        let expiration_timestamp = timestamp::now_seconds() + 86400;
        
        let (market_id, market_address) = volatility_marketplace::create_market(
            &creator,
            asset_symbol,
            initial_volatility,
            expiration_timestamp,
            marketplace_addr
        );

        // Fast-forward past expiration
        timestamp::fast_forward_seconds(86401);

        // Try to settle with unauthorized signer (trader instead of creator)
        let settlement_price = 20 * 1000000;
        volatility_marketplace::settle_market(&trader, marketplace_addr, market_id, settlement_price);
    }

    #[test(creator = @0x123, framework = @aptos_framework)]
    #[expected_failure(abort_code = 0x10003, location = marketplace::implied_volatility_market)]
    fun test_settlement_not_expired(creator: signer, framework: signer) {
        // Setup test environment
        timestamp::set_time_has_started_for_testing(&framework);

        // Create marketplace
        let marketplace_addr = volatility_marketplace::create_marketplace(&creator);

        // Create a volatility market that hasn't expired yet
        let asset_symbol = string::utf8(b"BTC");
        let initial_volatility = 25;
        let expiration_timestamp = timestamp::now_seconds() + 86400;
        
        let (market_id, market_address) = volatility_marketplace::create_market(
            &creator,
            asset_symbol,
            initial_volatility,
            expiration_timestamp,
            marketplace_addr
        );

        // Try to settle before expiration (should fail)
        let settlement_price = 20 * 1000000;
        volatility_marketplace::settle_market(&creator, marketplace_addr, market_id, settlement_price);
    }

    #[test(creator = @0x123, framework = @aptos_framework)]
    #[expected_failure(abort_code = 0x10002, location = marketplace::implied_volatility_market)]
    fun test_settlement_already_settled(creator: signer, framework: signer) {
        // Setup test environment
        timestamp::set_time_has_started_for_testing(&framework);

        // Create marketplace
        let marketplace_addr = volatility_marketplace::create_marketplace(&creator);

        // Create a volatility market
        let asset_symbol = string::utf8(b"BTC");
        let initial_volatility = 25;
        let expiration_timestamp = timestamp::now_seconds() + 86400;
        
        let (market_id, market_address) = volatility_marketplace::create_market(
            &creator,
            asset_symbol,
            initial_volatility,
            expiration_timestamp,
            marketplace_addr
        );

        // Fast-forward past expiration
        timestamp::fast_forward_seconds(86401);

        // Settle the market once
        let settlement_price = 20 * 1000000;
        volatility_marketplace::settle_market(&creator, marketplace_addr, market_id, settlement_price);

        // Try to settle again (should fail)
        volatility_marketplace::settle_market(&creator, marketplace_addr, market_id, settlement_price);
    }

    #[test(creator = @0x123, trader = @0x456, staker = @0x789, framework = @aptos_framework)]
    fun test_settlement_with_long_positions(creator: signer, trader: signer, staker: signer, framework: signer) {
        // Setup test environment
        timestamp::set_time_has_started_for_testing(&framework);

        // Create marketplace
        let marketplace_addr = volatility_marketplace::create_marketplace(&creator);

        // Stake tokens
        let staking_amount = 100000 * 1000000;
        let staker_address = signer::address_of(&staker);
        volatility_marketplace::mint_test_usdc(staking_amount, staker_address, marketplace_addr);
        let vault_address = volatility_marketplace::get_staking_vault_address(marketplace_addr);
        staking_vault::stake(&staker, vault_address, staking_amount);

        // Create market
        let asset_symbol = string::utf8(b"BTC");
        let initial_volatility = 25*1000000;
        let expiration_timestamp = timestamp::now_seconds() + 86400;
        
        let (market_id, market_address) = volatility_marketplace::create_market(
            &creator,
            asset_symbol,
            initial_volatility,
            expiration_timestamp,
            marketplace_addr
        );

        // Mint USDC to trader and buy IV tokens (open long position)
        let trader_addr = signer::address_of(&trader);
        let usdc_amount = 10000000; // 10 USDC
        volatility_marketplace::mint_test_usdc(usdc_amount, trader_addr, marketplace_addr);

        let usdc_input = 5000000; // 5 USDC
        implied_volatility_market::swap(
            &trader,
            market_address,
            0, // swap_type: USDC -> IV
            usdc_input
        );

        // Get trader's IV balance before settlement
        let iv_metadata = implied_volatility_market::get_iv_token_metadata(market_address);
        let iv_balance_before_settlement = primary_fungible_store::balance(trader_addr, iv_metadata);
        assert!(iv_balance_before_settlement > 0, 1);

        // Fast-forward past expiration and settle
        timestamp::fast_forward_seconds(86401);
        let settlement_price = 30 * 1000000; // 30 USDC per IV token (profit for long)
        volatility_marketplace::settle_market(&creator, marketplace_addr, market_id, settlement_price);

        // Verify IV tokens were sold back and trader received USDC
        let iv_balance_after_settlement = primary_fungible_store::balance(trader_addr, iv_metadata);
        assert!(iv_balance_after_settlement == 0, 2); // All IV tokens should be sold

        let usdc_metadata = volatility_marketplace::get_test_usdc_metadata(marketplace_addr);
        let final_usdc_balance = primary_fungible_store::balance(trader_addr, usdc_metadata);
        assert!(final_usdc_balance > usdc_amount - usdc_input, 3); // Should have gained USDC
    }

    #[test(creator = @0x123, trader = @0x456, staker = @0x789, framework = @aptos_framework)]
    fun test_settlement_with_short_positions(creator: signer, trader: signer, staker: signer, framework: signer) {
        // Setup test environment
        timestamp::set_time_has_started_for_testing(&framework);

        // Create marketplace
        let marketplace_addr = volatility_marketplace::create_marketplace(&creator);

        // Stake tokens
        let staking_amount = 100000 * 1000000;
        let staker_address = signer::address_of(&staker);
        volatility_marketplace::mint_test_usdc(staking_amount, staker_address, marketplace_addr);
        let vault_address = volatility_marketplace::get_staking_vault_address(marketplace_addr);
        staking_vault::stake(&staker, vault_address, staking_amount);

        // Create market
        let asset_symbol = string::utf8(b"BTC");
        let initial_volatility = 25 * 1000000;
        let expiration_timestamp = timestamp::now_seconds() + 86400;
        
        let (market_id, market_address) = volatility_marketplace::create_market(
            &creator,
            asset_symbol,
            initial_volatility,
            expiration_timestamp,
            marketplace_addr
        );

        // Add USDC to market for liquidity
        let usdc_amount = 1000 * 1000000; // 1000 USDC
        volatility_marketplace::mint_test_usdc(usdc_amount, market_address, marketplace_addr);

        // Open short position
        let trader_addr = signer::address_of(&trader);
        let collateral_amount = 5 * 1000000; // 5 USDC
        volatility_marketplace::mint_test_usdc(collateral_amount, trader_addr, marketplace_addr);

        implied_volatility_market::open_short_position(
            &trader,
            market_address,
            collateral_amount
        );

        // Verify short position exists
        let account_state = implied_volatility_market::get_margin_account_state(market_address, trader_addr);
        let iv_units_borrowed = isolated_margin_account::get_iv_units_borrowed(&account_state);
        assert!(iv_units_borrowed > 0, 1);

        // Get trader's USDC balance before settlement
        let usdc_metadata = volatility_marketplace::get_test_usdc_metadata(marketplace_addr);
        let usdc_balance_before = primary_fungible_store::balance(trader_addr, usdc_metadata);

        // Fast-forward past expiration and settle at lower price (profit for short)
        timestamp::fast_forward_seconds(86401);
        let settlement_price = 20 * 1000000; // 20 USDC per IV token
        volatility_marketplace::settle_market(&creator, marketplace_addr, market_id, settlement_price);

        // Verify short position was closed and trader received remaining collateral
        let usdc_balance_after = primary_fungible_store::balance(trader_addr, usdc_metadata);
        assert!(usdc_balance_after >= usdc_balance_before, 2); // Should have received some USDC back
    }

    #[test(creator = @0x123, trader1 = @0x456, trader2 = @0x789, staker = @0x987, framework = @aptos_framework)]
    fun test_settlement_with_mixed_positions(creator: signer, trader1: signer, trader2: signer, staker: signer, framework: signer) {
        // Setup test environment
        timestamp::set_time_has_started_for_testing(&framework);

        // Create marketplace
        let marketplace_addr = volatility_marketplace::create_marketplace(&creator);

        // Stake tokens
        let staking_amount = 10000000000 * 1000000;
        let staker_address = signer::address_of(&staker);
        volatility_marketplace::mint_test_usdc(staking_amount, staker_address, marketplace_addr);
        let vault_address = volatility_marketplace::get_staking_vault_address(marketplace_addr);
        staking_vault::stake(&staker, vault_address, staking_amount);

        // Create market
        let asset_symbol = string::utf8(b"ETH");
        let initial_volatility = 30 * 1000000;
        let expiration_timestamp = timestamp::now_seconds() + 86400;
        
        let (market_id, market_address) = volatility_marketplace::create_market(
            &creator,
            asset_symbol,
            initial_volatility,
            expiration_timestamp,
            marketplace_addr
        );

        // Trader1 opens long position
        let trader1_addr = signer::address_of(&trader1);
        let long_usdc = 5000000; // 5 USDC
        volatility_marketplace::mint_test_usdc(long_usdc, trader1_addr, marketplace_addr);
        
        implied_volatility_market::swap(
            &trader1,
            market_address,
            0, // USDC -> IV
            long_usdc
        );

        // Trader2 opens short position
        let trader2_addr = signer::address_of(&trader2);
        let short_collateral = 30000000; // 30 USDC
        volatility_marketplace::mint_test_usdc(short_collateral, trader2_addr, marketplace_addr);

        implied_volatility_market::open_short_position(
            &trader2,
            market_address,
            short_collateral
        );

        // Get initial balances
        let usdc_metadata = volatility_marketplace::get_test_usdc_metadata(marketplace_addr);
        let trader1_usdc_before = primary_fungible_store::balance(trader1_addr, usdc_metadata);
        let trader2_usdc_before = primary_fungible_store::balance(trader2_addr, usdc_metadata);

        // Fast-forward and settle at price favorable to long positions
        timestamp::fast_forward_seconds(86401);
        let settlement_price = 35 * 1000000; // 35 USDC per IV token
        volatility_marketplace::settle_market(&creator, marketplace_addr, market_id, settlement_price);

        // Verify both positions were closed
        let trader1_usdc_after = primary_fungible_store::balance(trader1_addr, usdc_metadata);
        let trader2_usdc_after = primary_fungible_store::balance(trader2_addr, usdc_metadata);

        // Long position should profit
        assert!(trader1_usdc_after > trader1_usdc_before, 1);

        // Short position should be in loss
        assert!(trader2_usdc_after < short_collateral, 2);
        
        // Vault should be in profit
        // This should be earnings from swap, lending fees + taking the other side of a margin
        // position that was a loss for the trader
        let vault_usdc_after = primary_fungible_store::balance(vault_address, usdc_metadata);

        assert!(vault_usdc_after > staking_amount, 3);

        // Market should be settled
        assert!(implied_volatility_market::is_settled(market_address), 3);
    }

}
