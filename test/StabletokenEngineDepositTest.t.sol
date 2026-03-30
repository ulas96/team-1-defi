// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {StabletokenEngine} from "../src/StabletokenEngine.sol";
import {Stabletoken} from "../src/Stabletoken.sol";
import {MockERC20, FailingERC20} from "./mocks/MockERC20.sol";
import {MockPriceFeed} from "./mocks/MockPriceFeed.sol";

contract StabletokenEngineDepositTest is Test {
    StabletokenEngine engine;
    Stabletoken sbt;
    MockERC20 collateral;
    MockPriceFeed priceFeed;

    address USER = makeAddr("user");
    uint256 constant INITIAL_BALANCE = 10 ether;
    uint256 constant DEPOSIT_AMOUNT = 1 ether;

    // $2000 price with 8 decimals — matches Chainlink ETH/USD format
    int256 constant INITIAL_PRICE = 2000e8;

    event Deposit(address indexed user, uint256 indexed amount);

    function setUp() public {
        collateral = new MockERC20();
        priceFeed = new MockPriceFeed(INITIAL_PRICE);
        sbt = new Stabletoken();
        engine = new StabletokenEngine(address(collateral), address(priceFeed), address(sbt));
        sbt.transferOwnership(address(engine));

        collateral.mint(USER, INITIAL_BALANCE);
    }

    function testDepositSuccessTransfersTokens() public {
        vm.startPrank(USER);
        collateral.approve(address(engine), DEPOSIT_AMOUNT);
        engine.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();

        assertEq(collateral.balanceOf(address(engine)), DEPOSIT_AMOUNT);
        assertEq(collateral.balanceOf(USER), INITIAL_BALANCE - DEPOSIT_AMOUNT);
    }

    function testDepositSuccessEmitsEvent() public {
        vm.startPrank(USER);
        collateral.approve(address(engine), DEPOSIT_AMOUNT);

        vm.expectEmit(true, true, false, false);
        emit Deposit(USER, DEPOSIT_AMOUNT);

        engine.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
    }

    function testDepositSuccessAccumulatesMultipleDeposits() public {
        vm.startPrank(USER);
        collateral.approve(address(engine), INITIAL_BALANCE);
        engine.deposit(DEPOSIT_AMOUNT);
        engine.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();

        assertEq(collateral.balanceOf(address(engine)), DEPOSIT_AMOUNT * 2);
    }

    function testDepositRevertsOnZeroAmount() public {
        vm.prank(USER);
        vm.expectRevert(StabletokenEngine.StabletokenEngine__ZeroAmount.selector);
        engine.deposit(0);
    }

    function testDepositRevertsWhenTransferFails() public {
        FailingERC20 failingToken = new FailingERC20();
        StabletokenEngine engineWithFailingToken =
            new StabletokenEngine(address(failingToken), address(priceFeed), address(sbt));

        vm.prank(USER);
        vm.expectRevert(StabletokenEngine.StabletokenEngine__TransferFailed.selector);
        engineWithFailingToken.deposit(DEPOSIT_AMOUNT);
    }

    function testDepositRevertsWithoutApproval() public {
        vm.prank(USER);
        vm.expectRevert(StabletokenEngine.StabletokenEngine__TransferFailed.selector);
        engine.deposit(DEPOSIT_AMOUNT);
    }
}
