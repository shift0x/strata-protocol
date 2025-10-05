import { addresses } from "./addresses";
import aptos from "./chain";
import { getPriceUpdate } from "./pyth";
import { formatDecimals, parseDecimals } from "./utils";

export const openOptionPosition = async (
    asset_symbol,               // the symbol for the position
    leg_option_types,           // list of option types for each leg in the position call=0, put=1
    leg_option_sides,           // list of option sides for each leg in the position long=0, short=1,
    leg_option_amounts,         // list of all option amounts for each leg in the position,
    leg_option_strike_prices,   // list of all option strike prices for each leg in the position,
    leg_option_expirations,     // list of all option expirations for each leg in the position (timestamp seconds)
) => {
    const underlyingPriceUpdate = await getPriceUpdate(asset_symbol);
    const riskFreeRatePriceUpdate = await getPriceUpdate("Rates.US10Y");

    const leg_option_amounts_big = leg_option_amounts.map(amount => {
        // amounts are 18 decimals
        return formatDecimals(amount, 18);
    });

    const leg_option_strike_prices_big = leg_option_strike_prices.map(strike_price => {
        // strike prices are 18 decimals
        return formatDecimals(strike_price, 18);
    });

    const transaction = {
        data : {
            function: `${addresses.code}::options_exchange::update_price_feed_and_open_position`,
            functionArguments: [
                underlyingPriceUpdate,
                riskFreeRatePriceUpdate,
                addresses.marketplace, 
                addresses.options_exchange, 
                asset_symbol,
                leg_option_types,
                leg_option_sides,
                leg_option_amounts_big,
                leg_option_strike_prices_big,
                leg_option_expirations
            ]
        }
    }

    return transaction;

}

export const closeOptionPosition = async(
    positionId  // the id of the position to close
) => {
    const transaction = {
        data : {
            function: `${addresses.code}::options_exchange::close_position`,
            functionArguments: [
                addresses.marketplace, 
                addresses.options_exchange, 
                positionId
            ]
        }
    }

    return transaction;
}

export const getUserPositions = async(
    userAddress // the address of the current logged in user
) => {
    const request = {
        function: `${addresses.code}::options_exchange::get_user_positions`,
        typeArguments: [],           
        functionArguments: [
            addresses.options_exchange, 
            userAddress
        ],
    }

    const result = await aptos.view({ payload: request });
    const positions = result[0].map(position => {
        const id = position.id;
        const symbol = position.asset_symbol;
        const closingQuote = formatQuote(position.closing_quote);
        const openingQuote = formatQuote(position.opening_quote);
        const status = position.status["__variant__"];
        const legs = position.legs.map(leg => { return formatLeg(leg)});

        return {
            id,
            symbol,
            closingQuote,
            openingQuote,
            status,
            legs
        }
    });

    return positions;
 
}

const formatLeg = (leg) => {
    return {
        amount: parseDecimals(leg.amount, 18),
        expiration: new Date(Number(leg.expiration)*1000),
        type: leg.option_type["__variant__"],
        side: leg.side["__variant__"],
        strikePrice: parseDecimals(leg.strike_price, 18)
    }
}

const formatQuote = (quote) => {
    return {
        initialMargin: parseDecimals(quote.initial_margin, 18),
        maintenanceMargin: parseDecimals(quote.maintenance_margin, 18),
        netCredit: parseDecimals(quote.net_credit, 18),
        netDebit:parseDecimals(quote.net_debit, 18),
        riskFreeRate: parseDecimals(quote.risk_free_rate, 18),
        timestamp: new Date(Number(quote.timestamp) * 1000),
        underlyingPrice: parseDecimals(quote.underlying_price, 18),
        volatility: parseDecimals(quote.volatility, 18)
    }
}