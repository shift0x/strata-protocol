address marketplace {
module options_exchange {
    use std::error;
    use std::signer;
    use std::debug;
    use std::vector;
    use std::table::{Self, Table};
    use std::string::{Self, String};
    use aptos_framework::timestamp;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::primary_fungible_store::{Self};
    use aptos_framework::fungible_asset::{Self, Metadata};
    use aptos_framework::event;
    use marketplace::binomial_option_pricing::{Self, Greeks};
    use marketplace::isolated_margin_account;
    use marketplace::price_oracle;
    use marketplace::volatility_marketplace;
    use marketplace::staking_vault;
    use pyth::pyth;
    use aptos_framework::coin;

    // ------------------------------------------------------------------------
    // Constants and errors
    // ------------------------------------------------------------------------

    const E_U64_OVERFLOW: u64 = 1;
    const E_POSITION_EMPTY: u64 = 2;
    const E_POSITION_NOT_FOUND: u64 = 3;
    const E_POSITION_CLOSED: u64 = 4;
    const E_UNAUTHORIZED: u64 = 5;
    const E_POSITION_NOT_OPEN: u64 = 6;

    const ONE_E_18: u256 = 1000000000000000000u256;

    // ------------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------------

    #[event]
    struct ExchangeCreated has drop, store {
        exchange_address: address,
        oracle_address: address,
        creator: address,
        usdc_address: address,
    }

    #[event]
    struct MarginAccountCreated has drop, store {
        exchange_address: address,
        user: address,
        margin_account_address: address,
    }

    #[event]
    struct PositionOpened has drop, store {
        exchange_address: address,
        position_id: u64,
        trader: address,
        asset_symbol: String,
        legs_count: u64,
        net_debit: u256,
        net_credit: u256,
        initial_margin: u256,
        net_amount_required: u256,
    }

    #[event]
    struct PositionClosed has drop, store {
        exchange_address: address,
        position_id: u64,
        trader: address,
        asset_symbol: String,
        profit: u256,
        loss: u256,
        amount_returned: u256,
    }

    // 1e18 fixed-point scaling used by the pricing model
    const ONE_E18: u256 = 1000000000000000000u256;
    const ONE_E12: u256 = 1000000000000u256;

    // Basis points to 1e18 fixed-point: 1 bp = 1e-4 => 1e14 in 1e18 fp
    const ONE_BP_IN_FP: u256 = 100000000000000u256; // 1e14

    // Time constants
    const SECONDS_PER_DAY: u256 = 86400;

    // Maintenance margin percent in bps (e.g., 7500 = 75%)
    const MAINTENANCE_MARGIN_BPS: u64 = 7500;

    // The multiplier per contract (100 to emulate equities)
    const CONTRACT_MULTIPLIER: u64 = 100;

    // ------------------------------------------------------------------------
    // Enums and data structures
    // ------------------------------------------------------------------------

    enum OrderStatus has copy, drop, store {
        OPEN,
        CLOSED,
        CANCELLED,
        EXPIRED,
    }

    enum OptionType has copy, drop, store {
        CALL,
        PUT,
    }

    enum Side has copy, drop, store {
        LONG,
        SHORT,
    }

    struct PositionLeg has store, drop, copy {
        // the type of the option (call or put)
        option_type: OptionType,
        // the side of the position (long or short)
        side: Side,
        // number of contracts (nonzero)
        amount: u256,
        // strike price expressed in the same base units as underlying_price
        strike_price: u256,
        // expiration timestamp (seconds since epoch)
        expiration: u64
    }

    struct Position has store, drop, copy {
        // the unique id of the position
        id: u64,
        // the trader that opened the position
        trader_address: address,
        // the symbol of the underlying asset
        asset_symbol: String,
        // the legs accociated with the position
        legs: vector<PositionLeg>,
        // execution status and bookkeeping
        status: OrderStatus,
        // quote at the opening of the position
        opening_quote: Quote,
        // quote at the closing of the position
        closing_quote: Quote,
    }

    struct Quote has store, drop, copy {
        // debit amount for the position
        net_debit: u256,
        // credit amount for the position
        net_credit: u256,
        // initial margin for the position
        initial_margin: u256,
        // maintenance margin for the position
        maintenance_margin: u256,
        // the timestamp of the quote
        timestamp: u64,
        // the volatility used to generate the quote
        volatility: u256,
        // the underlying price use to generate the quote
        underlying_price: u256,
        // the risk free rate used in the calculation
        risk_free_rate: u256
    }

    struct MarginAccount has store, drop, copy {
        // the total margin available to the user
        total_margin: u256,
        // the total margin used by the user
        used_margin: u256,
    }

    struct OptionsExchange has key {
        // list of all user positions
        user_positions: vector<Position>,
        // mapping of users to their positions
        user_position_lookup: Table<address, vector<u64>>,
        // mapping of users to their margin accounts
        user_margin_accounts: Table<address, address>,
        // counter for positions created in the exchange
        position_counter: u64,
        // address of usdc token
        usdc_address: address,
        // address of the price oracle
        oracle_address: address,
    }

    fun reconstruct_position(
        asset_symbol: String,
        leg_option_types: vector<u8>,
        leg_option_sides: vector<u8>,
        leg_option_amounts: vector<u256>,
        leg_option_strike_prices: vector<u256>,
        leg_option_expirations: vector<u64>
    ) : Position {
        // construct position legs from component vectors
        let legs = vector::empty<PositionLeg>();
        let num_legs = vector::length(&leg_option_types);
        let i = 0;
        while (i < num_legs) {
            let option_type = if (*vector::borrow(&leg_option_types, i) == 0) {
                OptionType::CALL
            } else {
                OptionType::PUT
            };
            
            let side = if (*vector::borrow(&leg_option_sides, i) == 0) {
                Side::LONG
            } else {
                Side::SHORT
            };
            
            let leg = create_position_leg(
                option_type,
                side,
                *vector::borrow(&leg_option_amounts, i),
                *vector::borrow(&leg_option_strike_prices, i),
                *vector::borrow(&leg_option_expirations, i)
            );
            vector::push_back(&mut legs, leg);
            i = i + 1;
        };

        // create the user position
        create_position(0, asset_symbol, legs)
    }

    public entry fun update_price_feed_and_open_position(
        user: &signer,
        underlying_price_update: vector<vector<u8>>,
        risk_free_rate_price_update: vector<vector<u8>>,
        marketplace_address: address,
        exchange_address: address,
        asset_symbol: String,
        leg_option_types: vector<u8>,
        leg_option_sides: vector<u8>,
        leg_option_amounts: vector<u256>,
        leg_option_strike_prices: vector<u256>,
        leg_option_expirations: vector<u64>
    ) acquires OptionsExchange {
        /*
         * Ideally i would like to update the price feed and subsequently read from the feed, however I get an VM
         * error when trying to update the price feed with the data returned from the pyth api. As such, we parse
         * the price feed update and store it in the mock price oracle. 
         *
         * I suspect this is a testnet specific issue
         *
         * Commenting out the price updates for now as they are not working
         */
        
        // update underlying price
        // let underlying_price_coins = coin::withdraw(user, pyth::get_update_fee(&underlying_price_update));
        // pyth::update_price_feeds(underlying_price_update, underlying_price_coins);

        // update risk free rate
        // let risk_free_rate_coins = coin::withdraw(user, pyth::get_update_fee(&underlying_price_update));
        // pyth::update_price_feeds(risk_free_rate_price_update, risk_free_rate_coins);
        
        open_position(
            user, 
            marketplace_address,
            exchange_address,
            asset_symbol,
            leg_option_types,
            leg_option_sides,
            leg_option_amounts,
            leg_option_strike_prices,
            leg_option_expirations
        );
    }

    // entry functions
    public fun open_position(
        user: &signer,
        marketplace_address: address,
        exchange_address: address,
        asset_symbol: String,
        leg_option_types: vector<u8>,
        leg_option_sides: vector<u8>,
        leg_option_amounts: vector<u256>,
        leg_option_strike_prices: vector<u256>,
        leg_option_expirations: vector<u64>
    ) acquires OptionsExchange {
        let exchange = borrow_global_mut<OptionsExchange>(exchange_address);
        let user_addr = signer::address_of(user);

        // ensure the user exists
        ensure_user_created(user_addr, exchange, exchange_address);

        let position = reconstruct_position(
            asset_symbol,
            leg_option_types,
            leg_option_sides,
            leg_option_amounts,
            leg_option_strike_prices,
            leg_option_expirations
        );

        position.id = exchange.position_counter + 1;
        position.trader_address = user_addr;

        let user_positions_ref = table::borrow_mut<address, vector<u64>>(&mut exchange.user_position_lookup, user_addr);
        vector::push_back(user_positions_ref, position.id);
        
        // update the position counter
        exchange.position_counter = exchange.position_counter + 1;

        // execute the trade
        execute_open_position(user, &mut position, marketplace_address, exchange);

        // Emit position opened event
        event::emit(PositionOpened {
            exchange_address,
            position_id: position.id,
            trader: position.trader_address,
            asset_symbol: position.asset_symbol,
            legs_count: vector::length(&position.legs) as u64,
            net_debit: position.opening_quote.net_debit,
            net_credit: position.opening_quote.net_credit,
            initial_margin: position.opening_quote.initial_margin,
            net_amount_required: position.opening_quote.net_debit + 
                position.opening_quote.initial_margin - 
                position.opening_quote.net_credit,
        });

        vector::push_back(&mut exchange.user_positions, position);
    }

    public entry fun close_position(
        user: &signer,
        marketplace_address: address,
        exchange_address: address,
        position_id: u64
    ) acquires OptionsExchange {
        let exchange = borrow_global_mut<OptionsExchange>(exchange_address);
        let user_addr = signer::address_of(user);

        // ensure the position exists
        assert!(position_id <= exchange.position_counter, E_POSITION_NOT_FOUND);

        let position = vector::borrow(&mut exchange.user_positions, position_id-1);

        // ensure the position is open
        assert!(position.status == OrderStatus::OPEN, E_POSITION_NOT_OPEN);

        // ensure the position is owned by the user
        assert!(position.trader_address == user_addr, E_UNAUTHORIZED);

        // close the position
        execute_close_position(user, exchange, marketplace_address, exchange_address, position_id-1);
    }

    public fun create_exchange(
        owner: &signer,
        usdc_address: address
    ) : (address, address) {
        let creator_addr = signer::address_of(owner);

        // create the price oracle
        let oracle_address = price_oracle::create(owner);

        // Create the new exchange
        let constructor_ref = object::create_object(creator_addr);
        let object_signer = object::generate_signer(&constructor_ref);
        let object_addr = signer::address_of(&object_signer);

        let exchange = OptionsExchange { 
            user_positions: vector::empty<Position>(),
            user_position_lookup: table::new<address, vector<u64>>(),
            user_margin_accounts: table::new<address, address>(),
            position_counter: 0,
            usdc_address,
            oracle_address
        };

        move_to<OptionsExchange>(&object_signer, exchange);

        // Emit exchange created event
        event::emit(ExchangeCreated {
            exchange_address: object_addr,
            oracle_address: oracle_address,
            creator: creator_addr,
            usdc_address,
        });

        (object_addr, oracle_address)
    }

    fun get_quote_for_position(
        position: &Position,
        marketplace_address: address,
        oracle_address: address
    ) : Quote {
        // get the current IV from the volatility marketplace
        let volatility_bps = volatility_marketplace::get_implied_volatility(
            marketplace_address, 
            position.asset_symbol
        );

        // get the underlying price from the oracle
        let underlying_price = price_oracle::get_price(oracle_address, position.asset_symbol);

        // get the risk free rate from the oracle
        let risk_free_rate_bps = price_oracle::get_price(oracle_address, string::utf8(b"Rates.US10Y"));

        let (
            asset_symbol, 
            leg_option_types, 
            leg_option_sides, 
            leg_option_amounts, 
            leg_option_strike_prices, 
            leg_option_expirations) = deconstruct_position(*position);

        price_position(
            asset_symbol,
            leg_option_types,
            leg_option_sides,
            leg_option_amounts,
            leg_option_strike_prices,
            leg_option_expirations,
            underlying_price, 
            risk_free_rate_bps, 
            volatility_bps, 
            timestamp::now_seconds()
        )
    }

    fun execute_close_position(
        trader: &signer,
        exchange: &mut OptionsExchange,
        marketplace_address: address,
        exchange_address: address,
        position_id: u64
    ) {
        let position = vector::borrow_mut(&mut exchange.user_positions, position_id);
        let trader_address = signer::address_of(trader);
        
        // quote the position to determine net debit and margin amounts
        position.closing_quote = get_quote_for_position(position, marketplace_address, exchange.oracle_address);

        // determine the profit or loss on the position
        let opening_debit = position.opening_quote.net_debit;
        let closing_debit = position.closing_quote.net_debit;
        let opening_credit = position.opening_quote.net_credit;
        let closing_credit = position.closing_quote.net_credit;

        let (profit, loss) = if(opening_debit > 0){
            if(closing_debit > opening_debit){
                (closing_debit - opening_debit, 0)
            } else {
                (0, opening_debit - closing_debit)
            }
        } else {
            if(opening_credit > closing_credit){
                (opening_credit - closing_credit, 0)
            } else {
                (0, closing_credit - opening_credit)
            }
        };

        let initial_trader_deposit = position.opening_quote.net_debit + 
            position.opening_quote.initial_margin - 
            position.opening_quote.net_credit; 

        let transfer_amount_to_trader = initial_trader_deposit;
        let user_margin_account = *table::borrow(&exchange.user_margin_accounts, trader_address);

        // setup vars for transfer
        let margin_account_signer = isolated_margin_account::get_signer(user_margin_account);
        let usdc_metadata = object::address_to_object<Metadata>(exchange.usdc_address);
        let staking_vault_address = volatility_marketplace::get_staking_vault_address(marketplace_address); 
        
        if(profit > 0){ // transfer the profit amount from the vault to the margin account
            let profit_64 = ((profit / ONE_E12) as u64) + 1; // we need to round up

            staking_vault::withdraw_from_vault(
                staking_vault_address, 
                user_margin_account, 
                profit_64);

            transfer_amount_to_trader = transfer_amount_to_trader + profit;
        } else if(loss > 0){ // transfer the loss from the margin account to the vault
            let loss_64 = (loss / ONE_E12) as u64;
            let usdc_tokens = primary_fungible_store::withdraw(
                &margin_account_signer, 
                usdc_metadata, 
                loss_64);
            
            primary_fungible_store::deposit(staking_vault_address, usdc_tokens); 

            // record the profit by the vault
            staking_vault::volatility_market_profit(staking_vault_address, loss_64);

            // reduce the trader output by the position loss amount
            if(loss > transfer_amount_to_trader){
                transfer_amount_to_trader = 0;
            } else {
                transfer_amount_to_trader = transfer_amount_to_trader - loss;
            }
        };

        if(transfer_amount_to_trader > 0){
            let transfer_amount_trader_64 = (transfer_amount_to_trader / ONE_E12) as u64;

            let usdc_tokens = primary_fungible_store::withdraw(
                &margin_account_signer, 
                usdc_metadata, 
                transfer_amount_trader_64);
            
            primary_fungible_store::deposit(trader_address, usdc_tokens); 
        };
        

        // update the position status
        position.status = OrderStatus::CLOSED;

        // Emit position closed event
        event::emit(PositionClosed {
            exchange_address,
            position_id: position.id,
            trader: trader_address,
            asset_symbol: position.asset_symbol,
            profit,
            loss,
            amount_returned: transfer_amount_to_trader,
        });
    }

    fun execute_open_position(
        user: &signer,
        position: &mut Position,
        marketplace_address: address,
        exchange: &mut OptionsExchange
    ) {
        // quote the position to determine net debit and margin amounts
        position.opening_quote = get_quote_for_position(position, marketplace_address, exchange.oracle_address);

        // determine the amount required to open the position
        let net_user_amount_in = position.opening_quote.net_debit + 
            position.opening_quote.initial_margin - 
            position.opening_quote.net_credit;

        let net_user_amount_in_64 = net_user_amount_in / ONE_E12; // downscale to 6 decimals

        // transfer usdc to the user margin account
        let user_address = signer::address_of(user);
        let usdc_metadata = object::address_to_object<Metadata>(exchange.usdc_address);
        
        let usdc_tokens = primary_fungible_store::withdraw(user, usdc_metadata, net_user_amount_in_64 as u64);
        let user_margin_account = *table::borrow(&exchange.user_margin_accounts, user_address);
        primary_fungible_store::deposit(user_margin_account, usdc_tokens);
        
        // update the position status
        position.status = OrderStatus::OPEN;
    }


    fun ensure_user_created(
        user_address: address,
        exchange: &mut OptionsExchange,
        exchange_address: address
    ) {
        if (!table::contains<address, vector<u64>>(&exchange.user_position_lookup, user_address)) {
            // create the user position list
            let empty: vector<u64> = vector::empty<u64>();
            table::add(&mut exchange.user_position_lookup, user_address, empty);

            // create the user margin account
            let margin_account = isolated_margin_account::new(user_address);
            table::add(&mut exchange.user_margin_accounts, user_address, margin_account);

            // Emit margin account created event
            event::emit(MarginAccountCreated {
                exchange_address,
                user: user_address,
                margin_account_address: margin_account,
            });
        };
    }

    #[view]
    public fun get_user_positions(
        exchange_address: address,
        user_address: address
    ) : vector<Position> acquires OptionsExchange {
        let exchange = borrow_global<OptionsExchange>(exchange_address);
        let result = vector::empty<Position>();

        if (table::contains<address, vector<u64>>(&exchange.user_position_lookup, user_address)) {
            let position_ids = *table::borrow(&exchange.user_position_lookup, user_address);
        
            vector::for_each(position_ids, |position_id| {
                let position = exchange.user_positions[position_id-1];
                vector::push_back(&mut result, position);
            });
        };

        result
    }

    public fun deconstruct_position(
        position: Position
    ): (String, vector<u8>, vector<u8>, vector<u256>, vector<u256>, vector<u64>) {
        let asset_symbol = position.asset_symbol;
        let legs = &position.legs;
        let num_legs = vector::length(legs);
        
        let leg_option_types = vector::empty<u8>();
        let leg_option_sides = vector::empty<u8>();
        let leg_option_amounts = vector::empty<u256>();
        let leg_option_strike_prices = vector::empty<u256>();
        let leg_option_expirations = vector::empty<u64>();
        
        let i = 0;
        while (i < num_legs) {
            let leg = vector::borrow(legs, i);
            
            // Convert OptionType to u8: CALL = 0, PUT = 1
            let option_type_u8 = if (leg.option_type == OptionType::CALL) { 0u8 } else { 1u8 };
            vector::push_back(&mut leg_option_types, option_type_u8);
            
            // Convert Side to u8: LONG = 0, SHORT = 1
            let side_u8 = if (leg.side == Side::LONG) { 0u8 } else { 1u8 };
            vector::push_back(&mut leg_option_sides, side_u8);
            
            vector::push_back(&mut leg_option_amounts, leg.amount);
            vector::push_back(&mut leg_option_strike_prices, leg.strike_price);
            vector::push_back(&mut leg_option_expirations, leg.expiration);
            
            i = i + 1;
        };
        
        (asset_symbol, leg_option_types, leg_option_sides, leg_option_amounts, leg_option_strike_prices, leg_option_expirations)
    }

    // ------------------------------------------------------------------------
    // Position Getters
    // ------------------------------------------------------------------------

    public fun get_position_id(position: &Position): u64 {
        position.id
    }

    public fun get_position_opening_debit(position: &Position): u256 {
        position.opening_quote.net_debit
    }

    public fun get_position_trader_address(position: &Position): address {
        position.trader_address
    }

    public fun get_position_asset_symbol(position: &Position): String {
        position.asset_symbol
    }

    public fun get_position_legs(position: &Position): vector<PositionLeg> {
        position.legs
    }

    public fun is_position_open(position: &Position): bool {
        position.status == OrderStatus::OPEN
    }

    public fun get_position_opening_quote(position: &Position): Quote {
        position.opening_quote
    }

    public fun get_position_closing_quote(position: &Position): Quote {
        position.closing_quote
    }

    // PositionLeg getters
    public fun get_position_leg_option_type(leg: &PositionLeg): OptionType {
        leg.option_type
    }

    public fun get_position_leg_side(leg: &PositionLeg): Side {
        leg.side
    }

    public fun get_position_leg_amount(leg: &PositionLeg): u256 {
        leg.amount
    }

    public fun get_position_leg_strike_price(leg: &PositionLeg): u256 {
        leg.strike_price
    }

    public fun get_position_leg_expiration(leg: &PositionLeg): u64 {
        leg.expiration
    }

    // ------------------------------------------------------------------------
    // Quoting (premium) and margin
    // ------------------------------------------------------------------------

    public fun get_days_to_expiration(
        expiration: u64
    ) : u256 {
        let current_time_secs = timestamp::now_seconds();

        if (expiration > current_time_secs) {
            let time_diff = (expiration - current_time_secs) as u256;

            (time_diff * ONE_E_18) / SECONDS_PER_DAY
        } else {
            0
        }
    }
    // Inputs:
    // - underlying_price: in asset's base units (same units as strike and multiplier effects)
    // - risk_free_rate_bps: annualized rate in basis points (e.g., 500 = 5.00%)
    // - volatility_bps: annualized implied vol in basis points (e.g., 2000 = 20.00%)
    // - current_time_secs: UNIX timestamp (seconds)
    #[view]
    public fun price_position(
        asset_symbol: String,
        leg_option_types: vector<u8>,
        leg_option_sides: vector<u8>,
        leg_option_amounts: vector<u256>,
        leg_option_strike_prices: vector<u256>,
        leg_option_expirations: vector<u64>,
        underlying_price: u256,
        risk_free_rate_bps: u256,
        volatility_bps: u256,
        current_time_secs: u64
    ): Quote {
        let position = reconstruct_position(
            asset_symbol,
            leg_option_types,
            leg_option_sides,
            leg_option_amounts,
            leg_option_strike_prices,
            leg_option_expirations
        );

        let legs_ref = &position.legs;
        let n = vector::length<PositionLeg>(legs_ref);
        assert!(n > 0, E_POSITION_EMPTY);

        // Accumulators in u256
        let net_debit_u256 = 0u256;
        let net_credit_u256 = 0u256;

        let i = 0;
        while (i < n) {
            let leg_ref = vector::borrow<PositionLeg>(legs_ref, i);
            let days_to_exp = get_days_to_expiration(leg_ref.expiration);

            let is_call = if (leg_ref.option_type == OptionType::CALL) {
                true
            } else {
                false
            };

            // Price per underlying unit in 1e18 fp
            let k_fp = leg_ref.strike_price;
            let premium_fp = binomial_option_pricing::get_option_price(
                underlying_price,
                k_fp,
                risk_free_rate_bps,
                volatility_bps,
                days_to_exp,
                is_call
            );

            // Convert to quote currency units per contract, then multiply by amount
            // 1 contract = 100 shares (like stocks)
            let per_contract_premium = premium_fp * (CONTRACT_MULTIPLIER as u256); 

            // calculate the total leg premium by multiplying the contract cost by the 
            // number of units requested
            let leg_total_premium = mul_div_u256(
                per_contract_premium,
                leg_ref.amount,
                ONE_E18
            );

            if (leg_ref.side == Side::LONG) {
                net_debit_u256 = net_debit_u256 + leg_total_premium;
            } else {
                net_credit_u256 = net_credit_u256 + leg_total_premium;
            };

            i = i + 1;
        };

        // Initial margin via standard broker margin methodology
        let initial_margin_u256 = calculate_standard_margin(
            legs_ref,
            underlying_price
        );

        let maintenance_margin_u256 = (initial_margin_u256 * (MAINTENANCE_MARGIN_BPS as u256)) / 10000u256;
        
        Quote {
            net_debit: net_debit_u256,
            net_credit: net_credit_u256,
            initial_margin: initial_margin_u256,
            maintenance_margin: maintenance_margin_u256,
            timestamp: current_time_secs,
            volatility: volatility_bps,
            underlying_price: underlying_price,
            risk_free_rate: risk_free_rate_bps
        }
    }

    // ------------------------------------------------------------------------
    // Margin engine (standard broker methodology)
    // ------------------------------------------------------------------------

    // Calculate initial margin using standard broker methodology
    // This implements the 3-step process used by most brokers
    fun calculate_standard_margin(
        legs: &vector<PositionLeg>,
        underlying_price: u256
    ): u256 {
        let n = vector::length<PositionLeg>(legs);
        
        // For single leg positions, use direct calculation
        if (n == 1) {
            let leg = vector::borrow<PositionLeg>(legs, 0);
            return calculate_single_leg_margin(leg, underlying_price);
        };
        
        // For multi-leg positions, find short call and short put components
        let short_call_margin = 0u256;
        let short_put_margin = 0u256;
        let short_call_premium = 0u256;
        let short_put_premium = 0u256;
        
        let i = 0;
        while (i < n) {
            let leg = vector::borrow<PositionLeg>(legs, i);
            
            if (leg.side == Side::SHORT) {
                // Calculate premium for this short leg (simplified - using intrinsic + time value estimate)
                let premium = calculate_leg_premium_estimate(leg, underlying_price);
                
                if (leg.option_type == OptionType::CALL) {
                    let margin = calculate_short_call_margin(leg, underlying_price, premium);
                    short_call_margin = short_call_margin + margin;
                    short_call_premium = short_call_premium + premium;
                } else {
                    let margin = calculate_short_put_margin(leg, underlying_price, premium);
                    short_put_margin = short_put_margin + margin;
                    short_put_premium = short_put_premium + premium;
                };
            };
            
            i = i + 1;
        };
        
        // Step 3: Determine total margin as the higher of the two combinations
        let combination_a = short_call_margin + short_put_premium;
        let combination_b = short_put_margin + short_call_premium;
        
        if (combination_a > combination_b) { combination_a } else { combination_b }
    }
    
    // Calculate margin for a single leg position
    fun calculate_single_leg_margin(
        leg: &PositionLeg, 
        underlying_price: u256
    ): u256 {
        // Long positions don't require margin beyond premium paid
        if (leg.side == Side::LONG) {
            return 0u256;
        };
        
        // For short positions, calculate premium and margin
        let premium = calculate_leg_premium_estimate(leg, underlying_price);
        
        if (leg.option_type == OptionType::CALL) {
            calculate_short_call_margin(leg, underlying_price, premium)
        } else {
            calculate_short_put_margin(leg, underlying_price, premium)
        }
    }
    
    // Step 1: Calculate margin for short call
    // Margin = max(20% of underlying - OTM amount + premium, 10% of underlying + premium)
    fun calculate_short_call_margin(
        leg: &PositionLeg,
        underlying_price: u256, 
        premium: u256
    ): u256 {
        // Contract value: underlying_price (scaled) × amount × CONTRACT_MULTIPLIER, then unscale
        let contract_value = (underlying_price * leg.amount * (CONTRACT_MULTIPLIER as u256)) / ONE_E18;
        
        // Calculation A: 20% of underlying - OTM amount + premium
        let calc_a = if (leg.strike_price > underlying_price) {
            // Call is OTM (strike > underlying)
            let price_diff = leg.strike_price - underlying_price; // Both scaled, difference scaled
            let otm_amount = (price_diff * leg.amount * (CONTRACT_MULTIPLIER as u256)) / ONE_E18;
            let base_margin = (contract_value * 20) / 100; // 20% of underlying value
            if (base_margin > otm_amount) {
                base_margin - otm_amount + premium
            } else {
                premium // Margin can't go below premium
            }
        } else {
            // Call is ITM or ATM
            ((contract_value * 20) / 100) + premium // 20% of underlying + premium
        };
        
        // Calculation B: 10% of underlying + premium
        let calc_b = ((contract_value * 10) / 100) + premium;
        
        // Return the greater of the two
        if (calc_a > calc_b) { calc_a } else { calc_b }
    }
    
    // Step 2: Calculate margin for short put  
    // Margin = max(20% of underlying - OTM amount + premium, 10% of strike + premium)
    fun calculate_short_put_margin(
        leg: &PositionLeg,
        underlying_price: u256,
        premium: u256
    ): u256 {
        // Contract value based on underlying price
        let contract_value = (underlying_price * leg.amount * (CONTRACT_MULTIPLIER as u256)) / ONE_E18;
        // Strike value for calculation B
        let strike_value = (leg.strike_price * leg.amount * (CONTRACT_MULTIPLIER as u256)) / ONE_E18;
        
        // Calculation A: 20% of underlying - OTM amount + premium
        let calc_a = if (underlying_price > leg.strike_price) {
            // Put is OTM (underlying > strike)
            let price_diff = underlying_price - leg.strike_price; // Both scaled, difference scaled
            let otm_amount = (price_diff * leg.amount * (CONTRACT_MULTIPLIER as u256)) / ONE_E18;
            let base_margin = (contract_value * 20) / 100; // 20% of underlying value
            if (base_margin > otm_amount) {
                base_margin - otm_amount + premium
            } else {
                premium // Margin can't go below premium
            }
        } else {
            // Put is ITM or ATM
            ((contract_value * 20) / 100) + premium // 20% of underlying + premium
        };
        
        // Calculation B: 10% of strike + premium
        let calc_b = ((strike_value * 10) / 100) + premium;
        
        // Return the greater of the two
        if (calc_a > calc_b) { calc_a } else { calc_b }
    }
    
    // Simplified premium estimation for margin calculation
    // In practice, this would use the actual option pricing model
    fun calculate_leg_premium_estimate(
        leg: &PositionLeg,
        underlying_price: u256
    ): u256 {
        // Calculate intrinsic value
        let intrinsic = if (leg.option_type == OptionType::CALL) {
            if (underlying_price > leg.strike_price) {
                underlying_price - leg.strike_price
            } else {
                0u256
            }
        } else {
            if (leg.strike_price > underlying_price) {
                leg.strike_price - underlying_price
            } else {
                0u256
            }
        };
        
        // Add simple time value estimate (5% of underlying for ATM options)
        let time_value = underlying_price / 20; // 5% base time value (already scaled)
        let total_premium_per_unit = intrinsic + time_value; // Both scaled by 1e18
        
        // Scale by contract multiplier and amount, then unscale to get final premium
        (total_premium_per_unit * leg.amount * (CONTRACT_MULTIPLIER as u256)) / ONE_E18
    }

    // ------------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------------

    // Safe multiply/divide: (a * b) / denom in u256
    fun mul_div_u256(a: u256, b: u256, denom: u256): u256 {
        (a * b) / denom
    }

    // ------------------------------------------------------------------------
    // Public constructor functions for testing
    // ------------------------------------------------------------------------
    
    public fun create_position_leg(
        option_type: OptionType,
        side: Side,
        amount: u256,
        strike_price: u256,
        expiration: u64
    ): PositionLeg {
        PositionLeg {
            option_type,
            side,
            amount,
            strike_price,
            expiration
        }
    }
    
    public fun create_position(
        id: u64,
        asset_symbol: String,
        legs: vector<PositionLeg>
    ): Position {
        Position {
            id,
            asset_symbol,
            legs,
            trader_address: @0x00000000000000000000000000000000,
            status: OrderStatus::OPEN,
            opening_quote: Quote {
                net_debit: 0,   
                net_credit: 0,
                initial_margin: 0,  
                maintenance_margin: 0,
                timestamp: 0,
                volatility: 0,
                underlying_price: 0,
                risk_free_rate: 0
            },
            closing_quote: Quote {
                net_debit: 0,   
                net_credit: 0,
                initial_margin: 0,  
                maintenance_margin: 0,
                timestamp: 0,
                volatility: 0,
                underlying_price: 0,
                risk_free_rate: 0
            }
        }
    }
    
    public fun create_call(): OptionType { OptionType::CALL }
    public fun create_put(): OptionType { OptionType::PUT }
    public fun create_long(): Side { Side::LONG }
    public fun create_short(): Side { Side::SHORT }
    
    // Quote accessor functions
    public fun get_net_debit(quote: &Quote): u256 { quote.net_debit }
    public fun get_net_credit(quote: &Quote): u256 { quote.net_credit }
    public fun get_initial_margin(quote: &Quote): u256 { quote.initial_margin }
    public fun get_maintenance_margin(quote: &Quote): u256 { quote.maintenance_margin }
    public fun get_volatility(quote: &Quote) : u256 { quote.volatility }
    public fun get_underlying_price(quote: &Quote) : u256 { quote.underlying_price }
    public fun get_risk_free_rate(quote: &Quote) : u256 { quote.risk_free_rate }
}
}