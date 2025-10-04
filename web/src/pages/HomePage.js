import React from 'react';
import { Link } from 'react-router-dom';

import './HomePage.css';

function Home() {
  return (
    <main className="main-content">
      <div className="hero-section">
        <h1 className="hero-title">
          Trustless On-Chain Options<br />
          <span className="hero-title-secondary">& Volatility Markets</span>
        </h1>
        <p className="hero-subtitle">
          Trade volatility, hedge risk, and build advanced financial products with trustless option markets on Aptos
        </p>
        
        <div className="hero-cta">
          <Link to="/markets">
            <button className="cta-primary">Enter App</button>
          </Link>
        </div>
      </div>

      {/* Featured Section */}
      <div className="featured-container">
        <div className="featured-section">
          <div className="featured-badge">MARKETS</div>
          <h2 className="featured-title">Volatility Prediction Markets</h2>
          <p className="featured-description">
            Trade volatility predictions to hedge risk or speculate on market uncertainty. Community forecasts feed directly into our trustless option pricing model.
          </p>
        </div>
        
        <div className="stats-panel">
          <div className="stats-top">
            <div className="stats-badge">LIVE</div>
            <div className="stats-number">3</div>
            <div className="stats-label">active markets</div>
          </div>
          <div className="stats-indicator">
            <span className="indicator-dot"></span>
            Live
          </div>
        </div>
      </div>

      {/* Option Pricing & Trade Execution Row */}
      <div className="modules-container">
        <div className="module-section">
          <div className="featured-badge">PRICING</div>
          <h2 className="featured-title">On-Chain Option Pricing Model</h2>
          <p className="featured-description">
            Trustless option valuation using binomial pricing models. Calculate fair prices and option greeks entirely on-chain for transparent, verifiable pricing.
          </p>
        </div>
        
        <div className="module-section">
          <div className="featured-badge">EXECUTION</div>
          <h2 className="featured-title">Trustless Order Execution</h2>
          <p className="featured-description">
            Liquidity from stakers enables instant execution of option and volatility trades. A (future) keeper network will validate pricing from Pyth price feeds trustless execution across all supported markets (1,000+).
          </p>
        </div>
      </div>

      <div className="modules-container">
        <div className="module-section">
          <div className="featured-badge">BUILDER</div>
          <h2 className="featured-title">Multi-Leg Strategy Builder</h2>
          <p className="featured-description">
            Create complex multi-leg option positions. Build spreads, straddles, and custom combinations across supported markets with on-chain pricing and risk calculations.
          </p>
        </div>
        
        <div className="module-section">
          <div className="featured-badge">PASSIVE EARNINGS</div>
          <h2 className="featured-title">USDC Staking Rewards</h2>
          <p className="featured-description">
            Stake USDC to earn from platform trading fees and profits. Your stake provides liquidity for option and volatility positions while earning proportional rewards from all protocol activity.
          </p>
        </div>
      </div>
    </main>
  );
}

export default Home;
