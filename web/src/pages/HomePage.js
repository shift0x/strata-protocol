import React from 'react';
import './HomePage.css';

function Home() {
  return (
    <main className="main-content">
      <div className="hero-section">
        <h1 className="hero-title">
          On-chain option<br />
          <span className="hero-title-secondary">money legos</span>
        </h1>
        <p className="hero-subtitle">
          Trade volatility, hedge risk, and build advanced financial products with trustless option markets on Aptos
        </p>
        
        <div className="hero-cta">
          <button className="cta-primary">Enter App</button>
          <button className="cta-secondary">Developer Documentation</button>
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
            <div className="stats-number">4</div>
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
          <h2 className="featured-title">Intent-Based Trade Execution</h2>
          <p className="featured-description">
            Submit trading intents and let keepers execute your trades using real-time oracle data. Earn fees by providing execution services to the network.
          </p>
        </div>
      </div>
    </main>
  );
}

export default Home;
