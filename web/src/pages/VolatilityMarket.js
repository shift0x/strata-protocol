import React, { useState, useEffect, useRef } from 'react';
import { useVolatilityMarket } from '../providers/VolatilityMarketProvider';
import './VolatilityMarket.css';

function VolatilityMarket() {
  const {
    markets,
    selectedMarket,
    setSelectedMarket,
    currentMarket,
    formattedTimeToSettlement
  } = useVolatilityMarket();
  
  const [isDropdownOpen, setIsDropdownOpen] = useState(false);
  const dropdownRef = useRef(null);
  const chartRef = useRef(null);
  const chartWidget = useRef(null);

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
          interval: "5",
          timezone: "Etc/UTC",
          theme: "dark",
          style: "1",
          locale: "en",
          toolbar_bg: "#1a1f2b",
          enable_publishing: false,
          allow_symbol_change: false,
          container_id: "tradingview_chart",
          autosize: true,
          studies: [],
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

    return () => {
      // Cleanup chart widget when component unmounts or market changes
      if (chartWidget.current) {
        chartWidget.current.remove();
        chartWidget.current = null;
      }
    };
  }, [selectedMarket]); // Re-run when selectedMarket changes

  const handleMarketSelect = (market) => {
    setSelectedMarket(market.name);
    setIsDropdownOpen(false);
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
              <span className="status-value">{formattedTimeToSettlement}</span>
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

            {/* Statistics cards */}
            <div className="stats-cards">
              <div className="stat-card">
                <div className="stat-label">Mark IV</div>
                <div className="stat-value">47,3 %</div>
              </div>
              <div className="stat-card">
                <div className="stat-label">30d HV (oracle)</div>
                <div className="stat-value">42,8 %</div>
              </div>
              <div className="stat-card">
                <div className="stat-label">Basis</div>
                <div className="stat-value positive">+4 B vol pts</div>
                <div className="stat-subvalue positive">+10,3%</div>
              </div>
              <div className="stat-card">
                <div className="stat-label">IV token</div>
                <div className="stat-value">$1,047</div>
              </div>
              <div className="stat-card">
                <div className="stat-label">Pool TVL</div>
                <div className="stat-value">$9,6 M</div>
              </div>
            </div>
          </div>

          {/* Trade Panel */}
          <div className="trade-panel">
            <div className="trade-header">
              <h3>Trade</h3>
            </div>

            {/* Trade type toggle */}
            <div className="trade-toggle">
              <button className="toggle-btn active">Long IV</button>
              <button className="toggle-btn">Short IV</button>
            </div>

            {/* Pay section */}
            <div className="trade-section">
              <div className="section-header">
                <span>Pay</span>
                <button className="max-btn">MAX</button>
              </div>
              <div className="input-group">
                <div className="token-select">
                  <img src="/usdc-icon.png" alt="USDC" className="token-icon" />
                  <span>USDC</span>
                  <span className="dropdown-arrow">▼</span>
                </div>
                <input type="text" className="amount-input" placeholder="0" />
              </div>
            </div>

            {/* Receive section */}
            <div className="trade-section">
              <div className="section-header">
                <span>Receive</span>
                <button className="options-btn">⋯</button>
              </div>
              <div className="receive-options">
                <select className="slippage-select">
                  <option>S Slippage</option>
                </select>
                <select className="pool-select">
                  <option>AMM pool</option>
                </select>
              </div>
            </div>

            {/* Trade details */}
            <div className="trade-details">
              <div className="detail-row">
                <span>Price Impact</span>
                <span>0.5%</span>
              </div>
              <div className="detail-row">
                <span>Fees</span>
                <button className="info-btn">⋯</button>
              </div>
            </div>

            {/* Action buttons */}
            <div className="action-buttons">
              <button className="action-btn primary">Buy IV</button>
              <button className="action-btn secondary">Open Short</button>
            </div>

            {/* Settlement info */}
            <div className="settlement-info">
              <span>Market settles to 30-day rialiable</span>
              <span className="settlement-rate positive">+7,5 %</span>
            </div>
          </div>
        </div>
      </main>
    </>
  );
}

export default VolatilityMarket;
