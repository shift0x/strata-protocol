address marketplace {
// Centralized marketplace for managing multiple implied volatility markets
module volatility_marketplace {
    use std::error;
    use std::signer;
    use std::string;
    use std::table::{Self, Table};
    use std::bcs;
    use aptos_framework::timestamp;
    use marketplace::implied_volatility_market::{Self, VolatilityMarket};

    // Error codes
    const E_NOT_AUTHORIZED: u64 = 1;
    const E_MARKET_NOT_FOUND: u64 = 2;
    const E_MARKET_ALREADY_EXISTS: u64 = 3;
    const E_INVALID_EXPIRATION: u64 = 4;

    // Centralized marketplace resource
    struct Marketplace has key {
        // Owner of the marketplace
        owner: address,
        // Counter for generating unique market IDs
        market_counter: u64,
        // Table storing market addresses by ID
        market_addresses: Table<u64, address>,
        // Table for quick lookup by asset symbol and expiration
        market_lookup: Table<string::String, u64>
    }


    // Initialize the marketplace - setting the owner to the deployer
    fun init_module(owner: &signer) {
        let creator_addr = signer::address_of(owner);
        
        // Create the new marketplace
        let marketplace = Marketplace {
            owner: creator_addr,
            market_counter: 0,
            market_addresses: table::new(),
            market_lookup: table::new()
        };
        
        // Store resources
        move_to(creator, marketplace);

        return marketplace;
    }

    // Create a new volatility market
    public fun create_market(
        creator: &signer,
        marketplace_addr: address,
        asset_symbol: string::String,
        initial_volatility: u64,
        expiration_timestamp: u64
    ): u64 acquires Marketplace {
        // Only marketplace owner can create markets
        let creator_addr = signer::address_of(creator);
        let marketplace = borrow_global_mut<Marketplace>(marketplace_addr);
        
        assert!(marketplace.owner == creator_addr, error::permission_denied(E_NOT_AUTHORIZED));
        assert!(expiration_timestamp > timestamp::now_seconds(), error::invalid_argument(E_INVALID_EXPIRATION));
        
        // Create lookup key (asset_symbol + expiration)
        let lookup_key = asset_symbol;
        string::append(&mut lookup_key, string::utf8(b"_"));
        string::append(&mut lookup_key, string::utf8(std::bcs::to_bytes(&expiration_timestamp)));
        
        // Ensure market doesn't already exist for this asset/expiration
        assert!(!table::contains(&marketplace.market_lookup, lookup_key), 
                error::already_exists(E_MARKET_ALREADY_EXISTS));
        
        // Generate unique market ID
        let market_id = marketplace.market_counter;
        marketplace.market_counter = marketplace.market_counter + 1;
        
        // Create the new market using the individual market module
        let market_address = implied_volatility_market::init_volatility_market(
            creator,
            asset_symbol,
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
        marketplace_addr: address,
        market_id: u64,
        final_volatility: u64
    ) acquires Marketplace {
        let owner_addr = signer::address_of(owner);
        let marketplace = borrow_global<Marketplace>(marketplace_addr);
        
        assert!(marketplace.owner == owner_addr, error::permission_denied(E_NOT_AUTHORIZED));
        assert!(table::contains(&marketplace.market_addresses, market_id), error::not_found(E_MARKET_NOT_FOUND));
        
        // Get market address and delegate to individual market module
        let market_addr = *table::borrow(&marketplace.market_addresses, market_id);
        implied_volatility_market::settle_market(owner, market_addr, final_volatility);
    }

    // Transfer marketplace ownership
    public fun transfer_ownership(
        current_owner: &signer,
        marketplace_addr: address,
        new_owner: address
    ) acquires Marketplace {
        let owner_addr = signer::address_of(current_owner);
        let marketplace = borrow_global_mut<Marketplace>(marketplace_addr);
        
        assert!(marketplace.owner == owner_addr, error::permission_denied(E_NOT_AUTHORIZED));
        marketplace.owner = new_owner;
    }
}
}
