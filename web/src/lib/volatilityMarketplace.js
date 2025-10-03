import aptos from "./chain"
import { addresses } from "./addresses"

const marketSymbolMap = {
    'APT-USD': 'BINANCE:APTUSDT',
    'BTC-USD': 'BINANCE:BTCUSDT',
    'ETH-USD': 'BINANCE:ETHUSDT',
    'SOL-USD': 'BINANCE:SOLUSDT'
}

const getOpenMarkets = async() => {
    const symbols = ["BTC-USD", "ETH-USD", "APT-USD"]
    const request = {
        function: `${addresses.code}::volatility_marketplace::get_active_markets`,
        typeArguments: [],           
        functionArguments: [addresses.marketplace, symbols],
    }
    
    const result = await aptos.view({ payload: request});
    
    return result[0];
}

export const getMarkets = async () => {
  try {
    const marketData = await getOpenMarkets();
    
    // Transform blockchain data to component format
    const transformedMarkets = marketData.map(market => {
      const expirationDate = new Date(market.expiration * 1000);
      const formattedExpiration = expirationDate.toLocaleDateString('en-US', { 
        month: 'short', 
        day: 'numeric' 
      });
      
      return {
        id: market.symbol,
        name: `${market.symbol} (${formattedExpiration})`,
        pair: market.symbol,
        expirationDate: expirationDate,
        marketAddress: market.market_address,
        ivTokenAddress: market.iv_token_address,
        chartSymbol: marketSymbolMap[market.symbol]
      };
    });
    
    return transformedMarkets;
  } catch (error) {
    console.error('Failed to load markets:', error);
    return [];
  } 
};

export const getUserPosition = async (market, user) => {
    console.log({market, user})
    const request = {
        function: `${addresses.code}::implied_volatility_market::get_user_position`,
        typeArguments: [],           
        functionArguments: [market, user],
    }

    const result = await aptos.view({ payload: request });

    console.log(result);

    return result[0];
}