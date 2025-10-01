import React, { createContext, useContext, useState, useMemo } from 'react';

const VolatilityMarketContext = createContext();

export const useVolatilityMarket = () => {
  const context = useContext(VolatilityMarketContext);
  if (!context) {
    throw new Error('useVolatilityMarket must be used within a VolatilityMarketProvider');
  }
  return context;
};

export const VolatilityMarketProvider = ({ children }) => {
  const [selectedMarket, setSelectedMarket] = useState('APT-USD (30d)');
  const [userPositions, setUserPositions] = useState({
    open: [],
    closed: []
  });
  
  // Available markets with their data
  const markets = [
    {
      id: 'APT-USD',
      name: 'APT-USD (30d)',
      pair: 'APT-USD',
      period: '30d',
      expirationDate: new Date('2025-10-15T13:30:00Z'), // 15 days from now
    },
    {
      id: 'BTC-USD',
      name: 'BTC-USD (30d)',
      pair: 'BTC-USD',
      period: '30d',
      expirationDate: new Date('2025-10-12T10:17:42Z'), // 12 days from now
    },
    {
      id: 'ETH-USD',
      name: 'ETH-USD (30d)',
      pair: 'ETH-USD',
      period: '30d',
      expirationDate: new Date('2025-10-18T16:45:00Z'), // 18 days from now
    },
    {
      id: 'SOL-USD',
      name: 'SOL-USD (30d)',
      pair: 'SOL-USD',
      period: '30d',
      expirationDate: new Date('2025-10-20T09:20:30Z'), // 20 days from now
    }
  ];

  // Get current market data
  const currentMarket = markets.find(market => market.name === selectedMarket) || markets[1]; // Default to BTC-USD

  // Calculate time to settlement
  const [timeToSettlement, setTimeToSettlement] = useState({
    days: 0,
    hours: 0,
    minutes: 0,
    seconds: 0
  });

  const calculateTimeToSettlement = (expirationDate) => {
    const now = new Date();
    const timeDiff = expirationDate.getTime() - now.getTime();
    
    if (timeDiff <= 0) {
      return { days: 0, hours: 0, minutes: 0, seconds: 0 };
    }

    const days = Math.floor(timeDiff / (1000 * 60 * 60 * 24));
    const hours = Math.floor((timeDiff % (1000 * 60 * 60 * 24)) / (1000 * 60 * 60));
    const minutes = Math.floor((timeDiff % (1000 * 60 * 60)) / (1000 * 60));
    const seconds = Math.floor((timeDiff % (1000 * 60)) / 1000);

    return { days, hours, minutes, seconds };
  };

  

  const formatTime = (time) => {
    const { days, hours, minutes, seconds } = time;
    return `${days}d ${String(hours).padStart(2, '0')}:${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`;
  };

  // Mock data for user positions - in a real app this would come from an API
  const mockUserPositions = {
    'APT-USD (30d)': {
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
          market: 'APT-USD (30d)'
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
          market: 'APT-USD (30d)'
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
          market: 'APT-USD (30d)'
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
          market: 'APT-USD (30d)'
        }
      ]
    },
    'BTC-USD (30d)': {
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
          market: 'BTC-USD (30d)'
        }
      ],
      closed: []
    },
    'ETH-USD (30d)': {
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
          market: 'ETH-USD (30d)'
        }
      ]
    },
    'SOL-USD (30d)': {
      open: [],
      closed: []
    }
  };

  // Get user positions for the selected market
  const getUserPositions = (marketName = selectedMarket) => {
    return mockUserPositions[marketName] || { open: [], closed: [] };
  };

  // Get open positions for the selected market
  const getOpenPositions = (marketName = selectedMarket) => {
    return getUserPositions(marketName).open;
  };

  // Get closed positions for the selected market
  const getClosedPositions = (marketName = selectedMarket) => {
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
  const getMarketPnL = (marketName = selectedMarket) => {
    const positions = getUserPositions(marketName);
    const totalPnL = [...positions.open, ...positions.closed].reduce((sum, position) => sum + position.pnl, 0);
    return totalPnL;
  };

  // Close a position
  const closePosition = (positionId) => {
    // In a real app, this would make an API call
    // For now, we'll just move the position from open to closed
    const currentMarketPositions = getUserPositions();
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

  // Calculate swap output and fees for USDC input
  const calculateSwapOutput = (usdcAmount, tradeType = 'BUY') => {
    // Parse the numeric value from formatted currency
    const numericAmount = parseFloat(usdcAmount.replace(/[^\d.]/g, ''));
    
    if (!numericAmount || numericAmount <= 0) {
      return {
        outputAmount: 0,
        outputTokens: 0,
        feeAmount: 0,
        feePercentage: 0,
        pricePerToken: 0
      };
    }

    // Mock pricing logic - in a real app this would use actual market data
    const basePrice = tradeType === 'BUY' ? 1.047 : 0.953; // Different prices for buy/sell
    const feePercentage = 1; // 1% fee
    
    // Calculate fee
    const feeAmount = numericAmount * (feePercentage / 100);
    const amountAfterFees = numericAmount - feeAmount;
    
    // Calculate output tokens
    const outputTokens = Math.floor(amountAfterFees / basePrice);
    const outputAmount = outputTokens * basePrice;
    
    return {
      outputAmount: outputAmount,
      outputTokens: outputTokens,
      feeAmount: feeAmount,
      feePercentage: feePercentage,
      pricePerToken: basePrice,
      slippage: 0.1 // Mock slippage
    };
  };

  // Get current market price for IV tokens
  const getCurrentIVPrice = (marketName = selectedMarket) => {
    // Mock prices by market - in real app this would come from price feeds
    const marketPrices = {
      'APT-USD (30d)': 1.047,
      'BTC-USD (30d)': 1.125,
      'ETH-USD (30d)': 0.985,
      'SOL-USD (30d)': 1.200
    };
    
    return marketPrices[marketName] || 1.000;
  };

  // Get current market data including IV price and change
  const getCurrentMarketData = (marketName = selectedMarket) => {
    // Mock market data - in real app this would come from market data APIs
    const marketData = {
      'APT-USD (30d)': {
        currentIV: 47.3,
        dailyChange: 2.1,
        markIV: 47.3,
        historicalVol: 42.8,
        tokenPrice: 1.047
      },
      'BTC-USD (30d)': {
        currentIV: 52.8,
        dailyChange: -1.4,
        markIV: 52.8,
        historicalVol: 55.2,
        tokenPrice: 1.125
      },
      'ETH-USD (30d)': {
        currentIV: 38.9,
        dailyChange: 3.7,
        markIV: 38.9,
        historicalVol: 35.1,
        tokenPrice: 0.985
      },
      'SOL-USD (30d)': {
        currentIV: 61.2,
        dailyChange: 0.8,
        markIV: 61.2,
        historicalVol: 58.7,
        tokenPrice: 1.200
      }
    };
    
    return marketData[marketName] || {
      currentIV: 45.0,
      dailyChange: 0.0,
      markIV: 45.0,
      historicalVol: 45.0,
      tokenPrice: 1.000
    };
  };

  const value = {
    markets,
    selectedMarket,
    setSelectedMarket,
    currentMarket,
    timeToSettlement,
    formatTime,
    formattedTimeToSettlement: formatTime(timeToSettlement),
    calculateTimeToSettlement,
    // Position methods
    getUserPositions,
    getOpenPositions,
    getClosedPositions,
    getAllUserPositions,
    getMarketPnL,
    closePosition,
    calculateSwapOutput,
    getCurrentIVPrice,
    getCurrentMarketData
  };

  return (
    <VolatilityMarketContext.Provider value={value}>
      {children}
    </VolatilityMarketContext.Provider>
  );
};
