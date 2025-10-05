import { parseDecimals } from "./utils";

var priceFeeds = [];

const initPriceFeeds = async() => {
    const url = 'https://hermes.pyth.network/v2/price_feeds';
    
    try {
        const response = await fetch(url);
        const data = await response.json();
        priceFeeds = data.map(feedItem => {
            return {
                id: feedItem.id,
                ...feedItem.attributes
            }
        });

        return priceFeeds;
    } catch (error) {
        console.error('Failed to fetch price feeds:', error);
        throw error;
    }
}

const getPriceData = async(symbol) => {
    if(priceFeeds.length == 0){
        await initPriceFeeds();
    }
    
    const formattedSymbol = symbol.replace("-", "");
    const feed = priceFeeds.find(x => { return x.generic_symbol == formattedSymbol || x.symbol == symbol})
    
    if(!feed)
        throw `feed item not found for symbol ${symbol}`

    const url = `https://hermes.pyth.network/v2/updates/price/latest?ids[]=${feed.id}&parsed=true`

    try {
        const response = await fetch(url);
        const data = await response.json();

        return data;
    } catch(err) {
        console.error('Failed to fetch price:', err);

        throw err;
    }
}

export const getPriceUpdate = async(symbol) => {
    const data = await getPriceData(symbol);
    
    return data.binary.data;
}

export const getAssetPrice = async(symbol) => {
    const data = await getPriceData(symbol);
    const priceData = data.parsed[0].price;
    const price = priceData.price;
    const exponent = Math.abs(priceData.expo);
    const priceAsFloat = parseDecimals(price, exponent);

    return priceAsFloat;
}
