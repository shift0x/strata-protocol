#[test_only]
module marketplace::staking_vault_tests {
    use std::signer;
    use std::debug;
    use aptos_framework::account;
    use aptos_framework::primary_fungible_store;
    use marketplace::staking_vault;
    use marketplace::volatility_marketplace;

    #[test(creator = @0x123, user = @0x456)]
    public fun test_stake_and_unstake(creator: &signer, user: &signer) {
        let user_addr = signer::address_of(user);
        
        // Create marketplace
        let marketplace_address = volatility_marketplace::create_marketplace(creator);
        
        // Get the staking vault address from the marketplace
        let vault_address = volatility_marketplace::get_staking_vault_address(marketplace_address);
        
        // Mint test USDC for the user
        let factor = 1000000; //10^6
        let stake_amount = 1000 * factor;
        volatility_marketplace::mint_test_usdc(stake_amount, user_addr, marketplace_address);
        
        // Get USDC metadata to check balances
        let usdc_metadata = volatility_marketplace::get_test_usdc_metadata(marketplace_address);

        // Test initial staking balance should be 0
        let initial_balance = staking_vault::get_staking_balance(vault_address, user_addr);
        assert!(initial_balance == 0, 1);

        // Stake 500 USDC tokens
        let stake_amount_partial = stake_amount / 3;
        staking_vault::stake(user, vault_address, stake_amount_partial);
        
        // Verify staking balance equals the intended stake amount
        let staked_balance = staking_vault::get_staking_balance(vault_address, user_addr);
        let staking_vault_balance = primary_fungible_store::balance(vault_address, usdc_metadata);
        assert!(staked_balance == stake_amount_partial, 3);
        assert!(staked_balance == staking_vault_balance, 4);
        
        // Verify user's USDC equals the orginal balance - staked amount
        let remaining_usdc_balance = primary_fungible_store::balance(user_addr, usdc_metadata);
        assert!(remaining_usdc_balance == stake_amount - stake_amount_partial, 5);

        // Test unstaking partial amount
        let unstake_amount = stake_amount_partial/2;
        staking_vault::unstake(user, vault_address, unstake_amount);
        
        // Verify staking balance decreased
        let updated_staked_balance = staking_vault::get_staking_balance(vault_address, user_addr);
        assert!(updated_staked_balance == stake_amount_partial - unstake_amount, 6);
        
        // Verify user got USDC tokens back
        let final_usdc_balance = primary_fungible_store::balance(user_addr, usdc_metadata);
        let expected_usdc_balance = stake_amount - stake_amount_partial + unstake_amount;
        let balance_diff = expected_usdc_balance - final_usdc_balance;

        assert!(balance_diff < 1000, 7);
    }
}
