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

    // mint()
    // burn()
    // liquidate()
    // redeem()

    // State Variables

    Stabletoken private immutable sbt;

    address private immutable priceFeed;

    address private immutable collateralToken;

    mapping(address user => uint256 amount) private deposited;

    mapping(address user => uint256 amount) private minted;

    // Events
    event Deposit(address indexed user, address indexed token, uint256 indexed amount);

    // Functions

    constructor(address _collateralToken, address _priceFeed, address stabletokenAddress) {
        collateralToken = _collateralToken;
        priceFeed = _priceFeed;
        sbt = Stabletoken(stabletokenAddress);
    }

    function deposit(uint256 amount) public moreThanZero(amount) nonReentrant {
        deposited[msg.sender] += amount;
        emit Deposit(msg.sender, collateralToken, amount);
        bool success = IERC20(collateralToken).transferFrom(msg.sender, address(this), amount);
        if (!success) revert StabletokenEngine__TransferFailed();
    }
}
