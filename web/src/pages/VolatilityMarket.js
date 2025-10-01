import React, { useState, useEffect, useRef } from 'react';
import { useVolatilityMarket } from '../providers/VolatilityMarketProvider';
import { formatCurrency, parseCurrency, isValidCurrencyAmount } from '../lib/currency';
import './VolatilityMarket.css';

function VolatilityMarket() {
  const {
    markets,
    selectedMarket,
    setSelectedMarket,
    currentMarket,
    formattedTimeToSettlement,
    calculateTimeToSettlement,
    formatTime,
    getOpenPositions,
    getClosedPositions,
    closePosition,
    calculateSwapOutput,
    getCurrentIVPrice,
    getCurrentMarketData
  } = useVolatilityMarket();
  
  const [isDropdownOpen, setIsDropdownOpen] = useState(false);
  const [showOpenPositions, setShowOpenPositions] = useState(true);
  const [localTimeToSettlement, setLocalTimeToSettlement] = useState(null);
  const [usdcAmount, setUsdcAmount] = useState('');
  const [isValidAmount, setIsValidAmount] = useState(true);
  const [swapOutput, setSwapOutput] = useState(null);
  const dropdownRef = useRef(null);
  const chartRef = useRef(null);
  const chartWidget = useRef(null);
  const timerRef = useRef(null);

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

  // Function to get TradingView symbol based on market
  const getSymbolForMarket = (market) => {
    const symbolMap = {
      'APT-USD (30d)': 'BINANCE:APTUSDT',
      'BTC-USD (30d)': 'BINANCE:BTCUSDT',
      'ETH-USD (30d)': 'BINANCE:ETHUSDT',
      'SOL-USD (30d)': 'BINANCE:SOLUSDT'
    };
    return symbolMap[market] || 'BINANCE:BTCUSDT';
  };

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
          symbol: getSymbolForMarket(selectedMarket),
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

  const handleMarketSelect = (market) => {
    setSelectedMarket(market.name);
    setIsDropdownOpen(false);
  };

  // Get positions and market data from provider
  const openPositions = getOpenPositions();
  const closedPositions = getClosedPositions();
  const marketData = getCurrentMarketData();

  const handleClosePosition = (positionId) => {
    closePosition(positionId);
    // In a real app, you might want to refresh the data or show a confirmation
    alert(`Position ${positionId} closed successfully!`);
  };

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
      const output = calculateSwapOutput(formatted, 'BUY');
      setSwapOutput(output);
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
    const output = calculateSwapOutput(maxBalance, 'BUY');
    setSwapOutput(output);
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
                {localTimeToSettlement ? formatTime(localTimeToSettlement) : formattedTimeToSettlement}
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
      <h1 className="page-header">{currentMarket.pair} Volatility Prediction Market</h1>
      <p className="hero-subtitle wide">
        Trade predictions on {currentMarket.pair}'s 30-day realized volatility. Go long if you expect higher volatility, short if you expect lower. 
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
                <div className="position-toggles">
                  <button 
                    className={`toggle-btn ${showOpenPositions ? 'active' : ''}`}
                    onClick={() => setShowOpenPositions(true)}
                  >
                    Open ({openPositions.length})
                  </button>
                  <button 
                    className={`toggle-btn ${!showOpenPositions ? 'active' : ''}`}
                    onClick={() => setShowOpenPositions(false)}
                  >
                    Closed ({closedPositions.length})
                  </button>
                </div>
              </div>
              <div className="positions-table-container">
                <table className="positions-table">
                  <thead>
                    <tr>
                      <th>Type</th>
                      <th>Size</th>
                      <th>Entry Price</th>
                      {showOpenPositions ? <th>Current Price</th> : <th>Exit Price</th>}
                      <th>P&L</th>
                      <th>Date</th>
                      {showOpenPositions && <th></th>}
                    </tr>
                  </thead>
                  <tbody>
                    {(showOpenPositions ? openPositions : closedPositions).map((position) => (
                      <tr key={position.id}>
                        <td>
                          <span className={`position-badge ${position.type.toLowerCase()}`}>
                            {position.type} IV
                          </span>
                        </td>
                        <td>{position.size.toLocaleString()} tokens</td>
                        <td>{position.entryPrice}%</td>
                        <td>
                          {showOpenPositions ? `${position.currentPrice}%` : `${position.exitPrice}%`}
                        </td>
                        <td>
                          <div className="pnl-cell">
                            <span className={`pnl-value ${position.pnl >= 0 ? 'positive' : 'negative'}`}>
                              {position.pnl >= 0 ? '+' : ''}${Math.abs(position.pnl).toFixed(2)} ({position.pnlPercentage}%)
                            </span>
                          </div>
                        </td>
                        <td className="date-cell">
                          <div>
                            <div>
                              {position.timestamp.split(' ')[0]}
                              <span className="time"> {position.timestamp.split(' ')[1]}</span>
                            </div>
                          </div>
                        </td>
                          {showOpenPositions && (
                           <td className="actions-cell">
                             <button 
                               className="close-position-btn"
                               onClick={() => handleClosePosition(position.id)}
                             >
                               Close
                             </button>
                           </td>
                         )}
                       </tr>
                    ))}
                  </tbody>
                </table>
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
                  <span className="price-value">{marketData.currentIV}%</span>
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
                <span>Fees (${swapOutput?.feePercentage || 1}%)</span>
                <span className="detail-value">
                  {swapOutput ? `$${swapOutput.feeAmount.toFixed(2)}` : '—'}
                </span>
              </div>
            </div>

            {/* Action buttons */}
            <div className="action-buttons">
              <button className="action-btn primary">Buy IV</button>
              <button className="action-btn secondary">Open Short</button>
            </div>
          </div>
        </div>
      </div>
      </main>
    </>
  );
}

export default VolatilityMarket;
