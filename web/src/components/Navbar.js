import React from 'react';
import { Link, useLocation } from 'react-router-dom';
import { WalletSelector } from "@aptos-labs/wallet-adapter-ant-design";
import { useWallet } from "@aptos-labs/wallet-adapter-react";
import "@aptos-labs/wallet-adapter-ant-design/dist/index.css";
import './Navbar.css';

function Navbar() {
  const location = useLocation();
  const isHomePage = location.pathname === '/';
  const { connected } = useWallet();

  return (
    <nav className="navbar">
      <div className="navbar-content">
        <div className="navbar-logo">
          <Link to="/">
            <img src="/logo.png" alt="Strata Protocol" className="logo-image" />
          </Link>
        </div>
        
        {!isHomePage && (
          <div className="navbar-nav">
            <Link 
              to="/markets" 
              className={`nav-link ${location.pathname === '/markets' ? 'active' : ''}`}
            >
              Volatility Markets
            </Link>
            <Link 
              to="/options" 
              className={`nav-link ${location.pathname === '/options' ? 'active' : ''}`}
            >
              Options
            </Link>
          </div>
        )}
        
        {isHomePage ? (
          <Link to="/markets">
            <button className="enter-app-btn">
              Enter App →
            </button>
          </Link>
        ) : (
          <div className={`wallet-selector-container ${!connected ? 'disconnected' : ''}`}>
            <WalletSelector />
          </div>
        )}
      </div>
    </nav>
  );
}

export default Navbar;
