// SPDX-License-Identifier: MIT

pragma solidity ^0.8.29;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Stabletoken} from "./Stabletoken.sol";
import {Oracle, AggregatorV3Interface} from "./library/Oracle.sol";

contract StabletokenEngine is ReentrancyGuard {
    // Errors

    error StabletokenEngine__ZeroAmount();
    error StabletokenEngine__NotCollateral(address token);
    error StabletokenEngine__CollateralTokenAddressesAndPriceFeedsAddressesDontMatch();
    error StabletokenEngine__TransferFailed();
    error StabletokenEngine__BrokenHealthFactor();
    error StabletokenEngine__MintFailed();

    //Modifiers

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) revert StabletokenEngine__ZeroAmount();
        _;
    }

    // liquidate()
    // redeem()

    // Constants

    uint256 PRECISION = 1e18;
    uint256 LIQUIDATION_THRESHOLD = 50;
    uint256 LIQUIDATION_PRECISION = 100;

    // State Variables

    using Oracle for AggregatorV3Interface;

    Stabletoken private immutable sbt;

    AggregatorV3Interface private immutable priceFeed;

    address private immutable collateralToken;

    mapping(address user => uint256 amount) private deposited;

    mapping(address user => uint256 amount) private minted;

    // Events

    event Deposit(address indexed user, address indexed token, uint256 indexed amount);

    // Functions

    constructor(address _collateralToken, address _priceFeed, address stabletokenAddress) {
        collateralToken = _collateralToken;
        priceFeed = AggregatorV3Interface(_priceFeed);
        sbt = Stabletoken(stabletokenAddress);
    }

    // Public Functions

    function deposit(uint256 amount) public moreThanZero(amount) nonReentrant {
        deposited[msg.sender] += amount;
        emit Deposit(msg.sender, collateralToken, amount);
        bool success = IERC20(collateralToken).transferFrom(msg.sender, address(this), amount);
        if (!success) revert StabletokenEngine__TransferFailed();
    }

    function mint(uint256 amount) public moreThanZero(amount) nonReentrant {
        minted[msg.sender] += amount;
        if (_checkHealthFactor(msg.sender)) {
            revert StabletokenEngine__BrokenHealthFactor();
        }

        bool success = sbt.mint(msg.sender, amount);
        if (!success) {
            revert StabletokenEngine__MintFailed();
        }
    }

    function burn(uint256 amount) public moreThanZero(amount) {
        _burn(amount);
    }

    function liquidate() public {}

    function withdraw() public {}

    // Public View Functions

    function getCollateralPrice() public view returns (uint256) {
        return _getCollateralPrice();
    }

    function getCollateralValueInUsd(uint256 amount) public view returns (uint256) {
        return _getCollateralValueInUsd(amount);
    }

    function getHealthFactor(address user) public view returns (uint256) {
        return _getHealthFactor(user);
    }

    // Private Functions

    function _burn(uint256 amount, address onBehalf, address from) private {
        minted[onBehalf] -= amount;

        bool success = sbt.transferFrom(from, address(this), amount);

        if (!success) {
            revert StabletokenEngine__TransferFailed();
        }

        sbt.burn(amount);
    }

    // Private View Functions

    function _getCollateralPrice() private view returns (uint256) {
        (, int256 price,,,) = priceFeed.getOraclePrice();
        return (uint256(price));
    }

    function _getCollateralValueInUsd(uint256 amount) private view returns (uint256) {
        return _getCollateralPrice() * amount;
    }

    function _getHealthFactor(address user) private view returns (uint256) {
        uint256 userDeposit = deposited[user];
        uint256 userMint = minted[user];

        return _getCollateralValueInUsd(userDeposit) * PRECISION * LIQUIDATION_THRESHOLD
            / (userMint * LIQUIDATION_PRECISION);
    }

    function _checkHealthFactor(address user) private view returns (bool) {
        return _getHealthFactor(user) >= PRECISION;
    }
}
