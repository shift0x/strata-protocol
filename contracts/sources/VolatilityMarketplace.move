address marketplace {
// Centralized marketplace for managing multiple implied volatility markets
module volatility_marketplace {
    use std::error;
    use std::signer;
    use std::string;
    use std::option;
    use std::vector::{Self};
    use std::table::{Self, Table};
    use aptos_framework::timestamp;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::fungible_asset::{Self, Metadata, MintRef, TransferRef};
    use aptos_framework::primary_fungible_store::{Self};
    use marketplace::implied_volatility_market::{Self};
    use marketplace::staking_vault::{Self};

    // Error codes
    const E_NOT_AUTHORIZED: u64 = 1;
    const E_MARKET_NOT_FOUND: u64 = 2;
    const E_MARKET_ALREADY_EXISTS: u64 = 3;
    const E_INVALID_EXPIRATION: u64 = 4;

    // Capabilities for managing the TestUSDC token
    struct TestUSDCRefs has store {
        mint_ref: MintRef,
        transfer_ref: TransferRef,
    }

    // Centralized marketplace resource
    struct Marketplace has key {
        // Owner of the marketplace
        owner: address,
        // Counter for generating unique market IDs
        market_counter: u64,
        // Table storing market addresses by ID
        market_addresses: Table<u64, address>,
        // Table for quick lookup by market key(symbol+expiration)
        market_lookup: Table<string::String, u64>,
        // Table for all active markets for a given asset
        active_markets_by_asset: Table<string::String, vector<address>>,
        // TestUSDC token management capabilities
        test_usdc_refs: TestUSDCRefs,
        // TestUSDC token metadata
        test_usdc_metadata: Object<Metadata>,
        // Staking vault address
        staking_vault_address: address
    }

    // Helper function to convert u64 to decimal string
    fun u64_to_string(value: u64): string::String {
        if (value == 0) {
            return string::utf8(b"0")
        };
        
        let result = vector::empty<u8>();
        let temp = value;
        
        while (temp > 0) {
            let digit = (temp % 10) as u8;
            vector::push_back(&mut result, digit + 48); // 48 is ASCII '0'
            temp = temp / 10;
        };
        
        // Reverse the result since we built it backwards
        vector::reverse(&mut result);
        string::utf8(result)
    }

    // Initialize the marketplace - setting the owner to the deployer
    public fun create_marketplace(owner: &signer) {
        let creator_addr = signer::address_of(owner);
        
        // Create TestUSDC token
        let (test_usdc_refs, test_usdc_metadata) = create_test_usdc_token(owner);
        let usdc_address = object::object_address(&test_usdc_metadata);
        
        // Create a new staking vault
        let max_borrow_percentage = 100000; // 10%
        let vault_address = staking_vault::create_vault(owner, usdc_address, max_borrow_percentage);

        // Create the new marketplace
        let marketplace = Marketplace {
            owner: creator_addr,
            market_counter: 0,
            market_addresses: table::new(),
            market_lookup: table::new(),
            active_markets_by_asset: table::new(),
            test_usdc_refs,
            test_usdc_metadata,
            staking_vault_address: vault_address
        };

        // Store resources
        move_to(owner, marketplace);
    }

    fun create_test_usdc_token(
        owner_signer: &signer
    ) : (TestUSDCRefs, Object<Metadata>) {
        let fa_constructor_ref = &object::create_named_object(owner_signer, b"test_usdc");
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
          fa_constructor_ref,
          option::none(),
          string::utf8(b"Test USDC"),
          string::utf8(b"TUSDC"),
          6,
          string::utf8(b""),
          string::utf8(b""),
        );
        
        let test_usdc_metadata = object::object_from_constructor_ref<Metadata>(fa_constructor_ref);
        
        // Store token management capabilities
        let mint_ref = fungible_asset::generate_mint_ref(fa_constructor_ref);
        let transfer_ref = fungible_asset::generate_transfer_ref(fa_constructor_ref);
        
        let token_refs = TestUSDCRefs {
            mint_ref,
            transfer_ref,
        };

        (token_refs, test_usdc_metadata)
    }

    // Create a new volatility market
    public fun create_market(
        creator: &signer,
        asset_symbol: string::String,
        initial_volatility: u256,
        expiration_timestamp: u64,
        marketplace_address: address
    ): (u64, address) acquires Marketplace {
        // Only marketplace owner can create markets
        let creator_addr = signer::address_of(creator);
        let marketplace = borrow_global_mut<Marketplace>(marketplace_address);
        
        assert!(marketplace.owner == creator_addr, error::permission_denied(E_NOT_AUTHORIZED));
        assert!(expiration_timestamp > timestamp::now_seconds(), error::invalid_argument(E_INVALID_EXPIRATION));
        
        // Create lookup key (asset_symbol + expiration)
        let lookup_key = asset_symbol;
        string::append(&mut lookup_key, string::utf8(b"_"));
        string::append(&mut lookup_key, u64_to_string(expiration_timestamp));
        
        // Ensure market doesn't already exist for this asset/expiration
        assert!(!table::contains(&marketplace.market_lookup, lookup_key), 
                error::already_exists(E_MARKET_ALREADY_EXISTS));
        
        // Generate unique market ID
        let market_id = marketplace.market_counter;
        marketplace.market_counter = marketplace.market_counter + 1;
        
        // Create the new market using the individual market module
        let usdc_address = object::object_address(&marketplace.test_usdc_metadata);
        let market_address = implied_volatility_market::init_volatility_market(
            creator,
            asset_symbol,
            usdc_address,
            initial_volatility,
            expiration_timestamp,
            marketplace.staking_vault_address
        );
        
        // Store market address in tables
        table::add(&mut marketplace.market_addresses, market_id, market_address);
        table::add(&mut marketplace.market_lookup, lookup_key, market_id);
        
        // Add market address to active markets by asset
        if (table::contains(&marketplace.active_markets_by_asset, asset_symbol)) {
            let markets_vector = table::borrow_mut(&mut marketplace.active_markets_by_asset, asset_symbol);
            vector::push_back(markets_vector, market_address);
        } else {
            let new_markets_vector = vector::empty<address>();
            vector::push_back(&mut new_markets_vector, market_address);
            table::add(&mut marketplace.active_markets_by_asset, asset_symbol, new_markets_vector);
        };
        
        (market_id, market_address)
    }

    // Settle the given market at the given historical volatility price
    public fun settle_market(
        owner: &signer,
        marketplace_address: address,
        market_id: u64,
        historical_volatility: u256
    ) acquires Marketplace {
        let marketplace = borrow_global_mut<Marketplace>(marketplace_address);
        let market_address = *table::borrow(&marketplace.market_addresses, market_id);
        
        implied_volatility_market::settle_market(owner, market_address, historical_volatility);

        // remove the market from active markets by asset
        let asset_symbol = implied_volatility_market::get_asset_symbol(market_address);
        let markets_vector = table::borrow_mut(&mut marketplace.active_markets_by_asset, asset_symbol);
        let (exists, item_index) = vector::index_of(markets_vector, &market_address);
        
        if(exists) {
            vector::remove(markets_vector, item_index);
        }
    }


    // Transfer marketplace ownership
    public fun transfer_ownership(
        current_owner: &signer,
        new_owner: address,
        marketplace_address: address
    ) acquires Marketplace {
        let owner_addr = signer::address_of(current_owner);
        let marketplace = borrow_global_mut<Marketplace>(marketplace_address);
        
        assert!(marketplace.owner == owner_addr, error::permission_denied(E_NOT_AUTHORIZED));
        marketplace.owner = new_owner;
    }

    // Mint TestUSDC tokens to the sender
    public fun mint_test_usdc(
        amount: u64,
        to: address,
        marketplace_address: address
    ) acquires Marketplace {
        let marketplace = borrow_global<Marketplace>(marketplace_address);
        
        // Mint tokens using the mint ref
        let tokens = fungible_asset::mint(&marketplace.test_usdc_refs.mint_ref, amount);
        
        // Deposit tokens to the sender
        primary_fungible_store::deposit(to, tokens);
    }

    // Get TestUSDC metadata for external use
    #[view]
    public fun get_test_usdc_metadata(marketplace_address: address): Object<Metadata> acquires Marketplace {
        let marketplace = borrow_global<Marketplace>(marketplace_address);
        marketplace.test_usdc_metadata
    }

    #[view]
    public fun get_market_address(
        marketplace_address: address,
        market_id: u64
    ) : address acquires Marketplace {
        let marketplace = borrow_global<Marketplace>(marketplace_address);
        assert!(table::contains(&marketplace.market_addresses, market_id), error::not_found(E_MARKET_NOT_FOUND));
        
        let market_address = *table::borrow(&marketplace.market_addresses, market_id);
        return market_address
    }

    #[view]
    public fun get_staking_vault_address(
        marketplace_address: address
    ) : address acquires Marketplace {
        let marketplace = borrow_global<Marketplace>(marketplace_address);
        return marketplace.staking_vault_address
    }

    #[view]
    public fun get_implied_volatility(
        marketplace_address: address,
        asset_symbol: string::String
    ) : u256 acquires Marketplace {
        let marketplace = borrow_global<Marketplace>(marketplace_address);
        assert!(table::contains(&marketplace.active_markets_by_asset, asset_symbol), error::not_found(E_MARKET_NOT_FOUND));
        
        let markets_vector = table::borrow(&marketplace.active_markets_by_asset, asset_symbol);
        let num_markets = vector::length(markets_vector);
        
        assert!(num_markets > 0, error::not_found(E_MARKET_NOT_FOUND));
        
        let total_volatility = 0u256;
        let i = 0;
        
        while (i < num_markets) {
            let market_address = *vector::borrow(markets_vector, i);
            let market_volatility = implied_volatility_market::get_volatility(market_address);
            total_volatility = total_volatility + market_volatility;
            i = i + 1;
        };
        
        // Calculate average volatility
        total_volatility / (num_markets as u256)
    }
}
}