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
    MockERC20 collateral;
    MockPriceFeed priceFeed;

    address USER = makeAddr("user");
    address LIQUIDATOR = makeAddr("liquidator");

    // At $2000: deposit=1 ether → max safe mint=1000e18, MINT_AMOUNT=500e18 → HF=2e18 (healthy)
    // At $100:  collateralValueUsd=100e18, minted=500e18 → HF=0.1e18 (liquidatable)
    int256 constant INITIAL_PRICE = 2000e8;
    int256 constant CRASHED_PRICE = 100e8;
    uint256 constant DEPOSIT_AMOUNT = 1 ether;
    uint256 constant MINT_AMOUNT = 500e18;

    function setUp() public {
        collateral = new MockERC20();
        priceFeed = new MockPriceFeed(INITIAL_PRICE);
        sbt = new Stabletoken();
        engine = new StabletokenEngine(address(collateral), address(priceFeed), address(sbt));
        sbt.transferOwnership(address(engine));

        collateral.mint(USER, 10 ether);

        // USER deposits and mints at healthy price
        vm.startPrank(USER);
        collateral.approve(address(engine), DEPOSIT_AMOUNT);
        engine.deposit(DEPOSIT_AMOUNT);
        engine.mint(MINT_AMOUNT);
        vm.stopPrank();
    }

    function _crashPrice() internal {
        priceFeed.setPrice(CRASHED_PRICE);
    }

    function _fundLiquidator() internal {
        // Give LIQUIDATOR enough SBT to cover the debt (acquired from USER for simplicity)
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

        assertEq(collateral.balanceOf(LIQUIDATOR), DEPOSIT_AMOUNT);
    }

    function testLiquidateSuccessClearsUserDebt() public {
        _crashPrice();
        _fundLiquidator();

        vm.startPrank(LIQUIDATOR);
        sbt.approve(address(engine), MINT_AMOUNT);
        engine.liquidate(USER);
        vm.stopPrank();

        // After liquidation health factor is max (minted=0)
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

    function testLiquidateRevertsWhenHealthFactorNotBroken() public {
        // Price has not crashed — USER is still healthy
        vm.prank(LIQUIDATOR);
        vm.expectRevert(StabletokenEngine.StabletokenEngine__HealthFactorNotBroken.selector);
        engine.liquidate(USER);
    }

    function testLiquidateRevertsWhenLiquidatorHasNoSbt() public {
        _crashPrice();
        // LIQUIDATOR has no SBT and no approval — OZ transferFrom reverts
        vm.prank(LIQUIDATOR);
        vm.expectRevert();
        engine.liquidate(USER);
    }
}
