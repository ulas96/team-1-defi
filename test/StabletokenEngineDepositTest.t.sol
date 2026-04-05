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
    MockERC20 collateralA;
    MockERC20 collateralB;
    MockPriceFeed priceFeedA;
    MockPriceFeed priceFeedB;

    address USER = makeAddr("user");
    uint256 constant INITIAL_BALANCE = 10 ether;
    uint256 constant DEPOSIT_AMOUNT = 1 ether;

    int256 constant PRICE_A = 2000e8;
    int256 constant PRICE_B = 3000e8;

    event Deposit(address indexed user, address indexed token, uint256 indexed amount);

    function setUp() public {
        collateralA = new MockERC20();
        collateralB = new MockERC20();
        priceFeedA = new MockPriceFeed(PRICE_A);
        priceFeedB = new MockPriceFeed(PRICE_B);
        sbt = new Stabletoken();

        address[] memory collaterals = new address[](2);
        collaterals[0] = address(collateralA);
        collaterals[1] = address(collateralB);

        address[] memory feeds = new address[](2);
        feeds[0] = address(priceFeedA);
        feeds[1] = address(priceFeedB);

        engine = new StabletokenEngine(collaterals, feeds, address(sbt));
        sbt.transferOwnership(address(engine));

        collateralA.mint(USER, INITIAL_BALANCE);
        collateralB.mint(USER, INITIAL_BALANCE);
    }

    function testDepositSuccessTransfersTokens() public {
        vm.startPrank(USER);
        collateralA.approve(address(engine), DEPOSIT_AMOUNT);
        engine.deposit(address(collateralA), DEPOSIT_AMOUNT);
        vm.stopPrank();

        assertEq(collateralA.balanceOf(address(engine)), DEPOSIT_AMOUNT);
        assertEq(collateralA.balanceOf(USER), INITIAL_BALANCE - DEPOSIT_AMOUNT);
    }

    function testDepositSuccessEmitsEvent() public {
        vm.startPrank(USER);
        collateralA.approve(address(engine), DEPOSIT_AMOUNT);

        vm.expectEmit(true, true, true, false);
        emit Deposit(USER, address(collateralA), DEPOSIT_AMOUNT);

        engine.deposit(address(collateralA), DEPOSIT_AMOUNT);
        vm.stopPrank();
    }

    function testDepositSuccessAccumulatesMultipleDeposits() public {
        vm.startPrank(USER);
        collateralA.approve(address(engine), INITIAL_BALANCE);
        engine.deposit(address(collateralA), DEPOSIT_AMOUNT);
        engine.deposit(address(collateralA), DEPOSIT_AMOUNT);
        vm.stopPrank();

        assertEq(collateralA.balanceOf(address(engine)), DEPOSIT_AMOUNT * 2);
    }

    function testDepositSuccessMultipleCollateralTypes() public {
        vm.startPrank(USER);
        collateralA.approve(address(engine), DEPOSIT_AMOUNT);
        collateralB.approve(address(engine), DEPOSIT_AMOUNT);
        engine.deposit(address(collateralA), DEPOSIT_AMOUNT);
        engine.deposit(address(collateralB), DEPOSIT_AMOUNT);
        vm.stopPrank();

        assertEq(collateralA.balanceOf(address(engine)), DEPOSIT_AMOUNT);
        assertEq(collateralB.balanceOf(address(engine)), DEPOSIT_AMOUNT);
    }

    function testDepositRevertsOnZeroAmount() public {
        vm.prank(USER);
        vm.expectRevert(StabletokenEngine.StabletokenEngine__ZeroAmount.selector);
        engine.deposit(address(collateralA), 0);
    }

    function testDepositRevertsOnNotCollateral() public {
        address fakeToken = makeAddr("fakeToken");
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(StabletokenEngine.StabletokenEngine__NotCollateral.selector, fakeToken));
        engine.deposit(fakeToken, DEPOSIT_AMOUNT);
    }

    function testDepositRevertsWhenTransferFails() public {
        FailingERC20 failingToken = new FailingERC20();

        address[] memory collaterals = new address[](1);
        collaterals[0] = address(failingToken);
        address[] memory feeds = new address[](1);
        feeds[0] = address(priceFeedA);

        StabletokenEngine engineWithFailingToken = new StabletokenEngine(collaterals, feeds, address(sbt));

        vm.prank(USER);
        vm.expectRevert(StabletokenEngine.StabletokenEngine__TransferFailed.selector);
        engineWithFailingToken.deposit(address(failingToken), DEPOSIT_AMOUNT);
    }

    function testDepositRevertsWithoutApproval() public {
        vm.prank(USER);
        vm.expectRevert(StabletokenEngine.StabletokenEngine__TransferFailed.selector);
        engine.deposit(address(collateralA), DEPOSIT_AMOUNT);
    }
}
