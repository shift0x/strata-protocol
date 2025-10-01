import React from 'react';
import { Link, useLocation } from 'react-router-dom';

function Navbar() {
  const location = useLocation();
  const isHomePage = location.pathname === '/';

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
        
        <button className="enter-app-btn">
          Enter App →
        </button>
      </div>
    </nav>
  );
}

export default Navbar;
