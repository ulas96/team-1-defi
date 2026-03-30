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
    MockERC20 collateral;
    MockPriceFeed priceFeed;

    address USER = makeAddr("user");

    // At $2000 with 50% threshold: deposit=1 ether → safe up to 1000e18 SBT
    // With MINT_AMOUNT=500e18 (HF=2e18), safe to withdraw down to 0.5 ether
    // Withdrawing 0.6 ether leaves 0.4 ether → HF=0.8e18 < 1e18 → broken
    int256 constant INITIAL_PRICE = 2000e8;
    uint256 constant DEPOSIT_AMOUNT = 1 ether;
    uint256 constant MINT_AMOUNT = 500e18;
    uint256 constant SAFE_WITHDRAW = 0.4 ether; // leaves 0.6 ether, HF=1.2e18
    uint256 constant UNSAFE_WITHDRAW = 0.6 ether; // leaves 0.4 ether, HF=0.8e18

    event Withdraw(address indexed user, uint256 indexed amount);

    function setUp() public {
        collateral = new MockERC20();
        priceFeed = new MockPriceFeed(INITIAL_PRICE);
        sbt = new Stabletoken();
        engine = new StabletokenEngine(address(collateral), address(priceFeed), address(sbt));
        sbt.transferOwnership(address(engine));

        collateral.mint(USER, 10 ether);

        vm.startPrank(USER);
        collateral.approve(address(engine), DEPOSIT_AMOUNT);
        engine.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
    }

    function testWithdrawSuccessReturnsTokensToUser() public {
        vm.prank(USER);
        engine.withdraw(DEPOSIT_AMOUNT);

        assertEq(collateral.balanceOf(USER), 10 ether);
        assertEq(collateral.balanceOf(address(engine)), 0);
    }

    function testWithdrawSuccessEmitsEvent() public {
        vm.expectEmit(true, true, false, false);
        emit Withdraw(USER, DEPOSIT_AMOUNT);

        vm.prank(USER);
        engine.withdraw(DEPOSIT_AMOUNT);
    }

    function testWithdrawSuccessPartialWithdrawWhileHealthy() public {
        // Mint first to make health factor relevant
        vm.prank(USER);
        engine.mint(MINT_AMOUNT);

        vm.prank(USER);
        engine.withdraw(SAFE_WITHDRAW);

        assertEq(collateral.balanceOf(USER), 10 ether - DEPOSIT_AMOUNT + SAFE_WITHDRAW);
        assertGe(engine.getHealthFactor(USER), 1e18);
    }

    function testWithdrawRevertsOnZeroAmount() public {
        vm.prank(USER);
        vm.expectRevert(StabletokenEngine.StabletokenEngine__ZeroAmount.selector);
        engine.withdraw(0);
    }

    function testWithdrawRevertsBrokenHealthFactor() public {
        // Mint so there is outstanding debt, then try to withdraw too much
        vm.prank(USER);
        engine.mint(MINT_AMOUNT);

        vm.prank(USER);
        vm.expectRevert(StabletokenEngine.StabletokenEngine__BrokenHealthFactor.selector);
        engine.withdraw(UNSAFE_WITHDRAW);
    }

    function testWithdrawRevertsWhenTransferFails() public {
        // Deploy an engine backed by a token whose transfer always fails
        FailingERC20 failingToken = new FailingERC20();
        StabletokenEngine failingEngine =
            new StabletokenEngine(address(failingToken), address(priceFeed), address(sbt));

        // Seed the engine's internal accounting via vm.store (slot 1 = deposited mapping)
        bytes32 depositedKey = keccak256(abi.encode(USER, uint256(1)));
        vm.store(address(failingEngine), depositedKey, bytes32(DEPOSIT_AMOUNT));

        vm.prank(USER);
        vm.expectRevert(StabletokenEngine.StabletokenEngine__TransferFailed.selector);
        failingEngine.withdraw(DEPOSIT_AMOUNT);
    }
}
