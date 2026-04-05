// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {StabletokenEngine} from "../src/StabletokenEngine.sol";
import {Stabletoken} from "../src/Stabletoken.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockPriceFeed} from "./mocks/MockPriceFeed.sol";

contract StabletokenEngineLiquidateTest is Test {
    StabletokenEngine engine;
    Stabletoken sbt;
    MockERC20 collateralA;
    MockERC20 collateralB;
    MockPriceFeed priceFeedA;
    MockPriceFeed priceFeedB;

    address USER = makeAddr("user");
    address LIQUIDATOR = makeAddr("liquidator");

    // At $2000/$3000: deposit 1 ether each → $5000 total, mint 2000e18 → HF=1.25e18 (healthy)
    // Crash A to $100, B to $100: total=$200, HF=0.05e18 (liquidatable)
    int256 constant INITIAL_PRICE_A = 2000e8;
    int256 constant INITIAL_PRICE_B = 3000e8;
    int256 constant CRASHED_PRICE = 100e8;
    uint256 constant DEPOSIT_AMOUNT = 1 ether;
    uint256 constant MINT_AMOUNT = 500e18;

    function setUp() public {
        collateralA = new MockERC20();
        collateralB = new MockERC20();
        priceFeedA = new MockPriceFeed(INITIAL_PRICE_A);
        priceFeedB = new MockPriceFeed(INITIAL_PRICE_B);
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

        // USER deposits collateralA and mints at healthy price
        vm.startPrank(USER);
        collateralA.approve(address(engine), DEPOSIT_AMOUNT);
        engine.deposit(address(collateralA), DEPOSIT_AMOUNT);
        engine.mint(MINT_AMOUNT);
        vm.stopPrank();
    }

    function _crashPrice() internal {
        priceFeedA.setPrice(CRASHED_PRICE);
    }

    function _fundLiquidator() internal {
        vm.prank(USER);
        sbt.transfer(LIQUIDATOR, MINT_AMOUNT);
    }

    function testLiquidateSuccessTransfersCollateralToLiquidator() public {
        _crashPrice();
        _fundLiquidator();

        vm.startPrank(LIQUIDATOR);
        sbt.approve(address(engine), MINT_AMOUNT);
        engine.liquidate(USER);
        vm.stopPrank();

        assertEq(collateralA.balanceOf(LIQUIDATOR), DEPOSIT_AMOUNT);
    }

    function testLiquidateSuccessClearsUserDebt() public {
        _crashPrice();
        _fundLiquidator();

        vm.startPrank(LIQUIDATOR);
        sbt.approve(address(engine), MINT_AMOUNT);
        engine.liquidate(USER);
        vm.stopPrank();

        assertEq(engine.getHealthFactor(USER), type(uint256).max);
    }

    function testLiquidateSuccessBurnsSbt() public {
        _crashPrice();
        _fundLiquidator();
        uint256 totalSupplyBefore = sbt.totalSupply();

        vm.startPrank(LIQUIDATOR);
        sbt.approve(address(engine), MINT_AMOUNT);
        engine.liquidate(USER);
        vm.stopPrank();

        assertEq(sbt.totalSupply(), totalSupplyBefore - MINT_AMOUNT);
    }

    function testLiquidateSuccessTransfersMultipleCollaterals() public {
        // Deposit collateralB too
        vm.startPrank(USER);
        collateralB.approve(address(engine), DEPOSIT_AMOUNT);
        engine.deposit(address(collateralB), DEPOSIT_AMOUNT);
        vm.stopPrank();

        // Crash both prices
        priceFeedA.setPrice(CRASHED_PRICE);
        priceFeedB.setPrice(CRASHED_PRICE);

        _fundLiquidator();

        vm.startPrank(LIQUIDATOR);
        sbt.approve(address(engine), MINT_AMOUNT);
        engine.liquidate(USER);
        vm.stopPrank();

        // Liquidator receives both collateral types
        assertEq(collateralA.balanceOf(LIQUIDATOR), DEPOSIT_AMOUNT);
        assertEq(collateralB.balanceOf(LIQUIDATOR), DEPOSIT_AMOUNT);
    }

    function testLiquidateRevertsWhenHealthFactorNotBroken() public {
        vm.prank(LIQUIDATOR);
        vm.expectRevert(StabletokenEngine.StabletokenEngine__HealthFactorNotBroken.selector);
        engine.liquidate(USER);
    }

    function testLiquidateRevertsWhenLiquidatorHasNoSbt() public {
        _crashPrice();
        vm.prank(LIQUIDATOR);
        vm.expectRevert();
        engine.liquidate(USER);
    }
}
