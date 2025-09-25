address marketplace {
// Defines a single marketplace for predicting the realized volatility of an asset 
// with a given expiration. Each marketplace creates a single IV token asset and manages 
// transactions for the assets through the AMM 
module implied_volatility_market {
    use std::error;
    use std::signer;
    use std::string;
    use std::option;
    use aptos_framework::timestamp;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::fungible_asset::{Self, Metadata, MintRef, BurnRef, TransferRef};
    use aptos_framework::primary_fungible_store::{Self};

    // Error codes
    const E_NOT_AUTHORIZED: u64 = 1;
    const E_MARKET_ALREADY_SETTLED: u64 = 2;
    const E_MARKET_NOT_EXPIRED: u64 = 3;

    // Capabilities for managing the IV token
    struct IVTokenRefs has store {
        mint_ref: MintRef,
        burn_ref: BurnRef,
        transfer_ref: TransferRef,
    }

    struct VolatilityMarket has key {
        // owner of the market
        owner: address,
        // timestamp when the market was created
        created_at_timestamp: u64,
        // timstamp when the market was settleed
        settled_at_timestamp: u64,
        // timestamp when the market expires and can be finalized
        expiration_timestamp: u64,
        // token asset this market is aiming to predict
        asset_symbol: string::String,
        // boolean representing if the market has been settled
        settled: bool,
        // observed historical volatility at settlement
        volatility: u64,
        // amm responsible for trade activity
        amm: AutomatedMarketMaker,
        // metadata object for the IV token
        iv_token_metadata: Object<Metadata>,
        // token management capabilities
        iv_token_refs: IVTokenRefs
    }

    struct AutomatedMarketMaker has store {
        // pool balance of IV tokens
        iv_token_reserves: u64,
        // virtual balance of USDC tokens
        virtual_usdc_token_reserves: u64
    }

    fun create_iv_token(
        object_signer: &signer,
        asset_symbol: string::String
    ) : (IVTokenRefs, Object<Metadata>) {
        let iv_token_name = asset_symbol;
        string::append(&mut iv_token_name, string::utf8(b" IV Token"));
        
        let fa_constructor_ref = &object::create_named_object(object_signer, b"iv_token");
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
          fa_constructor_ref,
          option::none(),
          iv_token_name,
          string::utf8(b"IV"),
          6,
          string::utf8(b""),
          string::utf8(b""),
        );
        
        let iv_token_metadata = object::object_from_constructor_ref<Metadata>(fa_constructor_ref);
        
        // Store token management capabilities
        let mint_ref = fungible_asset::generate_mint_ref(fa_constructor_ref);
        let burn_ref = fungible_asset::generate_burn_ref(fa_constructor_ref);
        let transfer_ref = fungible_asset::generate_transfer_ref(fa_constructor_ref);
        
        let token_refs = IVTokenRefs {
            mint_ref,
            burn_ref,
            transfer_ref,
        };

        (token_refs, iv_token_metadata)
    }

    fun create_market_and_mint_tokens(
        market_object_addr: address,
        creator_addr: address,
        asset_symbol: string::String,
        initial_volatility: u64,
        expiration_timestamp: u64,
        iv_token_metadata: Object<Metadata>,
        iv_token_refs: IVTokenRefs
    ) : VolatilityMarket {
        let token_decimals = 1000000; // 6 decimals (10^6)

        // Mint initial IV tokens to the market object
        let initial_iv_supply = 1000000 * token_decimals; // 1 million tokens with 6 decimals
        let iv_tokens = fungible_asset::mint(&iv_token_refs.mint_ref, initial_iv_supply);
        
        // Deposit tokens to the market object's primary store
        primary_fungible_store::deposit(market_object_addr, iv_tokens);
        
        // Calculate USDC reserves based on initial volatility, this creates an initial market
        // state where the future IV is equal to the current HV. The market can begin to discount
        // the future IV as it approaches expiration.
        let virtual_usdc_reserves = initial_iv_supply * initial_volatility;
    
        let market = VolatilityMarket {
            owner: creator_addr,
            created_at_timestamp: timestamp::now_seconds(),
            settled_at_timestamp: 0,
            expiration_timestamp,
            asset_symbol,
            settled: false,
            volatility: initial_volatility,
            amm: AutomatedMarketMaker {
                iv_token_reserves: initial_iv_supply,
                virtual_usdc_token_reserves: virtual_usdc_reserves
            },
            iv_token_metadata,
            iv_token_refs,
        };
    
        market
    }

    public fun init_volatility_market(
        creator: &signer,
        asset_symbol: string::String,
        initial_volatility: u64,
        expiration_timestamp: u64 
    ) : address {
        let creator_addr = signer::address_of(creator);
        
        // Create object to hold the market and its token balances
        let constructor_ref = object::create_object(creator_addr);
        let object_signer = object::generate_signer(&constructor_ref);
        let object_addr = signer::address_of(&object_signer);
        
        // Create the IV token as a fungible asset
        let (iv_token_refs, iv_token_metadata) = create_iv_token(&object_signer, asset_symbol);
        
        // Create market and mint tokens
        let market = create_market_and_mint_tokens(
            object_addr,
            creator_addr,
            asset_symbol,
            initial_volatility,
            expiration_timestamp,
            iv_token_metadata,
            iv_token_refs
        );
        
        // Store the market in the object
        move_to(&object_signer, market);
        
        object_addr
    }

    public fun settle_market(
        owner: &signer,
        market_addr: address,
        final_volatility: u64
    ) acquires VolatilityMarket {
        let owner_addr = signer::address_of(owner);
        let market = borrow_global_mut<VolatilityMarket>(market_addr);
        
        assert!(market.owner == owner_addr, error::permission_denied(E_NOT_AUTHORIZED));
        assert!(market.settled == false, error::invalid_argument(E_MARKET_ALREADY_SETTLED));
        assert!(market.expiration_timestamp < timestamp::now_seconds(), error::invalid_argument(E_MARKET_NOT_EXPIRED));
        
        market.volatility = final_volatility;
        market.settled = true;
        market.settled_at_timestamp = timestamp::now_seconds();
    }

    // Getter functions for testing and external access
    #[view]
    public fun get_owner(market_addr: address): address acquires VolatilityMarket {
        borrow_global<VolatilityMarket>(market_addr).owner
    }

    #[view]
    public fun get_asset_symbol(market_addr: address): string::String acquires VolatilityMarket {
        borrow_global<VolatilityMarket>(market_addr).asset_symbol
    }

    #[view]
    public fun get_volatility(market_addr: address): u64 acquires VolatilityMarket {
        borrow_global<VolatilityMarket>(market_addr).volatility
    }

    #[view]
    public fun get_expiration(market_addr: address): u64 acquires VolatilityMarket {
        borrow_global<VolatilityMarket>(market_addr).expiration_timestamp
    }

    #[view]
    public fun is_settled(market_addr: address): bool acquires VolatilityMarket {
        borrow_global<VolatilityMarket>(market_addr).settled
    }

    #[view]
    public fun get_amm_reserves(market_addr: address): (u64, u64) acquires VolatilityMarket {
        let market = borrow_global<VolatilityMarket>(market_addr);
        (market.amm.iv_token_reserves, market.amm.virtual_usdc_token_reserves)
    }

    #[view]
    public fun get_iv_token_metadata(market_addr: address): Object<Metadata> acquires VolatilityMarket {
        borrow_global<VolatilityMarket>(market_addr).iv_token_metadata
    }
}
}