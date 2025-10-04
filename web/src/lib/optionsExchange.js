import { addresses } from "./addresses";
import aptos from "./chain";

export const openOptionPosition = async (
    asset_symbol,               // the symbol for the position
    leg_option_types,           // list of option types for each leg in the position call=0, put=1
    leg_option_sides,           // list of option sides for each leg in the position long=0, short=1,
    leg_option_amounts,         // list of all option amounts for each leg in the position,
    leg_option_strike_prices,   // list of all option strike prices for each leg in the position,
    leg_option_expirations,     // list of all option expirations for each leg in the position (timestamp seconds)
) => {
    const leg_option_amounts_big = leg_option_amounts.map(amount => {
        return (amount * Math.pow(10, 6)).toString();
    });

    const leg_option_strike_prices_big = leg_option_strike_prices.map(strike_price => {
        return (strike_price * Math.pow(10, 6)).toString();
    });

    const transaction = {
        data : {
            function: `${addresses.code}::options_exchange::open_position`,
            functionArguments: [
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

    console.log({request})

    const result = await aptos.view({ payload: request });

    console.log(result);

    return result[0];
}