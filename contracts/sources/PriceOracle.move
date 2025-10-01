address marketplace {
module price_oracle {
    use std::debug;
    use std::timestamp;
    use std::string;
    use std::signer;
    use std::table::{Self, Table};
    use pyth::pyth;
    use pyth::i64;
    use pyth::price::{Self, Price};
    use pyth::price_identifier;

    // Error codes
    const E_ONLY_OWNER: u64 = 1;

    struct PriceOracle has key {
        // owner address
        owner: address,
        // mapping from asset symbol to pyth market id
        pyth_price_identifier_lookup: Table<string::String, vector<u8>>,
        // mapping from asset to mock price
        asset_mock_price_lookup: Table<string::String, u256>
    }

    public fun create(
        owner: &signer
    ) : address {
        let owner_address = signer::address_of(owner);

        let oracle = PriceOracle {
            owner: owner_address,
            pyth_price_identifier_lookup: table::new(),
            asset_mock_price_lookup: table::new()
        };

        move_to(owner, oracle);

        owner_address
    }

    // used for testing to set the price of a given asset
    public fun set_mock_price(
        sender: &signer,
        oracle_address: address,
        asset_symbol: string::String,
        mock_price: u256
    ) acquires PriceOracle {
        let oracle = borrow_global_mut<PriceOracle>(oracle_address);
        let sender_address = signer::address_of(sender);

        assert!(sender_address == oracle.owner, E_ONLY_OWNER);
        
        // remove the price if it already exists
        if(table::contains(&oracle.asset_mock_price_lookup, asset_symbol)) {
            table::remove(&mut oracle.asset_mock_price_lookup, asset_symbol);
        };
        
        table::add(&mut oracle.asset_mock_price_lookup, asset_symbol, mock_price);
    }

    // use the pyth price identifier to get the price of an asset
    // if a mock price exists, then return that instead
    public fun get_price(
        marketplace_address: address,
        asset_symbol: string::String
    ) : u256 acquires PriceOracle {
        let oracle = borrow_global<PriceOracle>(marketplace_address);

        // If there is a mock price stored, then return that
        if(table::contains(&oracle.asset_mock_price_lookup, asset_symbol)) {
            *table::borrow(&oracle.asset_mock_price_lookup, asset_symbol)
        } else {
            // Get the price identifier for the asset
            let price_identifier = table::borrow(&oracle.pyth_price_identifier_lookup, asset_symbol);

            // Read the current price from a price feed.
            // Note: Aptos uses the Pyth price feed ID without the `0x` prefix.
            let price_id = price_identifier::from_byte_vec(*price_identifier);
            
            let pyth_price = pyth::get_price(price_id);

            let i64_price = price::get_price(&pyth_price);

            i64::get_magnitude_if_positive(&i64_price) as u256
        }
    }
}
}