import aptos from "./chain"
import { addresses } from "./addresses"
import { getAddressTokenBalance } from "./assets"

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

export const getMarketPrice = async(market) => {
    const request = {
        function: `${addresses.code}::implied_volatility_market::get_quote`,
        typeArguments: [],           
        functionArguments: [market],
    }

    const result = await aptos.view({ payload: request });
    const formattedValue = parseDecimals(result[0], 6);
    
    return formattedValue.toFixed(2);
}

export const getUserPosition = async (market, user) => {
    const request = {
        function: `${addresses.code}::implied_volatility_market::get_user_position`,
        typeArguments: [],           
        functionArguments: [market, user],
    }

    const result = await aptos.view({ payload: request });

    const data = {
        long: parseDecimals(result[0].long_amount, 6),
        short: parseDecimals(result[0].short_amount, 6)
    }

    return data;
}

export const getAmountOut = async (market, amountIn) => {
    let amountInBig = (amountIn * Math.pow(10, 6)).toString();

    const request = {
        function: `${addresses.code}::implied_volatility_market::get_swap_amount_out`,
        typeArguments: [],           
        functionArguments: [market, 0, amountInBig],
    }

    const result = await aptos.view({ payload: request });

    const amountOut = parseDecimals(result[0], 6);
    const feeAmount = parseDecimals(result[1], 6);

    return {
        outputTokens: amountOut,
        feeAmount: feeAmount,
        feePercentage: 1
    };
}

export const buildCloseLongPositionTransaction = async(userAddress, marketAddress, ivTokenAddress) => {
    const ivTokenBalance = await getAddressTokenBalance(userAddress, ivTokenAddress);
    
    return buildSwapTransaction(marketAddress, 1, ivTokenBalance);
}

export const buildSwapTransaction = async (marketAddress, swapType, amountIn) => {
    let amountInBig = (amountIn * Math.pow(10, 6)).toString();

    const transaction = {
        data: {
            function: `${addresses.code}::implied_volatility_market::swap`,
            functionArguments: [marketAddress, swapType, amountInBig],
        }
    }

    return transaction;
}

export const buildOpenShortTransaction = async (marketAddress, collateralAmount) => {
    let collateralAmountBig = (collateralAmount * Math.pow(10, 6)).toString();

    const transaction = {
        data : {
            function: `${addresses.code}::implied_volatility_market::open_short_position`,
            functionArguments: [marketAddress, collateralAmountBig]
        }
    }

    return transaction;
}

export const buildCloseShortTransaction = async (marketAddress) => {
    const transaction = {
        data : {
            function: `${addresses.code}::implied_volatility_market::close_short_position`,
            functionArguments: [marketAddress]
        }
    }

    return transaction;
}

export const mintTestUSDCTransaction = async (userAddress) => {
    const amount = 100000
    const amountBig = (amount * Math.pow(10, 6)).toString();

    const transaction = {
        data : {
            function: `${addresses.code}::volatility_marketplace::mint_test_usdc`,
            functionArguments: [amountBig, userAddress, addresses.marketplace]
        }
    }

    return transaction;
}

const parseDecimals = (amount, decimals) => {
    const floatValue = parseFloat(amount);
    const formattedValue = floatValue / Math.pow(10, decimals);

    return formattedValue;
}
