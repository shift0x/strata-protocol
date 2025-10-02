import React from 'react';
import { BrowserRouter as Router, Routes, Route } from 'react-router-dom';
import { VolatilityMarketProvider } from './providers/VolatilityMarketProvider';
import Navbar from './components/Navbar';
import Home from './pages/HomePage';
import VolatilityMarket from './pages/VolatilityMarket';
import OptionsPage from './pages/OptionsPage';
import './App.css';
import { WalletProvider } from './providers/WalletProvider';

function App() {
  return (
    <WalletProvider>
      <VolatilityMarketProvider>
        <Router>
          <div className="App">
            <Navbar />
            <Routes>
              <Route path="/" element={<Home />} />
              <Route path="/markets" element={<VolatilityMarket />} />
              <Route path="/options" element={<OptionsPage />} />
            </Routes>
          </div>
        </Router>
      </VolatilityMarketProvider>
    </WalletProvider>
  );
}

export default App;
