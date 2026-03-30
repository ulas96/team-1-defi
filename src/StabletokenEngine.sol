// SPDX-License-Identifier: MIT

pragma solidity ^0.8.29;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Stabletoken} from "./Stabletoken.sol";
import {Oracle, AggregatorV3Interface} from "./library/Oracle.sol";

/// @title StabletokenEngine
/// @notice Core engine for the collateral-backed stablecoin system. Manages collateral deposits,
///         SBT minting/burning, and liquidations while enforcing a 200% collateralization ratio.
/// @dev Owns the Stabletoken contract and is the only address authorized to mint/burn SBT.
///      Uses a Chainlink price feed to value collateral in USD.
contract StabletokenEngine is ReentrancyGuard {
    // Errors

    /// @notice Thrown when a zero amount is passed to a function that requires a non-zero value.
    error StabletokenEngine__ZeroAmount();
    /// @notice Thrown when an ERC20 transfer returns false.
    error StabletokenEngine__TransferFailed();
    /// @notice Thrown when an operation would leave the caller's health factor below 1e18.
    error StabletokenEngine__BrokenHealthFactor();
    /// @notice Thrown when attempting to liquidate a position whose health factor is healthy.
    error StabletokenEngine__HealthFactorNotBroken();
    /// @notice Thrown when the Stabletoken mint call returns false.
    error StabletokenEngine__MintFailed();

    //Modifiers

    /// @dev Reverts with `StabletokenEngine__ZeroAmount` if `amount` is 0.
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) revert StabletokenEngine__ZeroAmount();
        _;
    }

    // Constants

    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant DECIMAL_PRECISION = 1e8;

    // State Variables

    using Oracle for AggregatorV3Interface;

    Stabletoken private immutable sbt;

    AggregatorV3Interface private immutable priceFeed;

    address private immutable collateralToken;

    mapping(address user => uint256 amount) private deposited;

    mapping(address user => uint256 amount) private minted;

    // Events

    /// @notice Emitted when a user deposits collateral.
    /// @param user The address of the depositor.
    /// @param amount The amount of collateral tokens deposited.
    event Deposit(address indexed user, uint256 indexed amount);

    /// @notice Emitted when a user withdraws collateral.
    /// @param user The address of the withdrawer.
    /// @param amount The amount of collateral tokens withdrawn.
    event Withdraw(address indexed user, uint256 indexed amount);

    // Functions

    /// @notice Deploys the engine and links it to a collateral token, price feed, and stablecoin.
    /// @param _collateralToken ERC20 token accepted as collateral.
    /// @param _priceFeed Chainlink-compatible price feed for the collateral/USD pair (8 decimals).
    /// @param stabletokenAddress Address of the Stabletoken contract owned by this engine.
    constructor(address _collateralToken, address _priceFeed, address stabletokenAddress) {
        collateralToken = _collateralToken;
        priceFeed = AggregatorV3Interface(_priceFeed);
        sbt = Stabletoken(stabletokenAddress);
    }

    // Public Functions

    /// @notice Deposits collateral into the engine on behalf of the caller.
    /// @dev Requires prior ERC20 approval of `amount` to this contract.
    /// @param amount The amount of collateral tokens to deposit.
    function deposit(uint256 amount) public moreThanZero(amount) nonReentrant {
        deposited[msg.sender] += amount;

        emit Deposit(msg.sender, amount);

        bool success = IERC20(collateralToken).transferFrom(msg.sender, address(this), amount);
        if (!success) revert StabletokenEngine__TransferFailed();
    }

    /// @notice Mints SBT stablecoins against the caller's deposited collateral.
    /// @dev Reverts if minting would break the caller's health factor (below 1e18).
    /// @param amount The amount of SBT to mint (18 decimals).
    function mint(uint256 amount) public moreThanZero(amount) nonReentrant {
        minted[msg.sender] += amount;
        if (!_checkHealthFactor(msg.sender)) revert StabletokenEngine__BrokenHealthFactor();

        bool success = sbt.mint(msg.sender, amount);
        if (!success) revert StabletokenEngine__MintFailed();
    }

    /// @notice Burns SBT stablecoins to reduce the caller's minted debt.
    /// @dev Requires prior ERC20 approval of `amount` to this contract.
    ///      Reverts if burning somehow still leaves health factor broken (edge case guard).
    /// @param amount The amount of SBT to burn (18 decimals).
    function burn(uint256 amount) public moreThanZero(amount) nonReentrant {
        minted[msg.sender] -= amount;
        if (!_checkHealthFactor(msg.sender)) revert StabletokenEngine__BrokenHealthFactor();

        bool success = sbt.transferFrom(msg.sender, address(this), amount);
        if (!success) revert StabletokenEngine__TransferFailed();

        sbt.burn(amount);
    }

    /// @notice Liquidates an undercollateralized position, paying off its SBT debt in exchange for its collateral.
    /// @dev The caller must hold and approve at least `minted[user]` SBT to this contract.
    ///      The entire collateral balance is transferred to the caller as the liquidation incentive.
    /// @param user The address of the undercollateralized account to liquidate.
    function liquidate(address user) public nonReentrant {
        if (_checkHealthFactor(user)) revert StabletokenEngine__HealthFactorNotBroken();

        uint256 collateralDebt = deposited[user];
        uint256 sbtDebt = minted[user];

        deposited[user] = 0;
        minted[user] = 0;

        bool successSbt = sbt.transferFrom(msg.sender, address(this), sbtDebt);
        if (!successSbt) revert StabletokenEngine__TransferFailed();

        bool successCollateral = IERC20(collateralToken).transfer(msg.sender, collateralDebt);
        if (!successCollateral) revert StabletokenEngine__TransferFailed();

        sbt.burn(sbtDebt);
    }

    /// @notice Withdraws collateral from the engine back to the caller.
    /// @dev Reverts if withdrawal would break the caller's health factor.
    /// @param amount The amount of collateral tokens to withdraw.
    function withdraw(uint256 amount) public moreThanZero(amount) nonReentrant {
        deposited[msg.sender] -= amount;

        emit Withdraw(msg.sender, amount);

        if (!_checkHealthFactor(msg.sender)) revert StabletokenEngine__BrokenHealthFactor();

        bool success = IERC20(collateralToken).transfer(msg.sender, amount);
        if (!success) revert StabletokenEngine__TransferFailed();
    }

    // Public View Functions

    /// @notice Returns the USD value of a given amount of collateral tokens.
    /// @param amount The collateral amount to value (in collateral token decimals).
    /// @return The USD value with 18 decimals of precision.
    function getCollateralValueInUsd(uint256 amount) public view returns (uint256) {
        return _getCollateralValueInUsd(amount);
    }

    /// @notice Returns the health factor of a user's position.
    /// @dev A value >= 1e18 is healthy. Returns `type(uint256).max` when no SBT is minted.
    /// @param user The address to check.
    /// @return The health factor scaled by 1e18.
    function getHealthFactor(address user) public view returns (uint256) {
        return _getHealthFactor(user);
    }

    // Private View Functions

    /// @dev Fetches the latest price from the Chainlink oracle and converts `amount` to USD.
    /// @param amount Collateral amount in collateral token decimals.
    /// @return USD value with 18 decimals of precision.
    function _getCollateralValueInUsd(uint256 amount) private view returns (uint256) {
        (, int256 price,,,) = priceFeed.getOraclePrice();
        return (uint256(price) * amount) / DECIMAL_PRECISION;
    }

    /// @dev Computes health factor as: (collateralUSD * PRECISION * LIQUIDATION_THRESHOLD) / (minted * LIQUIDATION_PRECISION).
    ///      A result >= 1e18 means the position is adequately collateralized.
    /// @param user The address to evaluate.
    /// @return Health factor scaled by 1e18, or `type(uint256).max` if no debt.
    function _getHealthFactor(address user) private view returns (uint256) {
        uint256 userDeposit = deposited[user];
        uint256 userMint = minted[user];

        if (userMint == 0) return type(uint256).max;

        return _getCollateralValueInUsd(userDeposit) * PRECISION * LIQUIDATION_THRESHOLD
            / (userMint * LIQUIDATION_PRECISION);
    }

    /// @dev Returns true if the user's health factor is >= 1e18 (position is healthy).
    /// @param user The address to check.
    /// @return True if healthy, false if undercollateralized.
    function _checkHealthFactor(address user) private view returns (bool) {
        return _getHealthFactor(user) >= PRECISION;
    }
}
