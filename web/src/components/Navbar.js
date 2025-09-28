import React from 'react';

function Navbar() {
  return (
    <nav className="navbar">
      <div className="navbar-content">
        <div className="navbar-logo">
          <img src="/logo.png" alt="Strata Protocol" className="logo-image" />
        </div>
        <button className="enter-app-btn">
          Enter App →
        </button>
      </div>
    </nav>
  );
}

export default Navbar;
