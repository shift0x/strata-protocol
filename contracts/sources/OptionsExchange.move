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
    use marketplace::binomial_option_pricing;
    use marketplace::isolated_margin_account;
    use marketplace::price_oracle;
    use marketplace::volatility_marketplace;
    use marketplace::staking_vault;

    // ------------------------------------------------------------------------
    // Constants and errors
    // ------------------------------------------------------------------------

    const E_U64_OVERFLOW: u64 = 1;
    const E_POSITION_EMPTY: u64 = 2;
    const E_POSITION_NOT_FOUND: u64 = 3;
    const E_POSITION_CLOSED: u64 = 4;
    const E_UNAUTHORIZED: u64 = 5;
    const E_POSITION_NOT_OPEN: u64 = 6;

    // 1e18 fixed-point scaling used by the pricing model
    const ONE_E18: u256 = 1000000000000000000u256;
    const ONE_E12: u256 = 1000000000000u256;

    // Basis points to 1e18 fixed-point: 1 bp = 1e-4 => 1e14 in 1e18 fp
    const ONE_BP_IN_FP: u256 = 100000000000000u256; // 1e14

    // Time constants
    const SECONDS_PER_DAY: u64 = 86400;

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
        timestamp: u64
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
    }

    public fun create_exchange(
        owner: &signer,
        usdc_address: address
    ) : address {
        let exchange = OptionsExchange { 
            user_positions: vector::empty<Position>(),
            user_position_lookup: table::new<address, vector<u64>>(),
            user_margin_accounts: table::new<address, address>(),
            position_counter: 0,
            usdc_address,
        };

        move_to<OptionsExchange>(owner, exchange);

        // create the price oracle
        price_oracle::create(owner);

        signer::address_of(owner)
    }

    public fun close_position(
        user: &signer,
        marketplace_address: address,
        exchange_address: address,
        position_id: u64
    ) acquires OptionsExchange {
        let exchange = borrow_global_mut<OptionsExchange>(exchange_address);
        let user_addr = signer::address_of(user);

        // ensure the position exists
        assert!(position_id < exchange.position_counter, E_POSITION_NOT_FOUND);

        let position = exchange.user_positions[position_id];

        // ensure the position is open
        assert!(position.status == OrderStatus::OPEN, E_POSITION_NOT_OPEN);

        // ensure the position is owned by the user
        assert!(position.trader_address == user_addr, E_UNAUTHORIZED);

        // close the position
        execute_close_position(user, exchange, &mut position, marketplace_address);
    }


    public fun open_position(
        user: &signer,
        marketplace_address: address,
        exchange_address: address,
        position: Position
    ) acquires OptionsExchange {
        let exchange = borrow_global_mut<OptionsExchange>(exchange_address);
        let user_addr = signer::address_of(user);

        // ensure the user exists
        ensure_user_created(user_addr, exchange);

        // create the user position
        position.id = exchange.position_counter;
        position.trader_address = user_addr;

        vector::push_back(&mut exchange.user_positions, position);

        let user_positions_ref = table::borrow_mut<address, vector<u64>>(&mut exchange.user_position_lookup, user_addr);
        vector::push_back(user_positions_ref, position.id);
        
        // update the position counter
        exchange.position_counter = exchange.position_counter + 1;

        // execute the trade
        execute_open_position(user, &mut position, marketplace_address, exchange);
    }

    fun get_quote_for_position(
        position: &Position,
        marketplace_address: address
    ) : Quote {
        // get the current IV from the volatility marketplace
        let volatility_bps = volatility_marketplace::get_implied_volatility(
            marketplace_address, 
            position.asset_symbol
        );

        // get the underlying price from the oracle
        let underlying_price = price_oracle::get_price(marketplace_address, position.asset_symbol);

        // get the risk free rate from the oracle
        let risk_free_rate_bps = price_oracle::get_price(marketplace_address, string::utf8(b"Rates.US10Y"));

        price_position(
            position, 
            underlying_price, 
            risk_free_rate_bps, 
            volatility_bps, 
            timestamp::now_seconds()
        )
    }

    fun execute_close_position(
        trader: &signer,
        exchange: &OptionsExchange,
        position: &mut Position,
        marketplace_address: address
    ) {
        let trader_address = signer::address_of(trader);
        
        // quote the position to determine net debit and margin amounts
        position.closing_quote = get_quote_for_position(position, marketplace_address);

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

        if(profit > 0){ // then transfer the profit amount from the vault to the margin account
            let profit_64 = (profit / ONE_E12) as u64;

            staking_vault::withdraw_from_vault(
                marketplace_address, 
                user_margin_account, 
                profit_64);

            transfer_amount_to_trader = transfer_amount_to_trader + profit;
        } else if(loss > 0){ // transfer the loss from the margin account to the vault
            if(loss > transfer_amount_to_trader){
                transfer_amount_to_trader = 0;
            } else {
                transfer_amount_to_trader = transfer_amount_to_trader - loss;
            }
        };

        if(transfer_amount_to_trader > 0){
            let transfer_amount_trader_64 = (transfer_amount_to_trader / ONE_E12) as u64;
            let margin_account_signer = isolated_margin_account::get_signer(user_margin_account);
            let usdc_metadata = object::address_to_object<Metadata>(exchange.usdc_address);
            let usdc_tokens = primary_fungible_store::withdraw(
                &margin_account_signer, 
                usdc_metadata, 
                transfer_amount_trader_64);
            
            primary_fungible_store::deposit(trader_address, usdc_tokens); 
        };
        

        // update the position status
        position.status = OrderStatus::CLOSED;
    }

    fun execute_open_position(
        user: &signer,
        position: &mut Position,
        marketplace_address: address,
        exchange: &mut OptionsExchange
    ) {
        // quote the position to determine net debit and margin amounts
        position.opening_quote = get_quote_for_position(position, marketplace_address);

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
        exchange: &mut OptionsExchange
    ) {
        if (!table::contains<address, vector<u64>>(&exchange.user_position_lookup, user_address)) {
            // create the user position list
            let empty: vector<u64> = vector::empty<u64>();
            table::add(&mut exchange.user_position_lookup, user_address, empty);

            // create the user margin account
            let margin_account = isolated_margin_account::new(user_address);
            table::add(&mut exchange.user_margin_accounts, user_address, margin_account);
        };
    }


    // ------------------------------------------------------------------------
    // Quoting (premium) and margin
    // ------------------------------------------------------------------------

    // Inputs:
    // - underlying_price: in asset's base units (same units as strike and multiplier effects)
    // - risk_free_rate_bps: annualized rate in basis points (e.g., 500 = 5.00%)
    // - volatility_bps: annualized implied vol in basis points (e.g., 2000 = 20.00%)
    // - current_time_secs: UNIX timestamp (seconds)
    public fun price_position(
        position: &Position,
        underlying_price: u256,
        risk_free_rate_bps: u256,
        volatility_bps: u256,
        current_time_secs: u64
    ): Quote {
        let legs_ref = &position.legs;
        let n = vector::length<PositionLeg>(legs_ref);
        assert!(n > 0, E_POSITION_EMPTY);

        // Accumulators in u256
        let net_debit_u256 = 0u256;
        let net_credit_u256 = 0u256;

        let i = 0;
        while (i < n) {
            let leg_ref = vector::borrow<PositionLeg>(legs_ref, i);

            let days_to_exp = if (leg_ref.expiration > current_time_secs) {
                (leg_ref.expiration - current_time_secs) / SECONDS_PER_DAY
            } else {
                0
            };

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
            timestamp: current_time_secs
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
            },
            closing_quote: Quote {
                net_debit: 0,   
                net_credit: 0,
                initial_margin: 0,  
                maintenance_margin: 0,
                timestamp: 0,
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
}
}