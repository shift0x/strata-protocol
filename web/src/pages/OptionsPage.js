import React, { useState, useEffect } from 'react';
import { useWallet } from "@aptos-labs/wallet-adapter-react";
import { formatCurrency, isValidCurrencyAmount, parseCurrency } from '../lib/currency';
import { openOptionPosition, getUserPositions } from '../lib/optionsExchange';
import { getAssetPrice } from '../lib/pyth';
import './OptionsPage.css';

function OptionsPage() {
  const { connected, signAndSubmitTransaction, account } = useWallet();
  
  // State for multi-leg option configuration
  const [selectedAsset, setSelectedAsset] = useState('BTC-USD');
  const [legs, setLegs] = useState([
    {
      id: 1,
      optionType: 'call',
      strikePrice: '',
      expirationDays: '7',
      amount: '',
      isValidAmount: true,
      isValidStrike: true,
      side: 'buy' // 'buy' or 'sell'
    }
  ]);
  
  // Available assets
  const assets = [
    { symbol: 'BTC-USD', name: 'Bitcoin' },
    { symbol: 'ETH-USD', name: 'Ethereum' },
    { symbol: 'APT-USD', name: 'Aptos' },
  ];

  const [assetPrices, setAssetPrices] = useState({});
  
  // Fetch asset prices
  useEffect(() => {
    const fetchPrices = async () => {
      try {
        const pricePromises = assets.map(async (asset) => {
          const symbol = asset.symbol.replace('-', '');
          const price = await getAssetPrice(symbol);
          return { symbol: asset.symbol, price };
        });
        
        const prices = await Promise.all(pricePromises);
        const priceMap = {};
        prices.forEach(({ symbol, price }) => {
          priceMap[symbol] = price;
        });
        setAssetPrices(priceMap);
      } catch (error) {
        console.error('Error fetching asset prices:', error);
      }
    };

    fetchPrices();
  }, []);

  // Clear option legs when asset changes
  useEffect(() => {
    setLegs([{
      id: 1,
      optionType: 'call',
      strikePrice: '',
      expirationDays: '7',
      amount: '',
      isValidAmount: true,
      isValidStrike: true,
      side: 'buy'
    }]);
  }, [selectedAsset]);

  // Fetch user positions when connected user changes
  useEffect(() => {
    const fetchUserPositions = async () => {
      if (connected && account?.address) {
        try {
          const accountAddress = account.address.bcsToHex().toString();
          const positions = await getUserPositions(accountAddress);
          console.log('User positions:', positions);
        } catch (error) {
          console.error('Error fetching user positions:', error);
        }
      }
    };

    fetchUserPositions();
  }, [connected, account?.address]);
  
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
        amount: '',
        isValidAmount: true,
        isValidStrike: true,
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
    console.log({legId, property, value})

    const updatedLegs = legs.map(leg => {
      if(leg.id == legId){
        leg[property] = value;
      }

      return leg;
    });

    setLegs(updatedLegs);
  };

  const handleAmountChange = (legId, e) => {
    const inputValue = e.target.value;
    
    // Allow digits and decimal point for contract count
    const cleaned = inputValue.replace(/[^\d.]/g, '');
    
    // Prevent multiple decimal points
    const parts = cleaned.split('.');
    const validInput = parts.length > 2 ? parts[0] + '.' + parts[1] : cleaned;
    
    // Update the leg with the clean input
    updateLeg(legId, 'amount', validInput);
    
    // Validate the input - must be positive number
    const isValid = validInput === '' || (parseFloat(validInput) > 0 && !isNaN(parseFloat(validInput)));
    updateLeg(legId, 'isValidAmount', isValid);
  };

  const handleStrikePriceChange = (legId, e) => {
    const inputValue = e.target.value;
    
    // Use the currency library to format
    const formatted = formatCurrency(inputValue);
    
    // Update the leg with the formatted input
    updateLeg(legId, 'strikePrice', formatted);
    
    // Use the currency library to validate
    const isValid = inputValue === '' || isValidCurrencyAmount(formatted);
    updateLeg(legId, 'isValidStrike', isValid);
  };

  const handleQuickStrike = (legId, percentage) => {
    const currentPrice = assetPrices[selectedAsset];
    if (!currentPrice) return;

    const leg = legs.find(l => l.id === legId);
    if (!leg) return;

    let strikePrice;
    
    if (leg.optionType === 'call') {
      // For calls: ITM = below current, OTM = above current
      strikePrice = currentPrice * (1 + percentage / 100);
    } else {
      // For puts: ITM = above current, OTM = below current  
      strikePrice = currentPrice * (1 - percentage / 100);
    }

    // Round to nearest $5
    strikePrice = Math.round(strikePrice / 5) * 5;

    const formatted = formatCurrency(strikePrice.toString());
    updateLeg(legId, 'strikePrice', formatted);
    updateLeg(legId, 'isValidStrike', true);
  };

  // Strategy calculation placeholder - will be replaced with library
  const strategyCalculation = {
    netPremium: 0,
    totalAmount: 0,
    maxProfit: 'TBD',
    maxLoss: 0
  };



  // Handle creating position
  const handleCreatePosition = async () => {
    try {
      // Convert UI data to contract format
      const asset_symbol = selectedAsset;
      
      const leg_option_types = legs.map(leg => 
        leg.optionType === 'call' ? 0 : 1
      );
      
      const leg_option_sides = legs.map(leg => 
        leg.side === 'buy' ? 0 : 1  // buy = long (0), sell = short (1)
      );
      
      const leg_option_amounts = legs.map(leg => 
        parseFloat(leg.amount) || 0
      );
      
      const leg_option_strike_prices = legs.map(leg => 
        parseFloat(parseCurrency(leg.strikePrice))
      );
      
      const leg_option_expirations = legs.map(leg => {
        // Convert days to timestamp (current time + days * 24 * 60 * 60)
        const daysInSeconds = parseInt(leg.expirationDays) * 24 * 60 * 60;
        return Math.floor(Date.now() / 1000) + daysInSeconds;
      });

      // Create the transaction
      const transaction = await openOptionPosition(
        asset_symbol,
        leg_option_types,
        leg_option_sides,
        leg_option_amounts,
        leg_option_strike_prices,
        leg_option_expirations
      );

      // Submit transaction to blockchain
      const response = await signAndSubmitTransaction(transaction);
      
      alert(`Position created successfully! Transaction hash: ${response.hash}`);
      
    } catch (error) {
      console.error('Error creating position:', error);
      alert('Error creating position. Please try again.');
    }
  };



  return (
    <main className="internal-page-content">
      <div className="options-page-container">
        {/* Header */}
        <div className="page-header-section">
          <h1 className="page-header">Options Trading</h1>
          <p className="hero-subtitle wide">
            Create and trade multi-leg option positions. Build spreads, straddles, and custom combinations. 
            Options are priced using an on-chain Binomial Option Pricing Model that uses Pyth oracles for underlying asset price data and
            risk-free rates.
          </p>
        </div>

        <div className="options-main-grid">
          {/* Left Column - Strategy Creation */}
          <div className="option-creation-panel">
            <div className="panel-header">
              <h3>Position Builder</h3>
              <div className="leg-controls">
                <span className="leg-count">{legs.length} leg{legs.length > 1 ? 's' : ''}</span>
                  <button className="add-leg-btn" onClick={addLeg}>
                    + Add Leg
                  </button>
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
                  <span className="current-price">
                    {assetPrices[selectedAsset] ? 
                    `$${assetPrices[selectedAsset].toLocaleString()}` : 
                      'Loading...'
                      }
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
                      <label className="form-label">Contracts</label>
                      <div className={`input-group ${!leg.isValidAmount ? 'invalid' : ''}`}>
                        <input
                          type="text"
                          className="amount-input"
                          placeholder="1.0"
                          value={leg.amount}
                          onChange={(e) => handleAmountChange(leg.id, e)}
                        />
                      </div>
                      {!leg.isValidAmount && (
                        <div className="input-error">Please enter a valid number of contracts</div>
                      )}
                    </div>
                  </div>

                  {/* Strike Price and Expiration */}
                  <div className="form-row">
                  <div className="form-section">
                  <label className="form-label">Strike Price</label>
                  <div className={`input-group ${!leg.isValidStrike ? 'invalid' : ''}`}>
                  <span className="input-prefix">$</span>
                  <input
                  type="text"
                  className="form-input"
                  placeholder="70,000"
                  value={leg.strikePrice}
                  onChange={(e) => handleStrikePriceChange(leg.id, e)}
                  />
                  </div>
                  <div className="quick-strike-options">
                  <button 
                      type="button"
                        className="quick-strike-btn"
                           onClick={() => handleQuickStrike(leg.id, leg.optionType === 'call' ? -10 : 10)}
                         >
                           10% ITM
                         </button>
                         <button 
                           type="button"
                           className="quick-strike-btn"
                           onClick={() => handleQuickStrike(leg.id, leg.optionType === 'call' ? -5 : 5)}
                         >
                           5% ITM
                         </button>
                         <button 
                           type="button"
                           className="quick-strike-btn"
                           onClick={() => handleQuickStrike(leg.id, 0)}
                         >
                           ATM
                         </button>
                         <button 
                           type="button"
                           className="quick-strike-btn"
                           onClick={() => handleQuickStrike(leg.id, leg.optionType === 'call' ? 5 : -5)}
                         >
                           5% OTM
                         </button>
                         <button 
                           type="button"
                           className="quick-strike-btn"
                           onClick={() => handleQuickStrike(leg.id, leg.optionType === 'call' ? 10 : -10)}
                         >
                           10% OTM
                         </button>
                       </div>
                       {!leg.isValidStrike && (
                         <div className="input-error">Please enter a valid strike price</div>
                       )}
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
                <span className="detail-value">
                  $0.00
                </span>
              </div>
              <div className="detail-row">
                <span>Total Amount</span>
                <span className="detail-value">$0</span>
              </div>
              <div className="detail-row">
                <span>Max Profit</span>
                <span className="detail-value">
                  TBD
                </span>
              </div>
              <div className="detail-row">
                <span>Max Loss</span>
                <span className="detail-value">$0.00</span>
              </div>
            </div>

            {/* Create Button */}
            <button 
              className="create-option-btn"
              disabled={!connected || legs.some(leg => !leg.strikePrice || !leg.amount || !leg.isValidAmount || !leg.isValidStrike)}
              onClick={handleCreatePosition}
            >
              {!connected ? 'Connect Wallet' : 'Create Position'}
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
