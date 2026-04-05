// SPDX-License-Identifier: MIT

pragma solidity ^0.8.29;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Stabletoken} from "./Stabletoken.sol";
import {Oracle, AggregatorV3Interface} from "./library/Oracle.sol";

/// @title StabletokenEngine
/// @notice Core engine for the multi-collateral stablecoin system. Manages collateral deposits,
///         SBT minting/burning, and liquidations while enforcing a 200% collateralization ratio.
/// @dev Owns the Stabletoken contract and is the only address authorized to mint/burn SBT.
///      Uses Chainlink price feeds to value each collateral type in USD.
contract StabletokenEngine is ReentrancyGuard {
    // Errors
    error StabletokenEngine__ZeroAmount();
    error StabletokenEngine__NotCollateral(address token);
    error StabletokenEngine__CollateralTokenAddressesAndPriceFeedsAddressesDontMatch();
    error StabletokenEngine__TransferFailed();
    error StabletokenEngine__BrokenHealthFactor();
    error StabletokenEngine__HealthFactorNotBroken();
    error StabletokenEngine__MintFailed();

    //Modifiers

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) revert StabletokenEngine__ZeroAmount();
        _;
    }

    modifier isCollateral(address token) {
        if (priceFeeds[token] == address(0)) revert StabletokenEngine__NotCollateral(token);
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

    mapping(address collateral => address priceFeed) private priceFeeds;

    mapping(address user => mapping(address collateral => uint256 amount)) private deposited;

    mapping(address user => uint256 amount) private minted;

    address[] private collateralTokens;

    // Events
    event Deposit(address indexed user, address indexed token, uint256 indexed amount);
    event Withdraw(address indexed user, address indexed token, uint256 indexed amount);

    // Functions

    constructor(
        address[] memory collateralTokenAddresses,
        address[] memory priceFeedAddresses,
        address stabletokenAddress
    ) {
        if (collateralTokenAddresses.length != priceFeedAddresses.length) {
            revert StabletokenEngine__CollateralTokenAddressesAndPriceFeedsAddressesDontMatch();
        }

        for (uint256 i = 0; i < collateralTokenAddresses.length; i++) {
            priceFeeds[collateralTokenAddresses[i]] = priceFeedAddresses[i];
            collateralTokens.push(collateralTokenAddresses[i]);
        }

        sbt = Stabletoken(stabletokenAddress);
    }

    // Public Functions

    function deposit(address collateralToken, uint256 amount)
        public
        moreThanZero(amount)
        isCollateral(collateralToken)
        nonReentrant
    {
        deposited[msg.sender][collateralToken] += amount;
        emit Deposit(msg.sender, collateralToken, amount);
        bool success = IERC20(collateralToken).transferFrom(msg.sender, address(this), amount);
        if (!success) revert StabletokenEngine__TransferFailed();
    }

    function mint(uint256 amount) public moreThanZero(amount) nonReentrant {
        minted[msg.sender] += amount;
        if (!_checkHealthFactor(msg.sender)) revert StabletokenEngine__BrokenHealthFactor();

        bool success = sbt.mint(msg.sender, amount);
        if (!success) revert StabletokenEngine__MintFailed();
    }

    function burn(uint256 amount) public moreThanZero(amount) nonReentrant {
        minted[msg.sender] -= amount;
        if (!_checkHealthFactor(msg.sender)) revert StabletokenEngine__BrokenHealthFactor();

        bool success = sbt.transferFrom(msg.sender, address(this), amount);
        if (!success) revert StabletokenEngine__TransferFailed();

        sbt.burn(amount);
    }

    function withdraw(address collateralToken, uint256 amount)
        public
        moreThanZero(amount)
        isCollateral(collateralToken)
        nonReentrant
    {
        deposited[msg.sender][collateralToken] -= amount;

        emit Withdraw(msg.sender, collateralToken, amount);

        if (!_checkHealthFactor(msg.sender)) revert StabletokenEngine__BrokenHealthFactor();

        bool success = IERC20(collateralToken).transfer(msg.sender, amount);
        if (!success) revert StabletokenEngine__TransferFailed();
    }

    function liquidate(address user) public nonReentrant {
        if (_checkHealthFactor(user)) revert StabletokenEngine__HealthFactorNotBroken();

        uint256 sbtDebt = minted[user];
        minted[user] = 0;

        bool successSbt = sbt.transferFrom(msg.sender, address(this), sbtDebt);
        if (!successSbt) revert StabletokenEngine__TransferFailed();

        sbt.burn(sbtDebt);

        for (uint256 i = 0; i < collateralTokens.length; i++) {
            address token = collateralTokens[i];
            uint256 amount = deposited[user][token];
            if (amount == 0) continue;
            deposited[user][token] = 0;
            bool success = IERC20(token).transfer(msg.sender, amount);
            if (!success) revert StabletokenEngine__TransferFailed();
        }
    }

    // Public View Functions

    function getCollateralValueInUsd(address token, uint256 amount) public view returns (uint256) {
        return _getCollateralValueInUsd(token, amount);
    }

    function getTotalCollateralValueInUsd(address user) public view returns (uint256) {
        return _getTotalCollateralValueInUsd(user);
    }

    function getHealthFactor(address user) public view returns (uint256) {
        return _getHealthFactor(user);
    }

    // Private View Functions

    function _getCollateralValueInUsd(address token, uint256 amount) private view returns (uint256) {
        AggregatorV3Interface feed = AggregatorV3Interface(priceFeeds[token]);
        (, int256 price,,,) = feed.getOraclePrice();
        return (uint256(price) * amount) / DECIMAL_PRECISION;
    }

    function _getTotalCollateralValueInUsd(address user) private view returns (uint256) {
        uint256 totalValue = 0;
        for (uint256 i = 0; i < collateralTokens.length; i++) {
            address token = collateralTokens[i];
            uint256 amount = deposited[user][token];
            if (amount > 0) {
                totalValue += _getCollateralValueInUsd(token, amount);
            }
        }
        return totalValue;
    }

    function _getHealthFactor(address user) private view returns (uint256) {
        uint256 userMint = minted[user];
        if (userMint == 0) return type(uint256).max;

        uint256 totalCollateralUsd = _getTotalCollateralValueInUsd(user);
        return totalCollateralUsd * PRECISION * LIQUIDATION_THRESHOLD / (userMint * LIQUIDATION_PRECISION);
    }

    function _checkHealthFactor(address user) private view returns (bool) {
        return _getHealthFactor(user) >= PRECISION;
    }
}
