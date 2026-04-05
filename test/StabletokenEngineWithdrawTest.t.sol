// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {StabletokenEngine} from "../src/StabletokenEngine.sol";
import {Stabletoken} from "../src/Stabletoken.sol";
import {MockERC20, FailingERC20} from "./mocks/MockERC20.sol";
import {MockPriceFeed} from "./mocks/MockPriceFeed.sol";

contract StabletokenEngineWithdrawTest is Test {
    StabletokenEngine engine;
    Stabletoken sbt;
    MockERC20 collateralA;
    MockERC20 collateralB;
    MockPriceFeed priceFeedA;
    MockPriceFeed priceFeedB;

    address USER = makeAddr("user");

    // collateralA at $2000, collateralB at $3000
    // deposit 1 ether of A → $2000
    // With MINT_AMOUNT=500e18 (HF=2e18 with A alone)
    int256 constant PRICE_A = 2000e8;
    int256 constant PRICE_B = 3000e8;
    uint256 constant DEPOSIT_AMOUNT = 1 ether;
    uint256 constant MINT_AMOUNT = 500e18;
    uint256 constant SAFE_WITHDRAW = 0.4 ether; // leaves 0.6 ether ($1200), HF=1.2e18
    uint256 constant UNSAFE_WITHDRAW = 0.6 ether; // leaves 0.4 ether ($800), HF=0.8e18

    // Storage: deposited=slot1 (nested mapping)
    uint256 constant DEPOSITED_SLOT = 1;

    event Withdraw(address indexed user, address indexed token, uint256 indexed amount);

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

        collateralA.mint(USER, 10 ether);
        collateralB.mint(USER, 10 ether);

        vm.startPrank(USER);
        collateralA.approve(address(engine), DEPOSIT_AMOUNT);
        engine.deposit(address(collateralA), DEPOSIT_AMOUNT);
        vm.stopPrank();
    }

    function testWithdrawSuccessReturnsTokensToUser() public {
        vm.prank(USER);
        engine.withdraw(address(collateralA), DEPOSIT_AMOUNT);

        assertEq(collateralA.balanceOf(USER), 10 ether);
        assertEq(collateralA.balanceOf(address(engine)), 0);
    }

    function testWithdrawSuccessEmitsEvent() public {
        vm.expectEmit(true, true, true, false);
        emit Withdraw(USER, address(collateralA), DEPOSIT_AMOUNT);

        vm.prank(USER);
        engine.withdraw(address(collateralA), DEPOSIT_AMOUNT);
    }

    function testWithdrawSuccessPartialWithdrawWhileHealthy() public {
        vm.prank(USER);
        engine.mint(MINT_AMOUNT);

        vm.prank(USER);
        engine.withdraw(address(collateralA), SAFE_WITHDRAW);

        assertEq(collateralA.balanceOf(USER), 10 ether - DEPOSIT_AMOUNT + SAFE_WITHDRAW);
        assertGe(engine.getHealthFactor(USER), 1e18);
    }

    function testWithdrawSuccessOtherCollateralKeepsHealthy() public {
        // Deposit collateralB too, mint against aggregate, then withdraw all of A
        vm.startPrank(USER);
        collateralB.approve(address(engine), DEPOSIT_AMOUNT);
        engine.deposit(address(collateralB), DEPOSIT_AMOUNT);
        // Total collateral: $2000 + $3000 = $5000, max safe mint = 2500e18
        engine.mint(1000e18);
        // Withdraw all of A: remaining $3000 from B, HF = 3000*50/(1000*100) = 1.5e18
        engine.withdraw(address(collateralA), DEPOSIT_AMOUNT);
        vm.stopPrank();

        assertGe(engine.getHealthFactor(USER), 1e18);
    }

    function testWithdrawRevertsOnZeroAmount() public {
        vm.prank(USER);
        vm.expectRevert(StabletokenEngine.StabletokenEngine__ZeroAmount.selector);
        engine.withdraw(address(collateralA), 0);
    }

    function testWithdrawRevertsBrokenHealthFactor() public {
        vm.prank(USER);
        engine.mint(MINT_AMOUNT);

        vm.prank(USER);
        vm.expectRevert(StabletokenEngine.StabletokenEngine__BrokenHealthFactor.selector);
        engine.withdraw(address(collateralA), UNSAFE_WITHDRAW);
    }

    function testWithdrawRevertsWhenTransferFails() public {
        FailingERC20 failingToken = new FailingERC20();

        address[] memory collaterals = new address[](1);
        collaterals[0] = address(failingToken);
        address[] memory feeds = new address[](1);
        feeds[0] = address(priceFeedA);

        StabletokenEngine failingEngine = new StabletokenEngine(collaterals, feeds, address(sbt));

        // Seed internal accounting via vm.store for nested mapping: deposited[USER][failingToken]
        bytes32 outerKey = keccak256(abi.encode(USER, DEPOSITED_SLOT));
        bytes32 innerKey = keccak256(abi.encode(address(failingToken), outerKey));
        vm.store(address(failingEngine), innerKey, bytes32(DEPOSIT_AMOUNT));

        vm.prank(USER);
        vm.expectRevert(StabletokenEngine.StabletokenEngine__TransferFailed.selector);
        failingEngine.withdraw(address(failingToken), DEPOSIT_AMOUNT);
    }
}
