script {
    use std::string;
    use std::signer;
    use std::debug;
    use std::timestamp;
    use marketplace::volatility_marketplace::{Self};
    use marketplace::options_exchange::{Self};
    use marketplace::staking_vault::{Self};
    use marketplace::price_oracle::{Self};

    const ONE_E6 : u64 = 1000000;
    const ONE_E18 : u256 = 1000000000000000000;

    fun main(
        sender: &signer
    ) {
        let sender_address = signer::address_of(sender);

        // create the volatility marketplace
        let marketplace_address = volatility_marketplace::create_marketplace(sender);
        let usdc_address = volatility_marketplace::get_usdc_address(marketplace_address);

        // create the option exchange
        let (option_exchange_address, oracle_address) = options_exchange::create_exchange(sender, usdc_address);

        // register price feeds with the oracle
        let pyth_rates_us10y_identifier = x"e13490529898ba044274027323a175105d89bc43c2474315c76a051ba02d76f8";
        let pyth_btcusdc_identifier = x"f9c0172ba10dfa4d19088d94f5bf61d3b54d5bd7483a322a982e1373ee8ea31b";
        let pyth_aptusdc_identifier = x"44a93dddd8effa54ea51076c4e851b6cbbfd938e82eb90197de38fe8876bb66e";
        let pyth_ethusdc_identifier = x"ca80ba6dc32e08d06f1aa886011eed1d77c77be9eb761cc10d72b7d0a2fd57a6";
        
        // risk free interest rate
        price_oracle::store_price_identifier(
            sender,
            option_exchange_address,
            string::utf8(b"Rates.US10Y"),
            pyth_rates_us10y_identifier
        );

        // BTC
        price_oracle::store_price_identifier(
            sender,
            option_exchange_address,
            string::utf8(b"BTC-USD"),
            pyth_btcusdc_identifier
        );

        // ETH
        price_oracle::store_price_identifier(
            sender,
            option_exchange_address,
            string::utf8(b"ETH-USD"),
            pyth_ethusdc_identifier
        );

        // APT
        price_oracle::store_price_identifier(
            sender,
            option_exchange_address,
            string::utf8(b"APT-USD"),
            pyth_aptusdc_identifier
        );

        // mint test usdc from the marketplace to the sender
        let staking_amount = 1000000 * ONE_E6;  // 1,000,000
        let trading_amount = 50000 * ONE_E6;    // 50,000
        let total_mint_amount = staking_amount + trading_amount;

        volatility_marketplace::mint_test_usdc(total_mint_amount, sender_address, marketplace_address);

        // stake test usdc into the vault
        let vault_address = volatility_marketplace::get_staking_vault_address(marketplace_address);

        staking_vault::stake(sender, vault_address, staking_amount);

        // create markets for each supported asset
        let expiration_timestamp = timestamp::now_seconds() + (86400*60); // 60 days from now

        volatility_marketplace::create_market(
            sender,
            string::utf8(b"BTC-USD"),
            30 * ONE_E18,
            expiration_timestamp,
            marketplace_address
        );

        volatility_marketplace::create_market(
            sender,
            string::utf8(b"ETH-USD"),
            55 * ONE_E18,
            expiration_timestamp,
            marketplace_address
        );

        volatility_marketplace::create_market(
            sender,
            string::utf8(b"APT-USD"),
            75 * ONE_E18,
            expiration_timestamp,
            marketplace_address
        );


    }
}
