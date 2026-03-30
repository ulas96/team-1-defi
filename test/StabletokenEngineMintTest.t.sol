// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {StabletokenEngine} from "../src/StabletokenEngine.sol";
import {Stabletoken} from "../src/Stabletoken.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockPriceFeed} from "./mocks/MockPriceFeed.sol";

contract StabletokenEngineMintTest is Test {
    StabletokenEngine engine;
    Stabletoken sbt;
    MockERC20 collateral;
    MockPriceFeed priceFeed;

    address USER = makeAddr("user");

    // At $2000/ETH with 50% liquidation threshold:
    //   collateralValueUsd = 2000 * deposit
    //   healthFactor = (collateralValueUsd * 1e18 * 50) / (minted * 100)
    //   healthy when: 1000 * deposit >= minted
    // deposit=1 ether → max safe mint = 1000e18 SBT
    int256 constant INITIAL_PRICE = 2000e8;
    uint256 constant DEPOSIT_AMOUNT = 1 ether;
    uint256 constant SAFE_MINT_AMOUNT = 500e18; // HF = 2e18
    uint256 constant EXCESS_MINT_AMOUNT = 1001e18; // HF < 1e18

    function setUp() public {
        collateral = new MockERC20();
        priceFeed = new MockPriceFeed(INITIAL_PRICE);
        sbt = new Stabletoken();
        engine = new StabletokenEngine(address(collateral), address(priceFeed), address(sbt));
        sbt.transferOwnership(address(engine));

        collateral.mint(USER, 10 ether);
    }

    function testMintSuccessMintsTokensToUser() public {
        vm.startPrank(USER);
        collateral.approve(address(engine), DEPOSIT_AMOUNT);
        engine.deposit(DEPOSIT_AMOUNT);
        engine.mint(SAFE_MINT_AMOUNT);
        vm.stopPrank();

        assertEq(sbt.balanceOf(USER), SAFE_MINT_AMOUNT);
    }

    function testMintSuccessHealthFactorRemainsHealthy() public {
        vm.startPrank(USER);
        collateral.approve(address(engine), DEPOSIT_AMOUNT);
        engine.deposit(DEPOSIT_AMOUNT);
        engine.mint(SAFE_MINT_AMOUNT);
        vm.stopPrank();

        assertGe(engine.getHealthFactor(USER), 1e18);
    }

    function testMintSuccessAccumulatesMultipleMints() public {
        vm.startPrank(USER);
        collateral.approve(address(engine), DEPOSIT_AMOUNT);
        engine.deposit(DEPOSIT_AMOUNT);
        engine.mint(SAFE_MINT_AMOUNT / 2);
        engine.mint(SAFE_MINT_AMOUNT / 2);
        vm.stopPrank();

        assertEq(sbt.balanceOf(USER), SAFE_MINT_AMOUNT);
    }

    function testMintRevertsOnZeroAmount() public {
        vm.prank(USER);
        vm.expectRevert(StabletokenEngine.StabletokenEngine__ZeroAmount.selector);
        engine.mint(0);
    }

    function testMintRevertsWithNoCollateral() public {
        // No deposit at all — any mint breaks health factor
        vm.prank(USER);
        vm.expectRevert(StabletokenEngine.StabletokenEngine__BrokenHealthFactor.selector);
        engine.mint(SAFE_MINT_AMOUNT);
    }

    function testMintRevertsWhenExceedsCollateralThreshold() public {
        vm.startPrank(USER);
        collateral.approve(address(engine), DEPOSIT_AMOUNT);
        engine.deposit(DEPOSIT_AMOUNT);

        vm.expectRevert(StabletokenEngine.StabletokenEngine__BrokenHealthFactor.selector);
        engine.mint(EXCESS_MINT_AMOUNT);
        vm.stopPrank();
    }
}
