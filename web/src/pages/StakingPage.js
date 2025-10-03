import React, { useState, useEffect } from 'react';
import { useWallet } from "@aptos-labs/wallet-adapter-react";
import { formatCurrency, isValidCurrencyAmount, parseCurrency } from '../lib/currency';
import { stake, unstake, getStakingBalance } from '../lib/staking';
import './StakingPage.css';

function StakingPage() {
  const { connected, account, signAndSubmitTransaction } = useWallet();
  
  const [stakeAmount, setStakeAmount] = useState('');
  const [unstakeAmount, setUnstakeAmount] = useState('');
  const [isValidStakeAmount, setIsValidStakeAmount] = useState(true);
  const [isValidUnstakeAmount, setIsValidUnstakeAmount] = useState(true);
  const [stakingBalance, setStakingBalance] = useState(null);
  const [loading, setLoading] = useState(false);
  const [activeTab, setActiveTab] = useState('stake');

  // Load staking balance when wallet connects or account changes
  useEffect(() => {
    if (!connected || !account) return;

    const fetchStakingBalance = async () => {
      try {
        const accountAddress = account.address.bcsToHex().toString();
        const balance = await getStakingBalance(accountAddress);
        setStakingBalance(balance);
      } catch (error) {
        console.error('Failed to fetch staking balance:', error);
        setStakingBalance(null);
      }
    };

    fetchStakingBalance();
  }, [connected, account]);

  const handleStakeAmountChange = (e) => {
    const inputValue = e.target.value;
    const formatted = formatCurrency(inputValue);
    setStakeAmount(formatted);
    
    const isValid = inputValue.trim() === '' || formatted === '' || isValidCurrencyAmount(formatted);
    setIsValidStakeAmount(isValid);
  };

  const handleUnstakeAmountChange = (e) => {
    const inputValue = e.target.value;
    const formatted = formatCurrency(inputValue);
    setUnstakeAmount(formatted);
    
    const isValid = inputValue.trim() === '' || formatted === '' || isValidCurrencyAmount(formatted);
    setIsValidUnstakeAmount(isValid);
  };

  const handleMaxStake = () => {
    // In a real app, this would get the user's actual USDC balance
    const maxBalance = '$10,000.00';
    setStakeAmount(maxBalance);
    setIsValidStakeAmount(true);
  };

  const handleMaxUnstake = () => {
    if (stakingBalance && stakingBalance.currentStakingAmount) {
      const maxUnstake = `$${stakingBalance.currentStakingAmount.toLocaleString()}.00`;
      setUnstakeAmount(maxUnstake);
      setIsValidUnstakeAmount(true);
    }
  };

  const handleStake = async () => {
    if (!connected || !stakeAmount || !isValidStakeAmount) {
      alert('Please connect wallet and enter a valid amount');
      return;
    }

    setLoading(true);
    try {
      const amountToStake = parseCurrency(stakeAmount);
      const transaction = await stake(amountToStake);
      
      const response = await signAndSubmitTransaction(transaction);
      
      console.log('Stake transaction:', response);
      alert('USDC staked successfully!');
      
      // Refresh staking balance
      const accountAddress = account.address.bcsToHex().toString();
      const balance = await getStakingBalance(accountAddress);
      setStakingBalance(balance);
      
      // Clear form
      setStakeAmount('');
      
    } catch (error) {
      console.error('Failed to stake:', error);
      alert('Failed to stake USDC');
    } finally {
      setLoading(false);
    }
  };

  const handleUnstake = async () => {
    if (!connected || !unstakeAmount || !isValidUnstakeAmount) {
      alert('Please connect wallet and enter a valid amount');
      return;
    }

    setLoading(true);
    try {
      const amountToUnstake = parseCurrency(unstakeAmount);
      const transaction = await unstake(amountToUnstake);
      
      const response = await signAndSubmitTransaction(transaction);
      
      console.log('Unstake transaction:', response);
      alert('USDC unstaked successfully!');
      
      // Refresh staking balance
      const accountAddress = account.address.bcsToHex().toString();
      const balance = await getStakingBalance(accountAddress);
      setStakingBalance(balance);
      
      // Clear form
      setUnstakeAmount('');
      
    } catch (error) {
      console.error('Failed to unstake:', error);
      alert('Failed to unstake USDC');
    } finally {
      setLoading(false);
    }
  };

  return (
    <main className="internal-page-content staking-page">
      <div className="staking-container">
        {/* Breadcrumb navigation */}
        <div className="breadcrumb-nav">
          <div className="breadcrumb-items">
            <span className="breadcrumb-item">Earn</span>
            <span className="breadcrumb-separator">›</span>
            <span className="breadcrumb-item active">Staking</span>
          </div>
          <span className="live-indicator">
            <span className="live-dot"></span>
            Live
          </span>
        </div>

        <h1 className="page-header">USDC Staking</h1>
        <p className="hero-subtitle wide">
          Stake your USDC to earn a share of the platform's earnings. Your staked tokens help provide liquidity to the 
          protocol by taking the other side of option and volatility positions. Earn platform fees and trading profits proportional to your stake.
        </p>

        {/* Main content area */}
        <div className="main-content-grid">
          {/* Staking Stats Section */}
          <div className="stats-section">
            <div className="stats-card">
              <div className="stats-header">
                <h3>Your Staking Position</h3>
              </div>
              <div className="stats-content">
                <div className="stat-item">
                  <span className="stat-label">Initial Staked</span>
                  <span className="stat-value">
                    {!connected ? 'Connect Wallet' : 
                     stakingBalance !== null ? `${stakingBalance.initialStakingAmount?.toLocaleString() || 0} USDC` : 'Loading...'}
                  </span>
                </div>
                <div className="stat-item">
                  <span className="stat-label">Claimable Amount</span>
                  <span className="stat-value">
                    {!connected ? 'Connect Wallet' : 
                     stakingBalance !== null ? `${stakingBalance.currentStakingAmount?.toLocaleString() || 0} USDC` : 'Loading...'}
                  </span>
                </div>
                <div className="stat-item">
                  <span className="stat-label">Total Staked</span>
                  <span className="stat-value">
                    {!connected ? 'Connect Wallet' : 
                     stakingBalance !== null ? `${stakingBalance.currentStakingAmount?.toLocaleString() || 0} USDC` : 'Loading...'}
                  </span>
                </div>
              </div>
            </div>

            <div className="stats-card">
              <div className="stats-header">
                <h3>Platform Metrics</h3>
              </div>
              <div className="stats-content">
                <div className="stat-item">
                  <span className="stat-label">APY</span>
                  <span className="stat-value highlight">12.5%</span>
                </div>
                <div className="stat-item">
                  <span className="stat-label">Total Volume (24h)</span>
                  <span className="stat-value">$2,847,392</span>
                </div>
                <div className="stat-item">
                  <span className="stat-label">Active Stakers</span>
                  <span className="stat-value">1,247</span>
                </div>
              </div>
            </div>
          </div>

          {/* Staking Panel */}
          <div className="staking-panel">
            <div className="panel-header">
              <div className="tab-buttons">
                <button 
                  className={`tab-btn ${activeTab === 'stake' ? 'active' : ''}`}
                  onClick={() => setActiveTab('stake')}
                >
                  Stake
                </button>
                <button 
                  className={`tab-btn ${activeTab === 'unstake' ? 'active' : ''}`}
                  onClick={() => setActiveTab('unstake')}
                >
                  Unstake
                </button>
              </div>
            </div>

            {activeTab === 'stake' && (
              <div className="trade-section">
                <div className="section-header">
                  <span>Amount to Stake</span>
                  <button className="max-btn" onClick={handleMaxStake}>MAX</button>
                </div>
                <div className={`input-group ${!isValidStakeAmount ? 'invalid' : ''}`}>
                  <div className="token-select">
                    <img src="/usdc.webp" alt="USDC" className="token-icon" />
                    <span>USDC</span>
                  </div>
                  <input 
                    type="text" 
                    className="amount-input" 
                    placeholder="$0.00"
                    value={stakeAmount}
                    onChange={handleStakeAmountChange}
                    disabled={loading}
                  />
                </div>
                {!isValidStakeAmount && (
                  <div className="input-error">Please enter a valid amount</div>
                )}

                <div className="action-buttons">
                  <button 
                    className="action-btn primary full-width" 
                    onClick={handleStake}
                    disabled={!connected || !stakeAmount || !isValidStakeAmount || loading}
                  >
                    {loading ? 'Staking...' : 'Stake USDC'}
                  </button>
                </div>
              </div>
            )}

            {activeTab === 'unstake' && (
              <div className="trade-section">
                <div className="section-header">
                  <span>Amount to Unstake</span>
                  <button 
                    className="max-btn" 
                    onClick={handleMaxUnstake}
                    disabled={!stakingBalance || !stakingBalance.currentStakingAmount || stakingBalance.currentStakingAmount === 0}
                  >
                    MAX
                  </button>
                </div>
                <div className={`input-group ${!isValidUnstakeAmount ? 'invalid' : ''}`}>
                  <div className="token-select">
                    <img src="/usdc.webp" alt="USDC" className="token-icon" />
                    <span>USDC</span>
                  </div>
                  <input 
                    type="text" 
                    className="amount-input" 
                    placeholder="$0.00"
                    value={unstakeAmount}
                    onChange={handleUnstakeAmountChange}
                    disabled={loading}
                  />
                </div>
                {!isValidUnstakeAmount && (
                  <div className="input-error">Please enter a valid amount</div>
                )}

                <div className="action-buttons">
                  <button 
                    className="action-btn secondary full-width" 
                    onClick={handleUnstake}
                    disabled={!connected || !unstakeAmount || !isValidUnstakeAmount || loading || !stakingBalance || !stakingBalance.currentStakingAmount || stakingBalance.currentStakingAmount === 0}
                  >
                    {loading ? 'Unstaking...' : 'Unstake USDC'}
                  </button>
                </div>
              </div>
            )}

            {/* Information Section */}
            <div className="info-section">
              <h4>How Staking Works</h4>
              <ul className="info-list">
                <li>Stake USDC to earn a share of platform trading fees</li>
                <li>Rewards are distributed proportionally to your stake</li>
                <li>You can unstake your tokens at any time</li>
                <li>Staking helps provide liquidity to the protocol</li>
              </ul>
            </div>
          </div>
        </div>
      </div>
    </main>
  );
}

export default StakingPage;
