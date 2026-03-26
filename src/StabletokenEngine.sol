// SPDX-License-Identifier: MIT

pragma solidity ^0.8.29;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Stabletoken} from "./Stabletoken.sol";

contract StabletokenEngine is ReentrancyGuard {
    // Errors
    error StabletokenEngine__ZeroAmount();
    error StabletokenEngine__NotCollateral(address token);
    error StabletokenEngine__CollateralTokenAddressesAndPriceFeedsAddressesDontMatch();
    error StabletokenEngine__TransferFailed();

    //Modifiers

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) revert StabletokenEngine__ZeroAmount();
        _;
    }

    modifier isCollateral(address token) {
        if (priceFeeds[token] == address(0)) revert StabletokenEngine__NotCollateral(token);
        _;
    }

    // mint()
    // burn()
    // liquidate()
    // redeem()

    // State Variables

    Stabletoken private immutable sbt;

    mapping(address collateral => address priceFeed) private priceFeeds;

    mapping(address user => mapping(address collateral => uint256 amount)) private deposited;

    mapping(address user => uint256 amount) private minted;

    address[] private collateralTokens;

    // Events
    event Deposit(address indexed user, address indexed token, uint256 indexed amount);

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
}
