import React, { useState, useEffect } from 'react';
import { useWallet } from "@aptos-labs/wallet-adapter-react";
import { formatCurrency, isValidCurrencyAmount, parseCurrency } from '../lib/currency';
import './OptionsPage.css';

function OptionsPage() {
  const { connected } = useWallet();
  
  // State for multi-leg option configuration
  const [selectedAsset, setSelectedAsset] = useState('BTC');
  const [legs, setLegs] = useState([
    {
      id: 1,
      optionType: 'call',
      strikePrice: '',
      expirationDays: '7',
      collateralAmount: '',
      isValidAmount: true,
      side: 'buy' // 'buy' or 'sell'
    }
  ]);
  
  // Mock data for available assets
  const assets = [
    { symbol: 'BTC', name: 'Bitcoin', price: 67500, change: '+2.1%' },
    { symbol: 'ETH', name: 'Ethereum', price: 3850, change: '+1.8%' },
    { symbol: 'APT', name: 'Aptos', price: 12.45, change: '+4.2%' },
    { symbol: 'SOL', name: 'Solana', price: 145, change: '-0.5%' }
  ];
  
  // Mock positions data
  const [userPositions] = useState([
    {
      id: '1',
      asset: 'BTC',
      type: 'call',
      strike: 70000,
      expiration: '2025-10-10',
      premium: 1250,
      collateral: 5000,
      currentValue: 1420,
      pnl: 170,
      pnlPercent: 13.6
    },
    {
      id: '2', 
      asset: 'ETH',
      type: 'put',
      strike: 3500,
      expiration: '2025-10-17',
      premium: 850,
      collateral: 3500,
      currentValue: 720,
      pnl: -130,
      pnlPercent: -15.3
    }
  ]);

  // Add a new leg to the strategy
  const addLeg = () => {
    if (legs.length < 3) {
      const newLeg = {
        id: Math.max(...legs.map(l => l.id)) + 1,
        optionType: 'call',
        strikePrice: '',
        expirationDays: '7',
        collateralAmount: '',
        isValidAmount: true,
        side: 'buy'
      };
      setLegs([...legs, newLeg]);
    }
  };

  // Remove a leg from the strategy
  const removeLeg = (legId) => {
    if (legs.length > 1) {
      setLegs(legs.filter(leg => leg.id !== legId));
    }
  };

  // Update a specific leg's property
  const updateLeg = (legId, property, value) => {
    setLegs(legs.map(leg => 
      leg.id === legId ? { ...leg, [property]: value } : leg
    ));
  };

  const handleCollateralAmountChange = (legId, e) => {
    const inputValue = e.target.value;
    const formatted = formatCurrency(inputValue);
    updateLeg(legId, 'collateralAmount', formatted);
    
    const isValid = inputValue.trim() === '' || formatted === '' || isValidCurrencyAmount(formatted);
    updateLeg(legId, 'isValidAmount', isValid);
  };

  const calculateLegPremium = (leg) => {
    // Mock premium calculation for a single leg
    if (!leg.strikePrice || !leg.collateralAmount) return 0;
    
    const strike = parseFloat(leg.strikePrice);
    const collateral = parseCurrency(leg.collateralAmount);
    const asset = assets.find(a => a.symbol === selectedAsset);
    const spotPrice = asset?.price || 0;
    
    // Simple mock calculation based on moneyness and time
    const moneyness = leg.optionType === 'call' ? 
      Math.max(0, spotPrice - strike) : 
      Math.max(0, strike - spotPrice);
    
    const timeValue = parseFloat(leg.expirationDays) * 2; // Mock time value
    let premium = moneyness + timeValue + (collateral * 0.02); // 2% base premium
    premium = Math.max(premium, collateral * 0.01); // Minimum 1% of collateral
    
    // If selling, premium is received (positive), if buying, premium is paid (negative)
    return leg.side === 'sell' ? premium : -premium;
  };

  const calculateTotalStrategy = () => {
    const totalPremium = legs.reduce((sum, leg) => sum + calculateLegPremium(leg), 0);
    const totalCollateral = legs.reduce((sum, leg) => {
      const collateral = leg.collateralAmount ? parseCurrency(leg.collateralAmount) : 0;
      return sum + collateral;
    }, 0);
    
    return {
      netPremium: totalPremium,
      totalCollateral: totalCollateral,
      maxProfit: legs.some(leg => leg.side === 'sell') ? 
        Math.abs(totalPremium) : // Limited profit if selling premium
        'Unlimited', // Unlimited if only buying
      maxLoss: totalCollateral + Math.min(0, totalPremium) // Collateral + premium paid
    };
  };

  const strategyCalculation = calculateTotalStrategy();

  // Detect common strategy names
  const getStrategyName = () => {
    if (legs.length === 1) return 'Single Option';
    if (legs.length === 2) {
      const [leg1, leg2] = legs;
      if (leg1.optionType === leg2.optionType && leg1.side !== leg2.side) {
        return 'Vertical Spread';
      }
      if (leg1.optionType !== leg2.optionType && leg1.strikePrice === leg2.strikePrice) {
        return 'Straddle';
      }
      if (leg1.optionType !== leg2.optionType && leg1.strikePrice !== leg2.strikePrice) {
        return 'Strangle';
      }
    }
    return 'Custom Strategy';
  };

  const currentAsset = assets.find(asset => asset.symbol === selectedAsset);

  return (
    <main className="internal-page-content">
      <div className="options-page-container">
        {/* Header */}
        <div className="page-header-section">
          <h1 className="page-header">Options Trading</h1>
          <p className="hero-subtitle wide">
            Create and trade multi-leg options strategies. Build spreads, straddles, and custom combinations up to 3 legs.
          </p>
        </div>

        <div className="options-main-grid">
          {/* Left Column - Strategy Creation */}
          <div className="option-creation-panel">
            <div className="panel-header">
              <h3>{getStrategyName()}</h3>
              <div className="leg-controls">
                <span className="leg-count">{legs.length} leg{legs.length > 1 ? 's' : ''}</span>
                {legs.length < 3 && (
                  <button className="add-leg-btn" onClick={addLeg}>
                    + Add Leg
                  </button>
                )}
              </div>
            </div>

            {/* Asset Selection - Global for all legs */}
            <div className="global-asset-section">
              <div className="asset-selector-header">
                <label className="form-label">Underlying Asset</label>
                <div className="asset-selector-row">
                  <select 
                    className="form-select asset-dropdown"
                    value={selectedAsset}
                    onChange={(e) => setSelectedAsset(e.target.value)}
                  >
                    {assets.map(asset => (
                      <option key={asset.symbol} value={asset.symbol}>
                        {asset.symbol} - {asset.name}
                      </option>
                    ))}
                  </select>
                  <div className="asset-price-display">
                    <span className="current-price">${currentAsset?.price.toLocaleString()}</span>
                    <span className={`price-change ${currentAsset?.change.startsWith('+') ? 'positive' : 'negative'}`}>
                      {currentAsset?.change} 24h
                    </span>
                  </div>
                </div>
              </div>
            </div>

            {/* Strategy Legs */}
            <div className="strategy-legs">
              {legs.map((leg, index) => (
                <div key={leg.id} className="leg-container">
                  <div className="leg-header">
                    <div className="leg-title">
                      <span className="leg-number">Leg {index + 1}</span>
                      {legs.length > 1 && (
                        <button 
                          className="remove-leg-btn"
                          onClick={() => removeLeg(leg.id)}
                        >
                          ✕
                        </button>
                      )}
                    </div>
                  </div>

                  {/* Side Selection */}
                  <div className="form-section">
                    <label className="form-label">Side</label>
                    <div className="side-toggle">
                      <button
                        className={`toggle-btn ${leg.side === 'buy' ? 'active' : ''}`}
                        onClick={() => updateLeg(leg.id, 'side', 'buy')}
                      >
                        Buy
                      </button>
                      <button
                        className={`toggle-btn ${leg.side === 'sell' ? 'active' : ''}`}
                        onClick={() => updateLeg(leg.id, 'side', 'sell')}
                      >
                        Sell
                      </button>
                    </div>
                  </div>

                  {/* Option Type and Collateral */}
                  <div className="form-row">
                    <div className="form-section">
                      <label className="form-label">Type</label>
                      <div className="option-type-toggle">
                        <button
                          className={`toggle-btn ${leg.optionType === 'call' ? 'active' : ''}`}
                          onClick={() => updateLeg(leg.id, 'optionType', 'call')}
                        >
                          Call
                        </button>
                        <button
                          className={`toggle-btn ${leg.optionType === 'put' ? 'active' : ''}`}
                          onClick={() => updateLeg(leg.id, 'optionType', 'put')}
                        >
                          Put
                        </button>
                      </div>
                    </div>

                    <div className="form-section">
                      <label className="form-label">Collateral</label>
                      <div className={`input-group ${!leg.isValidAmount ? 'invalid' : ''}`}>
                        <div className="token-select">
                          <img src="/usdc.webp" alt="USDC" className="token-icon" />
                          <span>USDC</span>
                        </div>
                        <input
                          type="text"
                          className="amount-input"
                          placeholder="$0.00"
                          value={leg.collateralAmount}
                          onChange={(e) => handleCollateralAmountChange(leg.id, e)}
                        />
                      </div>
                      {!leg.isValidAmount && (
                        <div className="input-error">Please enter a valid amount</div>
                      )}
                    </div>
                  </div>

                  {/* Strike Price and Expiration */}
                  <div className="form-row">
                    <div className="form-section">
                      <label className="form-label">Strike Price</label>
                      <div className="input-group">
                        <span className="input-prefix">$</span>
                        <input
                          type="text"
                          className="form-input"
                          placeholder="70,000"
                          value={leg.strikePrice}
                          onChange={(e) => updateLeg(leg.id, 'strikePrice', e.target.value)}
                        />
                      </div>
                    </div>

                    <div className="form-section">
                      <label className="form-label">Expiration</label>
                      <select 
                        className="form-select"
                        value={leg.expirationDays}
                        onChange={(e) => updateLeg(leg.id, 'expirationDays', e.target.value)}
                      >
                        <option value="1">1 Day</option>
                        <option value="7">7 Days</option>
                        <option value="14">14 Days</option>
                        <option value="30">30 Days</option>
                        <option value="60">60 Days</option>
                        <option value="90">90 Days</option>
                      </select>
                    </div>
                  </div>
                </div>
              ))}
            </div>

            {/* Strategy Summary */}
            <div className="strategy-summary">
              <div className="summary-header">
                <h4>Strategy Summary</h4>
              </div>
              <div className="detail-row">
                <span>Net Premium</span>
                <span className={`detail-value ${strategyCalculation.netPremium >= 0 ? 'positive' : 'negative'}`}>
                  {strategyCalculation.netPremium >= 0 ? '+' : ''}${Math.abs(strategyCalculation.netPremium).toFixed(2)}
                </span>
              </div>
              <div className="detail-row">
                <span>Total Collateral</span>
                <span className="detail-value">${strategyCalculation.totalCollateral.toLocaleString()}</span>
              </div>
              <div className="detail-row">
                <span>Max Profit</span>
                <span className="detail-value">
                  {typeof strategyCalculation.maxProfit === 'string' ? 
                    strategyCalculation.maxProfit : 
                    `$${strategyCalculation.maxProfit.toFixed(2)}`
                  }
                </span>
              </div>
              <div className="detail-row">
                <span>Max Loss</span>
                <span className="detail-value">${strategyCalculation.maxLoss.toFixed(2)}</span>
              </div>
            </div>

            {/* Create Button */}
            <button 
              className="create-option-btn"
              disabled={!connected || legs.some(leg => !leg.strikePrice || !leg.collateralAmount || !leg.isValidAmount)}
            >
              {!connected ? 'Connect Wallet' : `Create ${getStrategyName()}`}
            </button>
          </div>

          {/* Right Column - Positions & Market Info */}
          <div className="options-sidebar">
            {/* Current Positions */}
            <div className="positions-panel">
              <div className="panel-header">
                <h3>Your Positions</h3>
              </div>
              
              {!connected ? (
                <div className="no-positions">Connect wallet to view positions</div>
              ) : userPositions.length === 0 ? (
                <div className="no-positions">No active positions</div>
              ) : (
                <div className="positions-list">
                  {userPositions.map(position => (
                    <div key={position.id} className="position-card">
                      <div className="position-header">
                        <div className="position-asset">
                          <span className={`position-type ${position.type}`}>
                            {position.type.toUpperCase()}
                          </span>
                          <span className="position-symbol">{position.asset}</span>
                        </div>
                        <div className={`position-pnl ${position.pnl >= 0 ? 'positive' : 'negative'}`}>
                          {position.pnl >= 0 ? '+' : ''}${position.pnl}
                          <span className="pnl-percent">
                            ({position.pnl >= 0 ? '+' : ''}{position.pnlPercent}%)
                          </span>
                        </div>
                      </div>
                      
                      <div className="position-details">
                        <div className="position-row">
                          <span>Strike:</span>
                          <span>${position.strike.toLocaleString()}</span>
                        </div>
                        <div className="position-row">
                          <span>Expires:</span>
                          <span>{new Date(position.expiration).toLocaleDateString()}</span>
                        </div>
                        <div className="position-row">
                          <span>Premium:</span>
                          <span>${position.premium}</span>
                        </div>
                      </div>
                      
                      <button className="close-position-btn">
                        Close Position
                      </button>
                    </div>
                  ))}
                </div>
              )}
            </div>

            {/* Market Stats */}
            <div className="market-stats-panel">
              <div className="panel-header">
                <h3>Market Stats</h3>
              </div>
              
              <div className="stats-grid">
                <div className="stat-item">
                  <div className="stat-label">Total Volume</div>
                  <div className="stat-value">$2.4M</div>
                </div>
                <div className="stat-item">
                  <div className="stat-label">Open Interest</div>
                  <div className="stat-value">$892K</div>
                </div>
                <div className="stat-item">
                  <div className="stat-label">Active Options</div>
                  <div className="stat-value">347</div>
                </div>
                <div className="stat-item">
                  <div className="stat-label">Avg IV</div>
                  <div className="stat-value">72.3%</div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </main>
  );
}

export default OptionsPage;
