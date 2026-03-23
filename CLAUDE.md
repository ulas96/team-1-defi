# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Build
forge build

# Build with contract sizes
forge build --sizes

# Run all tests (verbose)
forge test -vvv

# Run a single test file
forge test --match-path test/MyTest.t.sol -vvv

# Run a single test function
forge test --match-test testFunctionName -vvv

# Format code
forge fmt

# Check formatting (CI)
forge fmt --check

# Gas snapshot
forge snapshot
```

## Architecture

This is a Foundry-based DeFi project implementing a collateral-backed stablecoin system with two contracts:

- **`src/Stabletoken.sol`** — The ERC20 stablecoin token (symbol: SBT). Extends OpenZeppelin's `ERC20Burnable` and `Ownable`. Only the owner (expected to be `StabletokenEngine`) can mint and burn tokens.

- **`src/StabletokenEngine.sol`** — The engine/controller contract (currently a stub). This is intended to hold the core logic: collateral management, Chainlink price feeds, minting/burning via the Stabletoken contract, and liquidation mechanics.

The intended ownership flow: `StabletokenEngine` owns `Stabletoken` so it controls token supply in response to collateral operations.

## Dependencies

Managed as git submodules in `lib/`:
- `forge-std` — Foundry testing utilities
- `openzeppelin-contracts` — ERC20, Ownable, etc.
- `chainlink-brownie-contracts` — Chainlink price feed interfaces (not yet used)

Import paths configured in `foundry.toml`:
- `@openzeppelin/contracts` → `lib/openzeppelin-contracts/contracts`
- `@chainlink/contracts/` → `lib/chainlink-brownie-contracts/contracts/`

## CI

GitHub Actions (`.github/workflows/test.yml`) runs on push/PR:
1. `forge fmt --check`
2. `forge build --sizes`
3. `forge test -vvv`
