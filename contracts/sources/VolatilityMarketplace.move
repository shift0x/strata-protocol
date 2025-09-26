address marketplace {
// Centralized marketplace for managing multiple implied volatility markets
module volatility_marketplace {
    use std::error;
    use std::signer;
    use std::string;
    use std::option;
    use std::vector;
    use std::table::{Self, Table};
    use aptos_framework::timestamp;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::fungible_asset::{Self, Metadata, MintRef, TransferRef};
    use aptos_framework::primary_fungible_store::{Self};
    use marketplace::implied_volatility_market::{Self};

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
        // Table for quick lookup by asset symbol and expiration  
        market_lookup: Table<string::String, u64>,
        // TestUSDC token management capabilities
        test_usdc_refs: TestUSDCRefs,
        // TestUSDC token metadata
        test_usdc_metadata: Object<Metadata>
    }

    public fun swap(
        user: &signer,
        marketplace_address: address,
        market_id: u64,
        swap_type: u8,
        amount_in: u64
    ): u64 acquires Marketplace {
        let marketplace = borrow_global<Marketplace>(marketplace_address);
        assert!(table::contains(&marketplace.market_addresses, market_id), error::not_found(E_MARKET_NOT_FOUND));
        
        let market_address = *table::borrow(&marketplace.market_addresses, market_id);

        implied_volatility_market::swap(user, market_address, swap_type, amount_in)
    }

    public fun get_swap_amount_out(
        marketplace_address: address,
        market_id: u64,
        swap_type: u8,
        amount_in: u64
    ) : u64 acquires Marketplace {
        let marketplace = borrow_global<Marketplace>(marketplace_address);
        assert!(table::contains(&marketplace.market_addresses, market_id), error::not_found(E_MARKET_NOT_FOUND));
        
        let market_address = *table::borrow(&marketplace.market_addresses, market_id);

        let amount_out = implied_volatility_market::get_swap_amount_out(market_address, swap_type, (amount_in as u256));

        return (amount_out as u64)
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
        
        // Create the new marketplace
        let marketplace = Marketplace {
            owner: creator_addr,
            market_counter: 0,
            market_addresses: table::new(),
            market_lookup: table::new(),
            test_usdc_refs,
            test_usdc_metadata
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
    ): u64 acquires Marketplace {
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
            expiration_timestamp
        );
        
        // Store market address in tables
        table::add(&mut marketplace.market_addresses, market_id, market_address);
        table::add(&mut marketplace.market_lookup, lookup_key, market_id);
        
        market_id
    }

    // Settle a market (owner only) - delegates to individual market
    public fun settle_market(
        owner: &signer,
        market_id: u64,
        final_volatility: u256,
        marketplace_address: address
    ) acquires Marketplace {
        let owner_addr = signer::address_of(owner);
        let marketplace = borrow_global<Marketplace>(marketplace_address);
        
        assert!(marketplace.owner == owner_addr, error::permission_denied(E_NOT_AUTHORIZED));
        assert!(table::contains(&marketplace.market_addresses, market_id), error::not_found(E_MARKET_NOT_FOUND));
        
        // Get market address and delegate to individual market module
        let market_addr = *table::borrow(&marketplace.market_addresses, market_id);
        implied_volatility_market::settle_market(owner, market_addr, final_volatility);
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
        sender: &signer,
        amount: u64,
        marketplace_address: address
    ) acquires Marketplace {
        let marketplace = borrow_global<Marketplace>(marketplace_address);
        let sender_addr = signer::address_of(sender);
        
        // Ensure primary store exists for the sender
        // primary_fungible_store::ensure_primary_store_exists(sender_addr, marketplace.test_usdc_metadata);
        
        // Mint tokens using the mint ref
        let tokens = fungible_asset::mint(&marketplace.test_usdc_refs.mint_ref, amount);
        
        // Deposit tokens to the sender
        primary_fungible_store::deposit(sender_addr, tokens);
    }

    // Get TestUSDC metadata for external use
    #[view]
    public fun get_test_usdc_metadata(marketplace_address: address): Object<Metadata> acquires Marketplace {
        let marketplace = borrow_global<Marketplace>(marketplace_address);
        marketplace.test_usdc_metadata
    }

    #[view]
    public fun get_iv_token_metadata(
        marketplace_address: address,
        market_id: u64
    ) : Object<Metadata> acquires Marketplace {
        let marketplace = borrow_global<Marketplace>(marketplace_address);
        assert!(table::contains(&marketplace.market_addresses, market_id), error::not_found(E_MARKET_NOT_FOUND));
        
        let market_address = *table::borrow(&marketplace.market_addresses, market_id);

        return implied_volatility_market::get_iv_token_metadata(market_address)
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
}
}
