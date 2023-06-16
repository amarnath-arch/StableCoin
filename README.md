# StableCoin 
Contracts which implements Stable Coin loosely based On MakerDAO System. Intended to make it similar to the 
DAI Stable Coin. Similar to DAI if DAI has no governance,no fees and was only backed by WETH and WBTC.

## Properties of this StableCoin:
1. Relative Stable Coin: Pegged / Anchored --> $1.00
    1. Chainlink Price Feed
    2. Set a function to exchange ETH & BTC ----> $$$
2. Stability Mechanism (Minting) : Algorithmic (Decentralized)
    1. People can only mint the stable coin with enough collateral (coded)
3. Collateral Type: Exogenous (Crypto)
    1. wETH
    2. wBTC

```
1. Our DSC System should be overcollateralized. At no point, should the value of all the collateral <= $ backed value of all the DSC.
2. The contract is the core of the DSC system.It handles all the logic for mining and redeeming DSC, as well as depositing & withdrawing collateral.

```

## What It is intended to do?
1. Deposit the collateral
2. Mint the Decentralized Stable Coin Mainting the Health Factor.
    1. If the Liquidations threshold is 50% i.e the protocol is 200% overcollateralized.
    2. Health Factor can be calculated by:
    ```
    HealthFactor = (((CollateralValueInUsd * LIQUIDATIONThreshold)/ 100) * PRECISION ) / (Total DSC Minted);

    CollateralValue in USD -----> Value of WETH and WBTC deposited in USD;
    LIQUIDATIONTHRESHOLD --------> Below which the collateral will get Liquidated.
    PRECISION  -------------------> Denotes the MIN_HEALTH_FACTOR 
    TotalDscMinted ---------------> TotalDscMinted by the user.

    ```
3. If the Health of the user stoops below the MIN_HEALTH_FACTOR the user's position can get
    liquidated.
4. Liquidators can earn bonus by liquidating others user's position maintaining their own health factor.