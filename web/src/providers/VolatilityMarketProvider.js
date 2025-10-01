import React, { createContext, useContext, useState, useEffect } from 'react';

const VolatilityMarketContext = createContext();

export const useVolatilityMarket = () => {
  const context = useContext(VolatilityMarketContext);
  if (!context) {
    throw new Error('useVolatilityMarket must be used within a VolatilityMarketProvider');
  }
  return context;
};

export const VolatilityMarketProvider = ({ children }) => {
  const [selectedMarket, setSelectedMarket] = useState('BTC-USD (30d)');
  
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

  // Update countdown timer
  useEffect(() => {
    const updateTimer = () => {
      setTimeToSettlement(calculateTimeToSettlement(currentMarket.expirationDate));
    };

    // Initial calculation
    updateTimer();

    // Update every second
    const timer = setInterval(updateTimer, 1000);

    return () => clearInterval(timer);
  }, [currentMarket.expirationDate]);

  const formatTime = (time) => {
    const { days, hours, minutes, seconds } = time;
    return `${days}d ${String(hours).padStart(2, '0')}:${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`;
  };

  const value = {
    markets,
    selectedMarket,
    setSelectedMarket,
    currentMarket,
    timeToSettlement,
    formatTime,
    formattedTimeToSettlement: formatTime(timeToSettlement)
  };

  return (
    <VolatilityMarketContext.Provider value={value}>
      {children}
    </VolatilityMarketContext.Provider>
  );
};
