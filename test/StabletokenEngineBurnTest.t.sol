// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {StabletokenEngine} from "../src/StabletokenEngine.sol";
import {Stabletoken} from "../src/Stabletoken.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockPriceFeed} from "./mocks/MockPriceFeed.sol";

contract StabletokenEngineBurnTest is Test {
    StabletokenEngine engine;
    Stabletoken sbt;
    MockERC20 collateralA;
    MockPriceFeed priceFeedA;

    address USER = makeAddr("user");

    int256 constant PRICE_A = 2000e8;
    uint256 constant DEPOSIT_AMOUNT = 1 ether;
    uint256 constant MINT_AMOUNT = 500e18;

    // Storage slots: deposited=1 (nested), minted=2
    uint256 constant MINTED_SLOT = 2;

    function setUp() public {
        collateralA = new MockERC20();
        priceFeedA = new MockPriceFeed(PRICE_A);
        sbt = new Stabletoken();

        address[] memory collaterals = new address[](1);
        collaterals[0] = address(collateralA);
        address[] memory feeds = new address[](1);
        feeds[0] = address(priceFeedA);

        engine = new StabletokenEngine(collaterals, feeds, address(sbt));
        sbt.transferOwnership(address(engine));

        collateralA.mint(USER, 10 ether);
    }

    function _depositAndMint() internal {
        vm.startPrank(USER);
        collateralA.approve(address(engine), DEPOSIT_AMOUNT);
        engine.deposit(address(collateralA), DEPOSIT_AMOUNT);
        engine.mint(MINT_AMOUNT);
        vm.stopPrank();
    }

    function testBurnSuccessReducesSbtBalance() public {
        _depositAndMint();

        vm.startPrank(USER);
        sbt.approve(address(engine), MINT_AMOUNT);
        engine.burn(MINT_AMOUNT);
        vm.stopPrank();

        assertEq(sbt.balanceOf(USER), 0);
    }

    function testBurnSuccessPartialBurn() public {
        _depositAndMint();
        uint256 burnAmount = MINT_AMOUNT / 2;

        vm.startPrank(USER);
        sbt.approve(address(engine), burnAmount);
        engine.burn(burnAmount);
        vm.stopPrank();

        assertEq(sbt.balanceOf(USER), MINT_AMOUNT - burnAmount);
    }

    function testBurnSuccessHealthFactorImproves() public {
        _depositAndMint();
        uint256 hfBefore = engine.getHealthFactor(USER);

        vm.startPrank(USER);
        sbt.approve(address(engine), MINT_AMOUNT / 2);
        engine.burn(MINT_AMOUNT / 2);
        vm.stopPrank();

        assertGt(engine.getHealthFactor(USER), hfBefore);
    }

    function testBurnRevertsOnZeroAmount() public {
        vm.prank(USER);
        vm.expectRevert(StabletokenEngine.StabletokenEngine__ZeroAmount.selector);
        engine.burn(0);
    }

    function testBurnRevertsWithoutApproval() public {
        _depositAndMint();

        vm.prank(USER);
        vm.expectRevert();
        engine.burn(MINT_AMOUNT);
    }

    function testBurnRevertsBrokenHealthFactor() public {
        // Simulate state where deposit=0 but minted>0 via vm.store
        vm.prank(address(engine));
        sbt.mint(USER, MINT_AMOUNT);

        bytes32 mintedKey = keccak256(abi.encode(USER, MINTED_SLOT));
        vm.store(address(engine), mintedKey, bytes32(MINT_AMOUNT));

        vm.startPrank(USER);
        sbt.approve(address(engine), MINT_AMOUNT / 2);
        vm.expectRevert(StabletokenEngine.StabletokenEngine__BrokenHealthFactor.selector);
        engine.burn(MINT_AMOUNT / 2);
        vm.stopPrank();
    }
}
