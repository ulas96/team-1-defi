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
    MockERC20 collateralA;
    MockERC20 collateralB;
    MockPriceFeed priceFeedA;
    MockPriceFeed priceFeedB;

    address USER = makeAddr("user");

    // collateralA at $2000, collateralB at $3000
    // deposit 1 ether of A → $2000, max safe mint = 1000e18
    // deposit 1 ether of B → $3000, max safe mint = 1500e18
    // both deposited → $5000 total, max safe mint = 2500e18
    int256 constant PRICE_A = 2000e8;
    int256 constant PRICE_B = 3000e8;
    uint256 constant DEPOSIT_AMOUNT = 1 ether;
    uint256 constant SAFE_MINT_AMOUNT = 500e18;
    uint256 constant EXCESS_MINT_AMOUNT = 1001e18;

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
    }

    function testMintSuccessMintsTokensToUser() public {
        vm.startPrank(USER);
        collateralA.approve(address(engine), DEPOSIT_AMOUNT);
        engine.deposit(address(collateralA), DEPOSIT_AMOUNT);
        engine.mint(SAFE_MINT_AMOUNT);
        vm.stopPrank();

        assertEq(sbt.balanceOf(USER), SAFE_MINT_AMOUNT);
    }

    function testMintSuccessHealthFactorRemainsHealthy() public {
        vm.startPrank(USER);
        collateralA.approve(address(engine), DEPOSIT_AMOUNT);
        engine.deposit(address(collateralA), DEPOSIT_AMOUNT);
        engine.mint(SAFE_MINT_AMOUNT);
        vm.stopPrank();

        assertGe(engine.getHealthFactor(USER), 1e18);
    }

    function testMintSuccessAccumulatesMultipleMints() public {
        vm.startPrank(USER);
        collateralA.approve(address(engine), DEPOSIT_AMOUNT);
        engine.deposit(address(collateralA), DEPOSIT_AMOUNT);
        engine.mint(SAFE_MINT_AMOUNT / 2);
        engine.mint(SAFE_MINT_AMOUNT / 2);
        vm.stopPrank();

        assertEq(sbt.balanceOf(USER), SAFE_MINT_AMOUNT);
    }

    function testMintSuccessAgainstMultipleCollaterals() public {
        // Deposit both collaterals: $2000 + $3000 = $5000 total, max mint = 2500e18
        vm.startPrank(USER);
        collateralA.approve(address(engine), DEPOSIT_AMOUNT);
        collateralB.approve(address(engine), DEPOSIT_AMOUNT);
        engine.deposit(address(collateralA), DEPOSIT_AMOUNT);
        engine.deposit(address(collateralB), DEPOSIT_AMOUNT);
        engine.mint(2000e18); // safe: HF = 5000 * 50 / (2000 * 100) = 1.25e18
        vm.stopPrank();

        assertEq(sbt.balanceOf(USER), 2000e18);
        assertGe(engine.getHealthFactor(USER), 1e18);
    }

    function testMintRevertsOnZeroAmount() public {
        vm.prank(USER);
        vm.expectRevert(StabletokenEngine.StabletokenEngine__ZeroAmount.selector);
        engine.mint(0);
    }

    function testMintRevertsWithNoCollateral() public {
        vm.prank(USER);
        vm.expectRevert(StabletokenEngine.StabletokenEngine__BrokenHealthFactor.selector);
        engine.mint(SAFE_MINT_AMOUNT);
    }

    function testMintRevertsWhenExceedsCollateralThreshold() public {
        vm.startPrank(USER);
        collateralA.approve(address(engine), DEPOSIT_AMOUNT);
        engine.deposit(address(collateralA), DEPOSIT_AMOUNT);

        vm.expectRevert(StabletokenEngine.StabletokenEngine__BrokenHealthFactor.selector);
        engine.mint(EXCESS_MINT_AMOUNT);
        vm.stopPrank();
    }
}
