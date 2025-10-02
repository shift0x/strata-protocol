address marketplace {
/// Staking vault where contributors stake USDC and earn rewards from trading fees and 
/// lending fees from margin loans to short sellers in IV markets.
/// This module is intended to be created by the VolatilityMarketplace module and called by 
/// users to initiate margin positions in IV Markets
module staking_vault {
    use std::error;
    use std::signer;
    use std::string;
    use std::table::{Self, Table};
    use aptos_framework::timestamp;
    use aptos_framework::object::{Self, Object, ExtendRef};
    use aptos_framework::fungible_asset::{Self, Metadata, MintRef, BurnRef, TransferRef};
    use aptos_framework::primary_fungible_store::{Self};
    use marketplace::volatility_marketplace::{Self};
    use marketplace::implied_volatility_market::{Self};
    use marketplace::options_exchange::{Self};

    // Error codes
    const E_INSUFFICIENT_BALANCE: u64 = 1;
    const E_BORROW_OVER_CAP: u64 = 2;

    friend marketplace::volatility_marketplace;
    friend marketplace::implied_volatility_market;
    friend marketplace::options_exchange;

    struct AccountRefs has key {
        extend_ref: object::ExtendRef
    }

    struct Vault has key {
        // address of the USDC token deposited into the vault
        usdc_address: address,
        // the amount of USDC loans made to user margin accounts
        usdc_loan_amount: u64,
        // the amount of USDC that has been staked (will differ from token balance because of loans)
        usdc_staked_amount: u64,
        // the amount of USDC owned by the vault, includes staked amount and earnings / loss from fees and trading
        usdc_claimable_amount: u64,
        // staking balances by user
        staking_balances: table::Table<address, u64>,
        // the amount of swap fees earned by the staking pool
        swap_fees_earned: u64,
        // the amount of lending fees earned by the staking pool
        lending_fees_earned: u64,
        // the maximum percentage of staked balances can be borrowed from the vault
        max_borrow_percentage: u64,
        // the fee changed for borrowing funds from the vault
        borrow_fee: u64,
    }

    // creates a new vault object that holds tokens and vault structs
    // this method should only be called from the Volatility Market during initialization
    public(friend) fun create_vault(
        creator: &signer,
        usdc_address: address,
        max_borrow_percentage: u64
    ): address {
        let creator_addr = signer::address_of(creator);

        // Create object to hold the market and its token balances
        let constructor_ref = object::create_object(creator_addr);
        let object_signer = object::generate_signer(&constructor_ref);
        let extend_ref = object::generate_extend_ref(&constructor_ref);
        let object_addr = signer::address_of(&object_signer);

        let vault = Vault {
            usdc_address,
            usdc_loan_amount: 0,
            usdc_staked_amount: 0,
            usdc_claimable_amount: 0,
            staking_balances: table::new(),
            swap_fees_earned: 0,
            lending_fees_earned: 0,
            max_borrow_percentage,
            borrow_fee: 40000 // 4%
        };

        // Store the vault in the object
        move_to(&object_signer, vault);
        move_to(&object_signer, AccountRefs { extend_ref });

        object_addr
    }

    public(friend) fun withdraw_from_vault(
        vault_address: address,
        destination_address: address,
        amount: u64
    ) acquires Vault, AccountRefs {
        // get the vault and signer
        let vault = borrow_global_mut<Vault>(vault_address);
        let vault_signer = get_signer(vault_address);

        // send the requested borrow amount
        let usdc_metadata = object::address_to_object<Metadata>(vault.usdc_address);
        let usdc_tokens = primary_fungible_store::withdraw(&vault_signer, usdc_metadata, amount);
        primary_fungible_store::deposit(destination_address, usdc_tokens); 

        // reduce the staking balance USDC (vault recording a loss)
        vault.usdc_claimable_amount = vault.usdc_claimable_amount - amount;
    }

    public(friend) fun borrow_on_margin(
        borrow_margin_account: &signer,
        liquidity_pool_address: address,
        vault_address: address,
        amount: u64
    ) acquires Vault, AccountRefs {
        // ensure the requested borrow amount is less than the max borrow
        let max_borrow_amount = get_maximum_borrow_amount(vault_address);
        assert!(amount <= max_borrow_amount, error::aborted(E_BORROW_OVER_CAP));

        // get the vault and signer
        let vault = borrow_global_mut<Vault>(vault_address);
        let vault_signer = get_signer(vault_address);

        // send the requested borrow amount
        let usdc_metadata = object::address_to_object<Metadata>(vault.usdc_address);
        let usdc_tokens = primary_fungible_store::withdraw(&vault_signer, usdc_metadata, amount);
        primary_fungible_store::deposit(liquidity_pool_address, usdc_tokens);    

        // extract borrow fees
        let borrow_fee = (vault.borrow_fee * amount) / 1000000;
        let borrow_usdc_tokens = primary_fungible_store::withdraw(borrow_margin_account, usdc_metadata, borrow_fee);
        primary_fungible_store::deposit(vault_address, borrow_usdc_tokens);

        // update the staked balance to reflect the collected transaction fees
        vault.usdc_claimable_amount = vault.usdc_claimable_amount + borrow_fee;

        // update the transaction fees collected from the borrow
        vault.lending_fees_earned = vault.lending_fees_earned + borrow_fee;
    }

    public(friend) fun swap_fees_collected(
        vault_address: address,
        amount: u64
    ) acquires Vault {
        let vault = borrow_global_mut<Vault>(vault_address);

        vault.swap_fees_earned = vault.swap_fees_earned + amount;
        vault.usdc_claimable_amount = vault.usdc_claimable_amount + amount;
    }

    public(friend) fun volatility_market_profit(
        vault_address: address,
        amount: u64
    ) acquires Vault {
        let vault = borrow_global_mut<Vault>(vault_address);

        vault.usdc_claimable_amount = vault.usdc_claimable_amount + amount;
    }

    // stake the amount of user tokens with the vault
    public fun stake(
        owner: &signer,
        vault_address: address,
        amount: u64  
    ) acquires Vault {
        let vault = borrow_global_mut<Vault>(vault_address);
        
        // transfer user usdc tokens into the vault
        let usdc_metadata = object::address_to_object<Metadata>(vault.usdc_address);
        let usdc_tokens = primary_fungible_store::withdraw(owner, usdc_metadata, amount);
        primary_fungible_store::deposit(vault_address, usdc_tokens);

        // update the vault staked amount
        vault.usdc_staked_amount = vault.usdc_staked_amount + amount;
        vault.usdc_claimable_amount = vault.usdc_claimable_amount + amount;

        // increment the users staking balance
        let owner_addr = signer::address_of(owner);
        if (table::contains(&vault.staking_balances, owner_addr)) {
            let current_balance = table::borrow_mut(&mut vault.staking_balances, owner_addr);
            *current_balance = *current_balance + amount;
        } else {
            table::add(&mut vault.staking_balances, owner_addr, amount);
        };
    }

    // unstake a given amount from the user balance. Reverts if the user does not have
    // enought staked tokens to stake
    public fun unstake(
        owner: &signer,
        vault_address: address,
        amount: u64
    ) acquires Vault, AccountRefs {
        let vault = borrow_global_mut<Vault>(vault_address);
        let owner_addr = signer::address_of(owner);
        
        // ensure the user has a balance
        assert!(table::contains(&vault.staking_balances, owner_addr), error::not_found(E_INSUFFICIENT_BALANCE));
        
        // calculate amount to transfer
        let amount_to_transfer = get_unstake_amount_internal(vault, owner_addr, amount);

        // get current balance to check if sufficient
        let current_balance_value = *table::borrow(&vault.staking_balances, owner_addr);
        assert!(current_balance_value >= amount, error::not_found(E_INSUFFICIENT_BALANCE));

        // transfer tokens back to the user in proportion to their stake
        let usdc_metadata = object::address_to_object<Metadata>(vault.usdc_address);
        let vault_signer = get_signer(vault_address);

        let usdc_tokens = primary_fungible_store::withdraw(&vault_signer, usdc_metadata, amount_to_transfer);
        primary_fungible_store::deposit(owner_addr, usdc_tokens);    

        // update the users current balance
        let current_balance = table::borrow_mut(&mut vault.staking_balances, owner_addr);
        *current_balance = *current_balance - amount;

        // updated the vault staked amount
        vault.usdc_staked_amount = vault.usdc_staked_amount - amount;
        vault.usdc_claimable_amount = vault.usdc_claimable_amount - amount_to_transfer;
    }


    // given a user and vault, returns the current staking balance for the user
    #[view]
    public fun get_staking_balance(
        vault_address: address,
        user_address: address
    ) : u64 acquires Vault {
        let vault = borrow_global<Vault>(vault_address);

         // Ensure market doesn't already exist for this asset/expiration
        if(!table::contains(&vault.staking_balances, user_address)) {
            0
        } else {
            *table::borrow(&vault.staking_balances, user_address)
        }
    }

    #[view]
    public fun get_unstake_amount(
        vault_address: address,
        user_address: address,
        amount: u64
    ) : u64 acquires Vault {
        let vault = borrow_global<Vault>(vault_address);
        
        get_unstake_amount_internal(vault, user_address, amount)
    }

    fun get_unstake_amount_internal(
        vault: &Vault,
        user_address: address,
        amount: u64
    ) : u64  {
        if(!table::contains(&vault.staking_balances, user_address)) {
            0
        } else {
            let factor = 1000000; //10^6
            let staked_percentage = (amount * factor) / vault.usdc_staked_amount;
            
            (vault.usdc_claimable_amount * staked_percentage) / factor
        }
        
    }

    // the vault has a limit on the amount of USDC that can be borrowed at any given time
    // this returns the maximum amount of USDC that can be borrowed given the existing borrows
    #[view]
    public fun get_maximum_borrow_amount(
        vault_address: address
    ): u64 acquires Vault {
        let vault = borrow_global<Vault>(vault_address);
        let factor = 1000000 as u256; //10^6

        let usdc_staked_amount_big = vault.usdc_claimable_amount as u256;
        let max_borrow_percentage_big = vault.max_borrow_percentage as u256;
        let max_borrow = (usdc_staked_amount_big * max_borrow_percentage_big) / factor;

        max_borrow as u64
    }
    
    fun get_signer(
        vault_address: address
    ) : signer acquires AccountRefs {
        let refs = borrow_global<AccountRefs>(vault_address);
        
        object::generate_signer_for_extending(&refs.extend_ref)
    }


}
}