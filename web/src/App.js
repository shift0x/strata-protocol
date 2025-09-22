import React from 'react';
import './App.css';

function App() {
  return (
    <div className="App">
      {/* Navigation */}
      <nav className="navbar">
        <div className="nav-container">
          <div className="nav-logo">
              <img src="/logo.png" width={175} />
          </div>
          <ul className="nav-menu">
            <li className="nav-item">
              <a href="#home" className="nav-link active">Home</a>
            </li>
            <li className="nav-item">
              <a href="#markets" className="nav-link">Markets</a>
            </li>
            <li className="nav-item">
              <a href="#dashboard" className="nav-link">Dashboard</a>
            </li>
          </ul>
          <button className="btn-primary text-sm">Connect Wallet</button>
        </div>
      </nav>

      {/* Hero Section */}
      <main className="main-content">
        <div className="hero-section">
          <h1 className="hero-title">
            Volatility Trading<br />
            Without The Complexity
          </h1>
          <p className="hero-subtitle">
            Protect your positions or speculate on price movements<br />
            without the complexities of options.
          </p>
          <button className="btn-primary">Get Started</button>
        </div>

        {/* Feature Cards */}
        <div className="features-section">
          <div className="feature-card liquidity-card">
            <div className="feature-background">
              <div className="feature-pattern"></div>
            </div>
            <div className="feature-content">
              <div className="feature-badge">Liquidity Providers</div>
              <h3 className="feature-title">Reduce Impermanent Loss</h3>
              <p className="feature-description">
                Purchase positions that gain value when volatility spikes, offsetting impermanent losses from your liquidity positions.
              </p>
            </div>
          </div>
          
          <div className="feature-card traders-card">
            <div className="feature-background">
              <div className="feature-pattern"></div>
            </div>
            <div className="feature-content">
              <div className="feature-badge">Traders</div>
              <h3 className="feature-title">Predict Volatility Not Price</h3>
              <p className="feature-description">
                Trade smarter. Predict volatility instead of predicting direction. Profit from prices moving more or less than the expected maket volatility.
              </p>
            </div>
          </div>
        </div>
      </main>
    </div>
  );
}

export default App;
