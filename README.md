Options markets are a critical building block in traditional finance. They are used to hedge downside risk, speculate on price movement, profit from non-directional markets and bet on volatility expansion. However, to date on-chain option markets are underdeveloped and lacking in liquidity and usage.

Strata protocol aims to fix the core issues with current implementations of option markets and introduce the building blocks for a vibrant on-chain ecosystem for on-chain option markets on Aptos.

To accomplish this goal, the protocol introduces the following new primitives:

## Volatility Prediction Markets

Volatility is one of the core modules of accurate option pricing. In tradfi markets, makers use battle tested models to determine the correct volatility to input into pricing models like Black-Scholes to determine their bid/asks. The purpose of volatility prediction markets in this ecosystem is to emulate the role of these models and provide accurate volatility predictions that can be used as inputs to the option pricing model.

The goal of the market is to "predict" the realized volatility of an asset over a 30 day timespan. The market is settled at expiration using the close data provided by a pyth price oracle. The calculation for HV is done off-chain, and the calculation result and underlying datapoints are published on-chain.

**Notes & Details**

- Markets mint new tokens to represent the IV prediction. The open price for the tokens is the current HV.
- Participants can go long/short IV
- Shorting is supported by "borrowing" IV tokens, then selling them in the pool. Participants close the short position by buying back the owed IV tokens
- Short positions can be liquidated by anyone ones the health score is below the required threshold. The liquidator earns a fee for this service (future)

**Future Work**

Currently markets are settled using off-chain calculations of historical volatility. Participants need to trust that the market owner is not manipulating the data. In the future, we plan to push this calculation on-chain and instead use a keeper network to submit the datapoints from the pyth feed that will go into the calculation. The contract will ensure the datapoints provided are within the desired range and expected span to settle markets.


## On-Chain Option Pricing Model

The on-chain option pricing model is what allows for trustless execution of option contracts. On-chain pricing allows for developers to build financial products backed with options in a way that has yet to be explored on-chain.

In our implementation, the pricing model implements a [Binomial Option Pricing Model ](https://https://www.investopedia.com/terms/b/binomialoptionpricing.asp)which allows it to be implemented on-chain. The model takes standard inputs  (underlying price, strike price, option type, volatility, time to expiration) and computes the price of the option.

With the model, we also produce option greeks which will be useful for advanced traders or advanced applications that aim to have a specific exposure.

## Trustless Order Execution

When users or contracts wish to execute an option trade, the liquidity from stakers is used to take the other side of the trade. This allows instant execution for option and volatility market trades.

This functionality does open up the possibility of front-running orders. To mitigate this, the market charges 1% transaction fee and markets are currently limited to markets that are sponsored by Aptos, this ensures a 15s heartbeat.

**Future Work**

In the future, the plan is to implement a keeper network where intents are submitted on chain, capturing the asset to be traded and the required data feeds to do an accurate to the second pricing. Keepers will be responsible for publishing aptos price feeds to the execution contract, where it will check that the price update is within a given price threshold (~1.5sec).

The contract will then use this price data to do option pricing and execute trades.

This functionality would open up option trading and volatility markets on the entire collection of markets supported by Pyth.

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