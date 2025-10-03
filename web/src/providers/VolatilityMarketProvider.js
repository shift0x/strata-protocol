import { createContext, useContext, useState, useEffect, useMemo } from 'react';

const VolatilityMarketContext = createContext();

export const useVolatilityMarket = () => {
  const context = useContext(VolatilityMarketContext);
  if (!context) {
    throw new Error('useVolatilityMarket must be used within a VolatilityMarketProvider');
  }
  return context;
};




export const VolatilityMarketProvider = ({ children }) => {

  // Calculate time to settlement
  const [timeToSettlement, setTimeToSettlement] = useState({
    days: 0,
    hours: 0,
    minutes: 0,
    seconds: 0
  });

 

  



  // Mock data for user positions - in a real app this would come from an API
  const mockUserPositions = {
    'APT-USD': {
      open: [
        {
          id: 1,
          type: 'LONG',
          size: 1250,
          entryPrice: 45.2,
          currentPrice: 47.3,
          pnl: 127.50,
          pnlPercentage: 4.6,
          timestamp: '2024-03-15 10:30',
          market: 'APT-USD'
        },
        {
          id: 2,
          type: 'SHORT',
          size: 800,
          entryPrice: 49.1,
          currentPrice: 47.3,
          pnl: -42.80,
          pnlPercentage: -2.1,
          timestamp: '2024-03-14 14:20',
          market: 'APT-USD'
        }
      ],
      closed: [
        {
          id: 3,
          type: 'LONG',
          size: 500,
          entryPrice: 42.8,
          exitPrice: 46.1,
          pnl: 82.50,
          pnlPercentage: 7.7,
          timestamp: '2024-03-12 09:15',
          closedAt: '2024-03-13 16:45',
          market: 'APT-USD'
        },
        {
          id: 4,
          type: 'SHORT',
          size: 1100,
          entryPrice: 48.5,
          exitPrice: 50.2,
          pnl: -93.50,
          pnlPercentage: -3.5,
          timestamp: '2024-03-10 11:20',
          closedAt: '2024-03-11 13:30',
          market: 'APT-USD'
        }
      ]
    },
    'BTC-USD': {
      open: [
        {
          id: 5,
          type: 'LONG',
          size: 2000,
          entryPrice: 52.1,
          currentPrice: 54.8,
          pnl: 270.00,
          pnlPercentage: 5.2,
          timestamp: '2024-03-16 08:45',
          market: 'BTC-USD'
        }
      ],
      closed: []
    },
    'ETH-USD': {
      open: [],
      closed: [
        {
          id: 6,
          type: 'SHORT',
          size: 1500,
          entryPrice: 48.9,
          exitPrice: 45.2,
          pnl: 277.50,
          pnlPercentage: 7.6,
          timestamp: '2024-03-08 15:30',
          closedAt: '2024-03-09 11:15',
          market: 'ETH-USD'
        }
      ]
    },
    'SOL-USD': {
      open: [],
      closed: []
    }
  };

  // Get user positions for a market
  const getUserPositions = (marketName) => {
    if (!marketName) return { open: [], closed: [] };
    // Extract pair from market name (e.g., "APT-USD (Oct 15)" -> "APT-USD")
    const pair = marketName.split(' ')[0] || '';
    return mockUserPositions[pair] || { open: [], closed: [] };
  };

  // Get open positions for a market
  const getOpenPositions = (marketName) => {
    return getUserPositions(marketName).open;
  };

  // Get closed positions for a market
  const getClosedPositions = (marketName) => {
    return getUserPositions(marketName).closed;
  };

  // Get all user positions across all markets
  const getAllUserPositions = () => {
    const allPositions = { open: [], closed: [] };
    Object.values(mockUserPositions).forEach(marketPositions => {
      allPositions.open.push(...marketPositions.open);
      allPositions.closed.push(...marketPositions.closed);
    });
    return allPositions;
  };

  // Calculate total P&L for a market
  const getMarketPnL = (marketName) => {
    if (!marketName) return 0;
    const positions = getUserPositions(marketName);
    const totalPnL = [...positions.open, ...positions.closed].reduce((sum, position) => sum + position.pnl, 0);
    return totalPnL;
  };

  // Close a position
  const closePosition = (positionId, marketName) => {
    // In a real app, this would make an API call
    // For now, we'll just move the position from open to closed
    if (!marketName) return null;
    const currentMarketPositions = getUserPositions(marketName);
    const positionToClose = currentMarketPositions.open.find(pos => pos.id === positionId);
    
    if (positionToClose) {
      // Create closed position with exit data
      const closedPosition = {
        ...positionToClose,
        exitPrice: positionToClose.currentPrice,
        closedAt: new Date().toISOString().slice(0, 16).replace('T', ' ')
      };
      delete closedPosition.currentPrice;
      
      // Update mock data (in real app, this would be handled by state management)
      console.log(`Closing position ${positionId}:`, closedPosition);
      
      // This is a simplified version - in a real app you'd update the actual state
      return closedPosition;
    }
    
    return null;
  };



  // Get current market price for IV tokens
  const getCurrentIVPrice = (marketName) => {
    if (!marketName) return 1.000;
    // Mock prices by market - in real app this would come from price feeds
    const pair = marketName.split(' ')[0] || '';
    const marketPrices = {
      'APT-USD': 1.047,
      'BTC-USD': 1.125,
      'ETH-USD': 0.985,
      'SOL-USD': 1.200
    };
    
    return marketPrices[pair] || 1.000;
  };

  // Get current market data including IV price and change
  const getCurrentMarketData = (marketName) => {
    if (!marketName) {
      return {
        currentIV: 45.0,
        dailyChange: 0.0,
        markIV: 45.0,
        historicalVol: 45.0,
        tokenPrice: 1.000
      };
    }
    
    // Mock market data - in real app this would come from market data APIs
    const pair = marketName.split(' ')[0] || '';
    const marketData = {
      'APT-USD': {
        currentIV: 47.3,
        dailyChange: 2.1,
        markIV: 47.3,
        historicalVol: 42.8,
        tokenPrice: 1.047
      },
      'BTC-USD': {
        currentIV: 52.8,
        dailyChange: -1.4,
        markIV: 52.8,
        historicalVol: 55.2,
        tokenPrice: 1.125
      },
      'ETH-USD': {
        currentIV: 38.9,
        dailyChange: 3.7,
        markIV: 38.9,
        historicalVol: 35.1,
        tokenPrice: 0.985
      },
      'SOL-USD': {
        currentIV: 61.2,
        dailyChange: 0.8,
        markIV: 61.2,
        historicalVol: 58.7,
        tokenPrice: 1.200
      }
    };
    
    return marketData[pair] || {
      currentIV: 45.0,
      dailyChange: 0.0,
      markIV: 45.0,
      historicalVol: 45.0,
      tokenPrice: 1.000
    };
  };

  const value = {
    // Position methods
    getUserPositions,
    getOpenPositions,
    getClosedPositions,
    getAllUserPositions,
    getMarketPnL,
    closePosition,

    getCurrentIVPrice,
    getCurrentMarketData
  };

  return (
    <VolatilityMarketContext.Provider value={value}>
      {children}
    </VolatilityMarketContext.Provider>
  );
};
