import React, { useState, useEffect, useRef } from 'react';
import { useVolatilityMarket } from '../providers/VolatilityMarketProvider';
import { formatCurrency, isValidCurrencyAmount, parseCurrency } from '../lib/currency';
import { getMarkets, getUserPosition, getMarketPrice, getAmountOut, buildSwapTransaction, buildOpenShortTransaction, buildCloseLongPositionTransaction, buildCloseShortTransaction, mintTestUSDCTransaction } from '../lib/volatilityMarketplace';
import { calculateTimeToSettlement, formatTime } from '../lib/time';
import { useWallet } from "@aptos-labs/wallet-adapter-react";

import './VolatilityMarket.css';

function VolatilityMarket() {
  const {
    getCurrentMarketData
  } = useVolatilityMarket();
  
  const { connected, account, signAndSubmitTransaction } = useWallet();
  const [markets, setMarkets] = useState([]);
  
  const [selectedMarket, setSelectedMarket] = useState('');
  const [isDropdownOpen, setIsDropdownOpen] = useState(false);

  const [localTimeToSettlement, setLocalTimeToSettlement] = useState(null);
  const [usdcAmount, setUsdcAmount] = useState('');
  const [isValidAmount, setIsValidAmount] = useState(true);
  const [swapOutput, setSwapOutput] = useState(null);
  const [marketPrice, setMarketPrice] = useState(null);
  const [userPosition, setUserPosition] = useState(null);
  const dropdownRef = useRef(null);
  const chartRef = useRef(null);
  const chartWidget = useRef(null);
  const timerRef = useRef(null);

  // Derive currentMarket from markets and selectedMarket
  const currentMarket = markets.find(market => market.name === selectedMarket);

  // load markets, once at load
  useEffect(() => {
    const getMarketData = async () => {
      const markets = await getMarkets();

      setMarkets(markets);
      
      // Set default selected market to first market if available
      if (markets.length > 0 && !selectedMarket) {
        setSelectedMarket(markets[0].name);
      }
    }

    getMarketData();
    
  }, [])

  // Close dropdown when clicking outside
  useEffect(() => {
    const handleClickOutside = (event) => {
      if (dropdownRef.current && !dropdownRef.current.contains(event.target)) {
        setIsDropdownOpen(false);
      }
    };

    if (isDropdownOpen) {
      document.addEventListener('mousedown', handleClickOutside);
    }

    return () => {
      document.removeEventListener('mousedown', handleClickOutside);
    };
  }, [isDropdownOpen]);

  // TradingView chart initialization
  useEffect(() => {
    const initChart = () => {
      if (window.TradingView && chartRef.current) {
        // Remove existing chart if it exists
        if (chartWidget.current) {
          chartWidget.current.remove();
        }

        // Clear the container
        if (chartRef.current) {
          chartRef.current.innerHTML = '';
        }

        // Create new chart with current market symbol
        chartWidget.current = new window.TradingView.widget({
          width: "100%",
          height: "100%",
          symbol: currentMarket?.chartSymbol || "BINANCE:BTCUSDT",
          interval: "1D",
          timezone: "ETC/UTC",
          theme: "dark",
          style: "1",
          locale: "en",
          toolbar_bg: "#1a1f2b",
          enable_publishing: false,
          allow_symbol_change: false,
          container_id: "tradingview_chart",
          autosize: true,
          studies: [
            {
              id: "MASimple@tv-basicstudies",
              inputs: {
                length: 20
              }
            },
            {
              id: "HV@tv-basicstudies",
              inputs: {
                length: 20
              }
            }
          ],
          overrides: {
            "paneProperties.background": "#000000",
            "paneProperties.vertGridProperties.color": "#2a2a2a",
            "paneProperties.horzGridProperties.color": "#2a2a2a"
          }
        });
      }
    };

    // Load TradingView script if not already loaded
    if (!window.TradingView) {
      const script = document.createElement('script');
      script.src = 'https://s3.tradingview.com/tv.js';
      script.async = true;
      script.onload = initChart;
      document.head.appendChild(script);
    } else {
      initChart();
    }
  }, [selectedMarket]); // Re-run when selectedMarket changes

  // Efficient countdown timer - only runs in this component
  useEffect(() => {
    const updateCountdown = () => {
      if (currentMarket?.expirationDate) {
        setLocalTimeToSettlement(calculateTimeToSettlement(currentMarket.expirationDate));
      }
    };

    // Initial calculation
    updateCountdown();

    // Start timer
    timerRef.current = setInterval(updateCountdown, 1000);

    // Cleanup on unmount or market change
    return () => {
      if (timerRef.current) {
        clearInterval(timerRef.current);
        timerRef.current = null;
      }
    };
  }, [currentMarket?.expirationDate, calculateTimeToSettlement]);

  // Clear trade inputs when market changes
  useEffect(() => {
    setUsdcAmount('');
    setSwapOutput(null);
    setIsValidAmount(true);
  }, [selectedMarket]);

  // Update user positions when the market changes
  useEffect(() => {
    if(!connected || !currentMarket) return;

    const accountAddress = account.address.bcsToHex().toString();
    const marketAddress = currentMarket.marketAddress;

    const updateUserPosition = async() => {
      try {
        const position = await getUserPosition(marketAddress, accountAddress);
        setUserPosition(position);
      } catch (error) {
        console.error('Failed to get user position:', error);
        setUserPosition(null);
      }
    }

    updateUserPosition();

  }, [currentMarket, account]);

  // Get market price when selected market changes
  useEffect(() => {
    if (!currentMarket) return;

    const fetchMarketPrice = async () => {
      try {
        const price = await getMarketPrice(currentMarket.marketAddress);
        setMarketPrice(price);
      } catch (error) {
        console.error('Failed to fetch market price:', error);
        setMarketPrice(null);
      }
    };

    fetchMarketPrice();
  }, [currentMarket, userPosition]);

  const handleMarketSelect = (market) => {
    setSelectedMarket(market.name);
    setIsDropdownOpen(false);
  };

  // Get market data from provider
  const marketData = getCurrentMarketData(selectedMarket);



  const handleUsdcAmountChange = (e) => {
    const inputValue = e.target.value;
  
    // Format the input as currency
    const formatted = formatCurrency(inputValue);
    setUsdcAmount(formatted);
    
    // Validate the amount - empty input is always valid
    const isValid = inputValue.trim() === '' || formatted === '' || isValidCurrencyAmount(formatted);
    setIsValidAmount(isValid);
    
    // Calculate swap output if valid amount
    if (isValid && formatted && formatted !== '$') {
      const numericValue = parseCurrency(inputValue);

      getAmountOut(currentMarket.marketAddress, numericValue, 'LONG')
        .then(result => setSwapOutput(result))
        .catch(error => {
          console.error('Failed to get amount out:', error);
          setSwapOutput(null);
        });
      
    } else {
      setSwapOutput(null);
    }
  };

  const handleMaxClick = () => {
    // In a real app, this would get the user's actual USDC balance
    const maxBalance = '$10,000.00';
    setUsdcAmount(maxBalance);
    setIsValidAmount(true);
    
    // Calculate swap output for max amount
    const numericValue = parseFloat(maxBalance.replace(/[^\d.]/g, ''));
    if (numericValue > 0 && currentMarket) {
      getAmountOut(currentMarket.marketAddress, numericValue, 'LONG')
        .then(result => setSwapOutput(result))
        .catch(error => {
          console.error('Failed to get amount out:', error);
          setSwapOutput(null);
        });
    }
  };

  const handleClosePosition = async (positionType) => {
    if (!connected || !currentMarket) {
      alert('Please connect wallet');
      return;
    }

    try {
      const senderAddress = account.address.bcsToHex().toString();
      const marketAddress = currentMarket.marketAddress;
      
      let transaction;
      
      if (positionType === 'LONG') {
        const ivTokenAddress = currentMarket.ivTokenAddress;
        transaction = await buildCloseLongPositionTransaction(senderAddress, marketAddress, ivTokenAddress);
      } else if (positionType === 'SHORT') {
        transaction = await buildCloseShortTransaction(marketAddress);
      } else {
        alert('Unknown position type');
        return;
      }
      
      const response = await signAndSubmitTransaction(transaction);
      
      console.log(`${positionType} position close transaction:`, response);
      alert(`${positionType} position closed successfully!`);
      
      // Refresh user position
      const position = await getUserPosition(marketAddress, senderAddress);
      setUserPosition(position);
      
    } catch (error) {
      console.error(`Failed to close ${positionType} position:`, error);
      alert(`Failed to close ${positionType} position`);
    }
  };

  const handleMintTestUSDC = async () => {
    if (!connected) {
      alert('Please connect wallet');
      return;
    }

    try {
      const senderAddress = account.address.bcsToHex().toString();
      const transaction = await mintTestUSDCTransaction(senderAddress);
      
      const response = await signAndSubmitTransaction(transaction);
      
      console.log('Mint test USDC transaction:', response);
      alert('100,000 test USDC minted successfully!');
      
    } catch (error) {
      console.error('Failed to mint test USDC:', error);
      alert('Failed to mint test USDC');
    }
  };

  const handleLongPosition = async () => {
    if (!connected || !currentMarket || !usdcAmount || !isValidAmount) {
      alert('Please connect wallet and enter a valid amount');
      return;
    }

    try {
      const senderAddress = account.address.bcsToHex().toString();
      const marketAddress = currentMarket.marketAddress;
      const amountIn = parseCurrency(usdcAmount);
      const swapType = 0; // Long position

      const transaction = await buildSwapTransaction(marketAddress, swapType, amountIn);
      
      const response = await signAndSubmitTransaction(transaction);
      
      console.log('Long position transaction:', response);
      alert('Long position opened successfully!');
      
      // Refresh user position
      const position = await getUserPosition(marketAddress, senderAddress);
      setUserPosition(position);
      
      // Clear form
      setUsdcAmount('');
      setSwapOutput(null);
      
    } catch (error) {
      console.error('Failed to open long position:', error);
      alert('Failed to open long position');
    }
  };

  const handleShortPosition = async () => {
    if (!connected || !currentMarket || !usdcAmount || !isValidAmount) {
      alert('Please connect wallet and enter a valid amount');
      return;
    }

    try {
      const senderAddress = account.address.bcsToHex().toString();
      const marketAddress = currentMarket.marketAddress;
      const amountIn = parseCurrency(usdcAmount);

      const transaction = await buildOpenShortTransaction(marketAddress, amountIn);
      
      const response = await signAndSubmitTransaction(transaction);
      
      console.log('Short position transaction:', response);
      alert('Short position opened successfully!');
      
      // Refresh user position
      const position = await getUserPosition(marketAddress, senderAddress);
      setUserPosition(position);
      
      // Clear form
      setUsdcAmount('');
      setSwapOutput(null);
      
    } catch (error) {
      console.error('Failed to open short position:', error);
      alert('Failed to open short position');
    }
  };

  return (
    <>
      <main className="internal-page-content">
        <div className="volatility-market-container">
          {/* First row - Breadcrumb navigation */}
          <div className="breadcrumb-nav">
            <div className="breadcrumb-items">
              <span className="breadcrumb-item">Markets</span>
              <span className="breadcrumb-separator">›</span>
              <span className="breadcrumb-item">Volatility</span>
              <span className="breadcrumb-separator">›</span>
              <div className="market-dropdown" ref={dropdownRef}>
                <button 
                  className="breadcrumb-item active dropdown-trigger"
                  onClick={() => setIsDropdownOpen(!isDropdownOpen)}
                >
                  {selectedMarket}
                  <span className="dropdown-arrow">▼</span>
                </button>
                {isDropdownOpen && (
                  <div className="dropdown-menu">
                    {markets.map((market) => (
                      <button
                        key={market.id}
                        className={`dropdown-item ${market.name === selectedMarket ? 'selected' : ''}`}
                        onClick={() => handleMarketSelect(market)}
                      >
                        {market.name}
                      </button>
                    ))}
                  </div>
                )}
              </div>
            </div>
            <span className="live-indicator">
              <span className="live-dot"></span>
              Live
            </span>
          </div>

          {/* Second row - Market status */}
          <div className="market-status">
            <div className="status-left">
              <span className="status-label">Time to settlement</span>
              <span className="status-value">
                {localTimeToSettlement ? formatTime(localTimeToSettlement) : '—'}
              </span>
            </div>
            <div className="status-right">
              <span className="oracle-status">
                <span className="oracle-dot"></span>
                Oracle: Pyth - Healthy
              </span>
            </div>
        </div>
      </div>
      <h1 className="page-header">{currentMarket?.pair || 'Loading...'} Volatility Prediction Market</h1>
      <p className="hero-subtitle wide">
        Trade predictions on {currentMarket?.pair || 'the selected market'}'s realized volatility. Go long if you expect higher volatility, short if you expect lower. 
        Markets settle to the actual realized volatility measured over the settlement period using Pyth oracle price data.
      </p>

      {/* Main content area with chart and trade panel */}
        <div className="main-content-grid">
          {/* Chart Section */}
          <div className="chart-section">
            {/* Chart placeholder */}
            <div className="chart-container">
              <div className="chart-placeholder">
                <div id="tradingview_chart" ref={chartRef}></div>
              </div>
            </div>

            {/* Positions Table */}
            <div className="positions-section">
              <div className="positions-header">
                <h3>Your Positions</h3>
              </div>
              <div className="positions-table-container">
                {!connected ? (
                  <div className="no-positions">Connect wallet to view positions</div>
                ) : !userPosition ? (
                  <div className="no-positions">Loading positions...</div>
                ) : (
                  <table className="positions-table">
                    <thead>
                      <tr>
                        <th>Type</th>
                        <th>Amount</th>
                        <th></th>
                      </tr>
                    </thead>
                    <tbody>
                      <tr>
                        <td>
                          <span className="position-badge long">
                            LONG IV
                          </span>
                        </td>
                        <td>{userPosition.long.toLocaleString()} tokens</td>
                        <td className="actions-cell">
                          <button 
                            className="close-position-btn width-75"
                            onClick={() => handleClosePosition('LONG')}
                            disabled={userPosition.long === 0}
                          >
                            Close
                          </button>
                        </td>
                      </tr>
                      <tr>
                        <td>
                          <span className="position-badge short">
                            SHORT IV
                          </span>
                        </td>
                        <td>{userPosition.short.toLocaleString()} tokens</td>
                        <td className="actions-cell">
                          <button 
                            className="close-position-btn width-75"
                            onClick={() => handleClosePosition('SHORT')}
                            disabled={userPosition.short === 0}
                          >
                            Close
                          </button>
                        </td>
                      </tr>
                    </tbody>
                  </table>
                )}
              </div>
            </div>
          </div>

          {/* Right Sidebar */}
          <div className="right-sidebar">
            {/* Market IV Price Section */}
            <div className="iv-price-section">
              <div className="iv-price-display">
                <div className="current-price">
                  <span className="price-label">Market IV</span>
                  <span className="price-value">{marketPrice ? `${marketPrice}%` : '—'}</span>
                </div>
                <div className="price-change">
                  <span className={`change-value ${marketData.dailyChange >= 0 ? 'positive' : 'negative'}`}>
                    {marketData.dailyChange >= 0 ? '+' : ''}{marketData.dailyChange}%
                  </span>
                  <span className="change-label">24h change</span>
                </div>
              </div>
            </div>

            {/* Trade Panel */}
            <div className="trade-panel">
            <div className="trade-header">
              <h3>Trade</h3>
            </div>
            {/* Pay section */}
            <div className="trade-section">
              <div className="section-header">
                <span>Pay</span>
                <button className="max-btn" onClick={handleMaxClick}>MAX</button>
              </div>
              <div className={`input-group ${!isValidAmount ? 'invalid' : ''}`}>
                <div className="token-select">
                  <img src="/usdc.webp" alt="USDC" className="token-icon" />
                  <span>USDC</span>
                </div>
                <input 
                  type="text" 
                  className="amount-input" 
                  placeholder="$0.00"
                  value={usdcAmount}
                  onChange={handleUsdcAmountChange}
                />
              </div>
              {!isValidAmount && (
                <div className="input-error">Please enter a valid amount</div>
              )}
            </div>

            {/* Trade details */}
            <div className="trade-details">
              <div className="detail-row">
                <span>Receive</span>
                <span className="detail-value">
                  {swapOutput ? `${swapOutput.outputTokens.toLocaleString()} IV tokens` : '—'}
                </span>
              </div>
              <div className="detail-row">
                <span>Fees ({swapOutput?.feePercentage || 1}%)</span>
                <span className="detail-value">
                  {swapOutput ? `$${ swapOutput.feeAmount.toFixed(2)}` : '—'}
                </span>
              </div>
            </div>

            {/* Action buttons */}
            <div className="action-buttons">
              <button 
                className="action-btn primary" 
                onClick={handleLongPosition}
                disabled={!connected || !usdcAmount || !isValidAmount}
              >
                Buy IV
              </button>
              <button 
                className="action-btn secondary" 
                onClick={handleShortPosition}
                disabled={!connected || !usdcAmount || !isValidAmount}
              >
                Open Short
              </button>
            </div>

            {/* Test USDC Mint Section */}
            <div className="test-usdc-section">
              <button 
                className="action-btn accent full-width" 
                onClick={handleMintTestUSDC}
                disabled={!connected}
              >
                Mint 100,000 Test USDC
              </button>
            </div>
          </div>
        </div>
      </div>
      </main>
    </>
  );
}

export default VolatilityMarket;
