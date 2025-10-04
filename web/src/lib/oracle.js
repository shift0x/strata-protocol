import { addresses } from "./addresses";
import aptos from "./chain";

export const getAssetPrice = async(symbol) => {
    const request = {
        function: `${addresses.code}::price_oracle::get_price`,
        typeArguments: [],           
        functionArguments: [addresses.price_oracle, symbol],
    }

    const result = await aptos.view({ payload: request });

    return result;
}
