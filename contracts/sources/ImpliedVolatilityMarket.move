address marketplace {
// Defines a single marketplace for predicting the realized volatility of an asset 
// with a given expiration. Each marketplace creates a single IV token asset and manages 
// transactions for the assets through the AMM 
module implied_volatility_market {
    use std::error;
    use std::signer;
    use std::string;
    use std::option;
    use std::table::{Self, Table};
    use std::vector::{Self};
    use aptos_framework::timestamp;
    use aptos_framework::object::{Self, Object, ExtendRef};
    use aptos_framework::fungible_asset::{Self, Metadata, MintRef, BurnRef, TransferRef};
    use aptos_framework::primary_fungible_store::{Self};
    use marketplace::isolated_margin_account::{Self, IsolatedMarginAccount};
    use marketplace::staking_vault::{Self};
    use marketplace::volatility_marketplace::{Self};

    friend marketplace::volatility_marketplace;

    // Error codes
    const E_NOT_AUTHORIZED: u64 = 1;
    const E_MARKET_ALREADY_SETTLED: u64 = 2;
    const E_MARKET_NOT_EXPIRED: u64 = 3;

    // This holds the ExtendRef, which we need to get a signer for the object so we can transfer funds.
    struct MarketRefs has key, store {
        extend_ref: ExtendRef,
    }

    // Capabilities for managing the IV token
    struct IVTokenRefs has store {
        mint_ref: MintRef,
        burn_ref: BurnRef,
        transfer_ref: TransferRef,
    }

    struct TokenReserves has store {
        // pool balance of IV tokens
        iv_token_reserves: u256,
        // virtual balance of USDC tokens (virtual to reduce slippage)
        virtual_usdc_token_reserves: u256
    }

    struct LiquidityPool has store {
        // token address to IV token
        iv_address: address,
        // token address for USDC token
        usdc_address: address,
        // token management capabilities
        iv_token_refs: IVTokenRefs,
        // asset store USDC
        usdc_store_address: address,
        // pool reserves
        reserves: TokenReserves
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
        settlement_price: u64,
        // liquidity pool responsible for managing token swaps
        pool: LiquidityPool,
        // margin accounts corresponding to users that have taken a short position
        margin_accounts: vector<address>,
        // isolated margin accounts
        isolated_margin_accounts: Table<address, address>,
        // staking vault address
        staking_vault_address: address,
        // swap fee
        swap_fee: u64,
        // token balances of each user address
        token_holders: vector<address>
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

    // private function that creates a new volaility market and mints new IV tokens for the market
    // The amount of tokens minted is dependent on the initial volatility param. The quote of the
    // market will match the initial volatility.
    fun create_market_and_mint_tokens(
        market_object_addr: address,
        creator_addr: address,
        asset_symbol: string::String,
        initial_volatility: u256,
        expiration_timestamp: u64,
        iv_token_metadata: Object<Metadata>,
        usdc_address: address,
        iv_token_refs: IVTokenRefs,
        staking_vault_address: address
    ) : VolatilityMarket {
        let token_decimals = 1000000; // 6 decimals (10^6)

        // Mint initial IV tokens to the market object
        let initial_iv_supply = 1000000 * token_decimals; // 1 million tokens with 6 decimals
        let iv_tokens = fungible_asset::mint(&iv_token_refs.mint_ref, initial_iv_supply);
        
        // Create primary fungible stores for the vault
        let usdc_metadata = object::address_to_object<Metadata>(usdc_address);
        let usdc_token_store = primary_fungible_store::create_primary_store(market_object_addr, usdc_metadata);
        
        // Deposit initial IV tokens to the IV token store
        primary_fungible_store::deposit(market_object_addr, iv_tokens);
        
        // Calculate USDC reserves based on initial volatility, this creates an initial market
        // state where the future IV is equal to the current HV. The market can begin to discount
        // the future IV as it approaches expiration.
        let virtual_usdc_reserves = ((initial_iv_supply as u256) * initial_volatility) / (token_decimals as u256);
        
        // Create the liquidity pool and assign reseve balances
        let pool = LiquidityPool {
            iv_address: object::object_address(&iv_token_metadata),
            usdc_address,
            iv_token_refs,
            usdc_store_address : object::object_address(&usdc_token_store),
            reserves: TokenReserves {
                iv_token_reserves: (initial_iv_supply as u256),
                virtual_usdc_token_reserves: virtual_usdc_reserves
            }
        };
    
        // create and return the new volatility market
        let market = VolatilityMarket {
            owner: creator_addr,
            created_at_timestamp: timestamp::now_seconds(),
            settled_at_timestamp: 0,
            expiration_timestamp,
            asset_symbol,
            settled: false,
            settlement_price: 0,
            pool,
            isolated_margin_accounts: table::new(),
            margin_accounts: vector[],
            staking_vault_address,
            swap_fee: 10000, // 1%
            token_holders: vector[]
        };
    
        market
    }

    public(friend) fun init_volatility_market(
        creator: &signer,
        asset_symbol: string::String,
        usdc_address: address,
        initial_volatility: u256,
        expiration_timestamp: u64,
        staking_vault_address: address
    ) : address {
        let creator_addr = signer::address_of(creator);
        
        // Create object to hold the market and its token balances
        let constructor_ref = object::create_object(creator_addr);
        let object_signer = object::generate_signer(&constructor_ref);
        let extend_ref = object::generate_extend_ref(&constructor_ref);
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
            usdc_address,
            iv_token_refs,
            staking_vault_address
        );
        
        // Store the market in the object
        move_to(&object_signer, market);
        move_to(&object_signer, MarketRefs { extend_ref });
        
        object_addr
    }

    // settles an implied volatility market at expiration. Currently this method takes 
    // the settlement price, but the final price should be calculated by the market itself. 
    // This can be acheived when AIP 125 (Scheduled Transactions) is implemented
    // The process of settling a market involves closing all short positions and paying
    // out the long positions at the settlement price. 
    public(friend) fun settle_market(
        owner: &signer,
        market_address: address,
        settlement_price: u64
    ) acquires VolatilityMarket, MarketRefs {
        let owner_addr = signer::address_of(owner);
        let market = borrow_global_mut<VolatilityMarket>(market_address);
        
        assert!(market.owner == owner_addr, error::permission_denied(E_NOT_AUTHORIZED));
        assert!(market.settled == false, error::invalid_argument(E_MARKET_ALREADY_SETTLED));
        assert!(market.expiration_timestamp < timestamp::now_seconds(), error::invalid_argument(E_MARKET_NOT_EXPIRED));
        
        // Update the market with settlement information
        market.settled = true;
        market.settlement_price = settlement_price;
        market.settled_at_timestamp = timestamp::now_seconds();

        // close short positions
        close_short_positions(market);

        // payout long positions at settlement price
        close_long_positions(market, market_address);

        // Transfer excess USDC to staking vault -- this represents the profit the vault
        // earned from taking the other side of trades. For example, a trader that bought
        // IV at 15, but it settled at 10. The process would only need to payout $10 and
        // the vault earned 5 USDC from the trade.
        let usdc_metadata = object::address_to_object<Metadata>(market.pool.usdc_address);
        let market_usdc_balance = primary_fungible_store::balance(market_address, usdc_metadata);

        if(market_usdc_balance > 0) {
            // setup object signer to transfer tokens from pool to user and staking vault (fees)
            let refs = borrow_global<MarketRefs>(market_address);
            let object_signer = object::generate_signer_for_extending(&refs.extend_ref);

            // Transfer USDC from market to vault
            let usdc_tokens = primary_fungible_store::withdraw(&object_signer, usdc_metadata, market_usdc_balance);
            primary_fungible_store::deposit(market.staking_vault_address, usdc_tokens);

            // Record the profit in the staking vault
            staking_vault::volatility_market_profit(market.staking_vault_address, market_usdc_balance);
        }
    }

    // Close the long positions that have been opened at the settlement price
    fun close_long_positions(
        market: &mut VolatilityMarket,
        market_address: address
    ) acquires MarketRefs {
        let i: u64 = 0;
        let len = vector::length(&market.token_holders);
        let iv_token_metadata = object::address_to_object<Metadata>(market.pool.iv_address);
        let usdc_metadata = object::address_to_object<Metadata>(market.pool.usdc_address);
        
        // close long positions for all token holders if they are still
        // holding tokens
        while (i < len) {
            let token_holder = *vector::borrow(&market.token_holders, i);
            let token_balance = primary_fungible_store::balance(token_holder, iv_token_metadata);
            
            // get the swap output amount and complete the swap in the pool
            // the market should already be closed at this point, so we should be using the 
            // settlement price
            if(token_balance > 0){
                let (amount_out, swap_fee) = get_swap_amount_out_internal(1, token_balance, market);

                // use the internal sell_to_close method instead of running though the swap
                // method which requires the user signer object
                sell_to_close_internal(
                    token_holder,
                    market,
                    market_address,
                    token_balance,
                    amount_out,
                    swap_fee
                );

            };

            i = i + 1;
        }
    }

    // Close the open short positions at the specified price
    // 1. Buy back IV tokens at the settlement price
    // 2. Repay the loaned USDC to the Vault
    // 3. Transfer the remaining USDC back to the owner
    fun close_short_positions(
        market: &mut VolatilityMarket
    ) {
        let i: u64 = 0;
        let len = vector::length(&market.margin_accounts);

        while (i < len) {
            let user_with_short_position = *vector::borrow(&market.margin_accounts, i);
            let margin_account_address = *table::borrow(&market.isolated_margin_accounts, user_with_short_position);
            let margin_account = isolated_margin_account::get_margin_account_state(margin_account_address);

            // determine the required input amount to receive the desired output amount
            let iv_units_borrowed = isolated_margin_account::get_iv_units_borrowed(&margin_account);
            let amount_in = get_swap_amount_in_internal(0, iv_units_borrowed, market);

            // transfer the input amount in USDC tokens to the vault
            // we don't need to manually buy the IV tokens back, then sell from the vault since
            // the price at this point is fixed. We can shortcut by calculating the USDC input
            // and transferring it directly to the vault.
            let usdc_metadata = object::address_to_object<Metadata>(market.pool.usdc_address);
            let margin_account_signer = isolated_margin_account::get_signer(margin_account_address);
            let usdc_tokens = primary_fungible_store::withdraw(&margin_account_signer, usdc_metadata, amount_in);
            primary_fungible_store::deposit(market.staking_vault_address, usdc_tokens);

            // transfer the remaining USDC from the margin account back to the user
            // this amount represents their profit or loss on the position
            let remaining_usdc = primary_fungible_store::balance(margin_account_address, usdc_metadata);
            primary_fungible_store::transfer(&margin_account_signer, usdc_metadata, user_with_short_position, remaining_usdc);

            // record the closing of the borrow
            isolated_margin_account::close_borrow(margin_account_address);

            i = i + 1;
        }
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
    public fun get_settlement_price(market_addr: address): u64 acquires VolatilityMarket {
        borrow_global<VolatilityMarket>(market_addr).settlement_price
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
    public fun get_amm_reserves(market_addr: address): (u256, u256) acquires VolatilityMarket {
        let market = borrow_global<VolatilityMarket>(market_addr);
        (market.pool.reserves.iv_token_reserves, market.pool.reserves.virtual_usdc_token_reserves)
    }

    #[view]
    public fun get_iv_token_metadata(market_addr: address): Object<Metadata> acquires VolatilityMarket {
        let market = borrow_global<VolatilityMarket>(market_addr);
        object::address_to_object<Metadata>(market.pool.iv_address)
    }

    // Calculate swap output amount using UniswapV2 constant product formula
    // swap_type: 0 = buy IV tokens (USDC -> IV), 1 = sell IV tokens (IV -> USDC)  
    #[view]
    public fun get_swap_amount_out(
        market_addr: address,
        swap_type: u8,
        amount_in: u64
    ): (u64, u64) acquires VolatilityMarket {
        let market = borrow_global<VolatilityMarket>(market_addr);
        
        return get_swap_amount_out_internal(swap_type, amount_in , market)
    }

    // Calculate required input amount for a desired output amount
    // swap_type: 0 = buy IV tokens (USDC -> IV), 1 = sell IV tokens (IV -> USDC)  
    #[view]
    public fun get_swap_amount_in(
        market_addr: address,
        swap_type: u8,
        amount_out: u64
    ): u64 acquires VolatilityMarket {
        let market = borrow_global<VolatilityMarket>(market_addr);
        
        return get_swap_amount_in_internal(swap_type, amount_out, market)
    }

    // get the quote for the current market
    // acquires VolatilityMarket
    #[view]
    public fun get_quote(
        market_addr: address
    ) : u64 acquires VolatilityMarket {
        let market = borrow_global<VolatilityMarket>(market_addr);
        
        get_quote_internal(market)
    }

    // get the quote for the given market. Internal method, that does not acquire any global state
    fun get_quote_internal(
        market: &VolatilityMarket
    ) : u64 {
        let factor = 1000000; // 10^6

        let quoteBig = (market.pool.reserves.virtual_usdc_token_reserves * factor) / market.pool.reserves.iv_token_reserves;

        (quoteBig as u64)
    }

    fun get_swap_amounts_for_settled_market(
        market: &VolatilityMarket,
        swap_type: u8,
        amount_in: u64
    ) : (u64, u64) {
        let factor = 1000000; // 10^6

        if (swap_type == 0){
            let swap_fees = (amount_in * market.swap_fee) / factor;
            let amount_in_after_fees = amount_in - swap_fees;
            let iv_token_amount = (amount_in_after_fees * factor) / market.settlement_price;

            (iv_token_amount, swap_fees)
        } else {
            let usdc_amount_out = (amount_in * market.settlement_price) / factor; 
            let swap_fees = (usdc_amount_out * market.swap_fee) / factor;
            let usdc_amount_out_after_fees = usdc_amount_out - swap_fees;

            (usdc_amount_out_after_fees, swap_fees)
        }
    }

    fun get_swap_amount_in_for_settled_market(
        market: &VolatilityMarket,
        swap_type: u8,
        amount_out: u64
    ): u64 {
        let factor = 1000000; // 10^6

        if (swap_type == 0) {
            // Buy IV tokens: calculate USDC input needed for desired IV output
            let usdc_before_fees = (amount_out * market.settlement_price) / factor;
            let amount_in = (usdc_before_fees * factor) / (factor - market.swap_fee);
            amount_in
        } else {
            // Sell IV tokens: calculate IV input needed for desired USDC output (after fees)
            let usdc_before_fees = (amount_out * factor) / (factor - market.swap_fee);
            let iv_amount_in = (usdc_before_fees * factor) / market.settlement_price;
            iv_amount_in
        }
    }

    // internal method to get amount out given reserves
    // avoids needing to acquire any global state
    fun get_swap_amount_out_internal(
        swap_type: u8,
        amount_in: u64,
        market: &VolatilityMarket
    ): (u64, u64)  {
        if(market.settled){
            get_swap_amounts_for_settled_market(market, swap_type, amount_in)
        } else {
            let iv_reserves = market.pool.reserves.iv_token_reserves;
            let usdc_reserves = market.pool.reserves.virtual_usdc_token_reserves;
            let amount_in_big = amount_in as u256;
            
            // Calculate output using constant product formula: x * y = k
            // amount_out = (amount_in * reserve_out) / (reserve_in + amount_in)
            if (swap_type == 0) {
                let swap_fees = (amount_in * market.swap_fee) / 1000000;
                let amount_in_with_fees = amount_in_big - (swap_fees as u256);
                let amount_out = (amount_in_with_fees * iv_reserves) / (usdc_reserves + amount_in_with_fees);

                (amount_out as u64, swap_fees as u64)
            } else {
                let amount_out_before_fees = ((amount_in_big * usdc_reserves) / (iv_reserves + amount_in_big)) as u64;
                let swap_fees = (amount_out_before_fees * market.swap_fee) / 1000000;
                let amount_out = amount_out_before_fees - swap_fees;

                (amount_out as u64, swap_fees as u64)
            }
        }
    }

    // internal method to get required input for a desired output amount
    // avoids needing to acquire any global state
    fun get_swap_amount_in_internal(
        swap_type: u8,
        amount_out: u64,
        market: &VolatilityMarket
    ): u64 {
        if(market.settled){
            get_swap_amount_in_for_settled_market(market, swap_type, amount_out)
        } else {
            let iv_reserves = market.pool.reserves.iv_token_reserves;
            let usdc_reserves = market.pool.reserves.virtual_usdc_token_reserves;
            let amount_out_big = amount_out as u256;
            
            // Calculate input using inverted constant product formula: x * y = k
            // amount_in = (reserve_in * amount_out) / (reserve_out - amount_out)
            // Then account for fees
            if (swap_type == 0) {
                // Buy IV tokens: need to calculate USDC input for desired IV output
                let amount_in_before_fees = (usdc_reserves * amount_out_big) / (iv_reserves - amount_out_big);
                
                // Need to solve for amount_in where (amount_in - fees) leads to desired output
                // Let x = amount_in, f = fee_rate (0.01 = 1%)
                // amount_out = ((x - x*f) * iv_reserves) / (usdc_reserves + (x - x*f))
                // Solving for x: x = (amount_out * usdc_reserves) / ((iv_reserves - amount_out) * (1 - f))
                let fee_factor = 1000000 - market.swap_fee; // 1 - fee_rate in basis points
                let amount_in = (amount_in_before_fees * 1000000) / (fee_factor as u256);
                
                (amount_in as u64)
            } else {
                // Sell IV tokens: need to calculate IV input for desired USDC output (after fees)
                // account_out_after_fees = amount_out, so we need to find amount_out_before_fees
                let amount_out_before_fees = (amount_out_big * 1000000) / (1000000 - market.swap_fee as u256);
                let amount_in = (iv_reserves * amount_out_before_fees) / (usdc_reserves - amount_out_before_fees);
                
                (amount_in as u64)
            }
        }
    }

    // Sell IV tokens: User pays IV tokens, receives USDC
    fun sell_to_close_internal(
        user_address: address,
        market: &mut VolatilityMarket,
        market_address: address,
        amount_in: u64,
        amount_out: u64,
        swap_fees: u64
    ) : u64 acquires MarketRefs {
        let usdc_metadata = object::address_to_object<Metadata>(market.pool.usdc_address);
        let required_usdc_balance = amount_out + swap_fees;

        // Ensure the market has enough USDC to tranfer (The vault covers any market shortfalls)
        let market_usdc_balance = primary_fungible_store::balance(market_address, usdc_metadata);

        if(market_usdc_balance < required_usdc_balance) {
            staking_vault::withdraw_from_vault(
                market.staking_vault_address, 
                market_address, 
                required_usdc_balance);
        };
        
        // Transfer IV tokens from user to market
        let iv_metadata = object::address_to_object<Metadata>(market.pool.iv_address);
        primary_fungible_store::transfer_with_ref(
            &market.pool.iv_token_refs.transfer_ref, 
            user_address, 
            market_address, 
            amount_in);
        
        // setup object signer to transfer tokens from pool to user and staking vault (fees)
        let refs = borrow_global<MarketRefs>(market_address);
        let object_signer = object::generate_signer_for_extending(&refs.extend_ref);

        // transfer swap fees to the staking pool
        let swap_fee_tokens = primary_fungible_store::withdraw(&object_signer, usdc_metadata, swap_fees);
        primary_fungible_store::deposit(market.staking_vault_address, swap_fee_tokens);

        // notify the staking vault of the swap fee earnings
        staking_vault::swap_fees_collected(market.staking_vault_address, swap_fees);

        // Transfer USDC from market to user (market owns the USDC, can withdraw directly)
        let usdc_tokens = primary_fungible_store::withdraw(&object_signer, usdc_metadata, amount_out);
        primary_fungible_store::deposit(user_address, usdc_tokens);
        
        // Update reserves: decrease USDC, increase IV tokens
        let virtual_reserves_adjustment = (amount_out + swap_fees as u256);

        if(virtual_reserves_adjustment > market.pool.reserves.virtual_usdc_token_reserves){
            market.pool.reserves.virtual_usdc_token_reserves = 0;
        } else {
            market.pool.reserves.virtual_usdc_token_reserves = market.pool.reserves.virtual_usdc_token_reserves - virtual_reserves_adjustment;
        };

        market.pool.reserves.iv_token_reserves = market.pool.reserves.iv_token_reserves + (amount_in as u256);

        amount_out
    }

    fun swap_internal (
        user: &signer,
        market: &mut VolatilityMarket,
        market_address: address,
        swap_type: u8,
        amount_in: u64
    ) : u64 acquires MarketRefs {
        let user_addr = signer::address_of(user);
        let usdc_metadata = object::address_to_object<Metadata>(market.pool.usdc_address);

        let (amount_out, swap_fees) = get_swap_amount_out_internal(swap_type, amount_in, market);
        
        if (swap_type == 0) {
            // transfer swap fees to the staking pool
            let swap_fee_tokens = primary_fungible_store::withdraw(user, usdc_metadata, swap_fees);
            primary_fungible_store::deposit(market.staking_vault_address, swap_fee_tokens);

            // notify the staking vault of the swap fee earnings
            staking_vault::swap_fees_collected(market.staking_vault_address, swap_fees);

            // Buy IV tokens: User pays USDC, receives IV tokens
            // Transfer USDC from user to market 
            
            let usdc_tokens = primary_fungible_store::withdraw(user, usdc_metadata, amount_in - swap_fees);
            primary_fungible_store::deposit(market_address, usdc_tokens);
            
            // Transfer IV tokens from market to user
            primary_fungible_store::transfer_with_ref(&market.pool.iv_token_refs.transfer_ref, market_address, user_addr, amount_out);
            
            // Update reserves: increase USDC, decrease IV tokens
            market.pool.reserves.virtual_usdc_token_reserves = market.pool.reserves.virtual_usdc_token_reserves + (amount_in as u256);
            market.pool.reserves.iv_token_reserves = market.pool.reserves.iv_token_reserves - (amount_out as u256);

            // record the token holder
            store_token_holder(market, user_addr);

            // return the output amount
            amount_out
        } else {
            sell_to_close_internal(
                user_addr,
                market,
                market_address,
                amount_in,
                amount_out,
                swap_fees
            )
        }
    }

    /// Perform a swap on the volatility market
    /// swap_type: 0 = buy IV tokens (USDC -> IV), 1 = sell IV tokens (IV -> USDC)
    public fun swap(
        user: &signer,
        market_addr: address,
        swap_type: u8,
        amount_in: u64
    ): u64 acquires VolatilityMarket, MarketRefs {
        let market = borrow_global_mut<VolatilityMarket>(market_addr);
        
        swap_internal(user, market, market_addr, swap_type, amount_in)
    }

    // Increment the users token balance by the given amount
    public fun store_token_holder(
        market: &mut VolatilityMarket,
        user_address: address
    ) {
        if(!vector::contains(&market.token_holders, &user_address)){
            vector::push_back(&mut market.token_holders, user_address);
        }
    }


    // Opens a new short position for the given user by creating a new isolated margin account
    // 1. Deposits collateral into the isolated margin account
    // 2. Borrows IV tokens from the market
    // 3. Swaps IV tokens for USDC
    // - The user will need to repay the borrowed IV tokens to close the position. If the IV price
    // falls, then they will close out at a profit, otherwise they will close out at a loss.
    // - User balances can be liquidiated if the margin account is undercollateralized.
    public fun open_short_position(
        user: &signer,
        market_addr: address,
        usdc_collateral_amount: u64
    ) acquires VolatilityMarket, MarketRefs {
        let market = borrow_global_mut<VolatilityMarket>(market_addr);
        let user_addr = signer::address_of(user);

        // ensure the user has a margin account
        let margin_account_address = ensure_margin_account_exists(market, user_addr);
        let margin_account_signer = isolated_margin_account::get_signer(margin_account_address);

        // transfer the usdc collateral amount to the margin account
        let usdc_metadata = object::address_to_object<Metadata>(market.pool.usdc_address);
        let usdc_tokens = primary_fungible_store::withdraw(user, usdc_metadata, usdc_collateral_amount);
        primary_fungible_store::deposit(margin_account_address, usdc_tokens);
        
        // mint and iv tokens to margin account (borrow)
        let quote = get_quote_internal(market);
        let iv_token_amount = (usdc_collateral_amount * 1000000) / quote;
        let iv_tokens = fungible_asset::mint(&market.pool.iv_token_refs.mint_ref, iv_token_amount);
        
        primary_fungible_store::deposit(margin_account_address, iv_tokens);

        // Ensure the market has enough liquidity to handle the short position
        // borrow usdc liquidity from the staking pool to facilitate the swap
        // this will not alter the quote of the pool, but it will increase the USDC
        // available to facilitate the margin sell. 
        // This balance will be repaid when the user closes the position.
        staking_vault::borrow_on_margin(
            &margin_account_signer,
            market_addr,
            market.staking_vault_address,
            usdc_collateral_amount
        );

        // Sell the tokens from the margin account
        swap(&margin_account_signer, market_addr, 1, iv_token_amount);

        // update the margin account balances
        isolated_margin_account::record_new_borrow(
            margin_account_address, 
            iv_token_amount, 
            usdc_collateral_amount 
        );
    }

    // creates a new margin account for the user if it does not already exist
    // otherwise, returns the existing margin account address
    fun ensure_margin_account_exists(
        market: &mut VolatilityMarket,
        user_address: address
    ) : address {
        if(table::contains(&market.isolated_margin_accounts, user_address)) {
            return *table::borrow(&market.isolated_margin_accounts, user_address)
        } else {
            let margin_account_address = isolated_margin_account::new(user_address);

            vector::push_back(&mut market.margin_accounts, user_address);
            table::add(&mut market.isolated_margin_accounts, user_address, margin_account_address);
            
            margin_account_address
        }
    }

    // gets the collateral and iv units borrowed for the given margin account
    #[view]
    public fun get_margin_account_state(
        market_address: address,
        account_address: address
    ) : IsolatedMarginAccount acquires VolatilityMarket {
        let market = borrow_global<VolatilityMarket>(market_address);

        if(!table::contains(&market.isolated_margin_accounts, account_address)) {
            return isolated_margin_account::empty(account_address)
        } else {
            let margin_account_address = *table::borrow(&market.isolated_margin_accounts, account_address);

            return isolated_margin_account::get_margin_account_state(margin_account_address)
        }
    }
}
}
