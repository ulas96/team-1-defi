# SBT Stablecoin

A collateral-backed stablecoin system built on Solidity with Foundry. Users deposit ERC-20 collateral (e.g. WAVAX), and mint **SBT** stablecoins against it at a **200% collateralization ratio**, using a Chainlink price feed for real-time USD valuation. Under-collateralized positions can be liquidated by any participant.

## How It Works

```
User ──deposit(collateral)──► StabletokenEngine ──transferFrom──► holds collateral
User ──mint(sbtAmount)──────► StabletokenEngine ──sbt.mint──────► SBT tokens to user
User ──burn(sbtAmount)──────► StabletokenEngine ──sbt.burn──────► destroys SBT, reduces debt
User ──withdraw(amount)─────► StabletokenEngine ──transfer──────► collateral back to user
Anyone ─liquidate(user)─────► StabletokenEngine ──seize──────────► collateral to liquidator, debt cleared
```

### Core Rules

- **200% collateralization**: you can only mint SBT up to 50% of your collateral's USD value
- **Health factor**: `(collateralUSD * 50%) / mintedSBT` must stay >= 1.0 after every operation
- **Liquidation**: if a position's health factor drops below 1.0, anyone can pay off the debt and claim all collateral
- **Oracle safety**: the Chainlink price feed has a 3-hour staleness check — reverts if the price is stale

## Contracts

| Contract                    | Description                                                                                                                 |
| --------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| `src/Stabletoken.sol`       | ERC-20 stablecoin token (SBT). Extends `ERC20Burnable` + `Ownable`. Only the owner (the engine) can mint/burn.              |
| `src/StabletokenEngine.sol` | Core engine. Manages deposits, withdrawals, minting, burning, and liquidations. Owns `Stabletoken`. Uses `ReentrancyGuard`. |
| `src/library/Oracle.sol`    | Library wrapping `AggregatorV3Interface.latestRoundData()` with staleness validation (3-hour timeout).                      |
| `script/Deploy.s.sol`       | Deployment script. Deploys both contracts, transfers SBT ownership to the engine.                                           |

## Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) installed

### Clone

```bash
git clone --recurse-submodules https://github.com/ulas96/team-1-defi.git
cd team-1-defi
```

If you already cloned without submodules:

```bash
git submodule update --init --recursive
```

### Build

```bash
forge build
```

### Test

```bash
forge test -vvv
```

Run a specific test file or function:

```bash
forge test --match-path test/StabletokenEngineDepositTest.t.sol -vvv
forge test --match-test testDepositSuccessTransfersTokens -vvv
```

### Format

```bash
forge fmt
```

### Gas Snapshot

```bash
forge snapshot
```

## Deployment

The deploy script reads two environment variables:

| Variable          | Description                                             |
| ----------------- | ------------------------------------------------------- |
| `WAVAX_ADDRESS`   | Address of the WAVAX (or other collateral) ERC-20 token |
| `AVAX_PRICE_FEED` | Address of the Chainlink AVAX/USD price feed            |

```bash
forge script script/Deploy.s.sol:Deploy \
  --rpc-url <RPC_URL> \
  --private-key <PRIVATE_KEY> \
  --broadcast
```

The script deploys `Stabletoken`, then `StabletokenEngine`, and transfers SBT ownership to the engine.

## Test Suite

Tests use mock contracts (`MockERC20`, `MockPriceFeed`) to simulate collateral tokens and price feeds without external dependencies.

| Test File                              | Covers                                                                                                                       |
| -------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| `StabletokenEngineDepositTest.t.sol`   | Deposit: token transfer, events, accumulation, zero-amount revert, transfer failure, missing approval                        |
| `StabletokenEngineMintTest.t.sol`      | Mint: token issuance, health factor enforcement, accumulation, reverts for zero amount / no collateral / exceeding threshold |
| `StabletokenEngineBurnTest.t.sol`      | Burn: debt reduction, SBT destruction, health factor post-burn                                                               |
| `StabletokenEngineWithdrawTest.t.sol`  | Withdraw: token return, events, partial withdrawal, reverts for zero amount / broken health factor / failed transfer         |
| `StabletokenEngineLiquidateTest.t.sol` | Liquidate: collateral seizure, debt clearing, SBT burn, reverts when health factor is healthy or liquidator has no SBT       |

## CI

GitHub Actions (`.github/workflows/test.yml`) runs on every push and PR:

1. `forge fmt --check` — enforce formatting
2. `forge build --sizes` — compile and report contract sizes
3. `forge test -vvv` — run all tests

## Dependencies

Managed as git submodules in `lib/`:

- **forge-std** — Foundry test utilities
- **openzeppelin-contracts** — ERC-20, Ownable, ReentrancyGuard
- **chainlink-brownie-contracts** — `AggregatorV3Interface` for price feeds

Remappings in `foundry.toml`:

```toml
remappings = [
    '@openzeppelin/contracts=lib/openzeppelin-contracts/contracts',
    '@chainlink/contracts/=lib/chainlink-brownie-contracts/contracts/',
]
```

## License

MIT
