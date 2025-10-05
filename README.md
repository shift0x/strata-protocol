Options markets are a critical building block in traditional finance. They are used to hedge downside risk, speculate on price movement, profit from non-directional markets and bet on volatility expansion. However, to date on-chain option markets are underdeveloped and lacking in liquidity and usage.

Why?

Current implementations are not true money legos. The have private off-chain components that prevent developers from building applications on top of the protocols in a truly trustless manner.

Strata protocol aims to fix this by implementing the on-chain components required for option markets in a trustless way on aptos.

These components are:

- On Chain Option Pricing Models
- Transparent Volatility Inputs to Pricing Models
- Trustless Price Feeds
- Instant, Zero Slippage Execution (no matching or order book)

**Web Demo:** [https://strata-protocol-hazel.vercel.app/](https://strata-protocol-hazel.vercel.app/)

## Development Setup

### Prerequisites

- Node.js and npm/yarn
- Aptos CLI

### Running the Web Application

To run the React frontend locally:

```bash
cd web
npm install
npm start
```

The application will be available at `http://localhost:3000`.

Available scripts:
- `npm start` - Start development server
- `npm build` - Build for production

### Running Contract Tests

To run the Move contract tests:

```bash
cd contracts
aptos move test
```

To compile the contracts:

```bash
cd contracts
aptos move compile
```