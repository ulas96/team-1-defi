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
    MockERC20 collateral;
    MockPriceFeed priceFeed;

    address USER = makeAddr("user");

    int256 constant INITIAL_PRICE = 2000e8;
    uint256 constant DEPOSIT_AMOUNT = 1 ether;
    uint256 constant MINT_AMOUNT = 500e18;

    // Storage slots in StabletokenEngine (after ReentrancyGuard._status at slot 0):
    //   slot 1 → deposited mapping
    //   slot 2 → minted mapping
    uint256 constant DEPOSITED_SLOT = 1;
    uint256 constant MINTED_SLOT = 2;

    function setUp() public {
        collateral = new MockERC20();
        priceFeed = new MockPriceFeed(INITIAL_PRICE);
        sbt = new Stabletoken();
        engine = new StabletokenEngine(address(collateral), address(priceFeed), address(sbt));
        sbt.transferOwnership(address(engine));

        collateral.mint(USER, 10 ether);
    }

    function _depositAndMint() internal {
        vm.startPrank(USER);
        collateral.approve(address(engine), DEPOSIT_AMOUNT);
        engine.deposit(DEPOSIT_AMOUNT);
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
        // OZ ERC20 transferFrom reverts when allowance is insufficient
        _depositAndMint();

        vm.prank(USER);
        vm.expectRevert();
        engine.burn(MINT_AMOUNT);
    }

    function testBurnRevertsBrokenHealthFactor() public {
        // Simulate a state where deposit=0 but minted>0, so any remaining debt breaks HF.
        // Achieved via vm.store since this state is unreachable through normal usage.
        vm.prank(address(engine));
        sbt.mint(USER, MINT_AMOUNT);

        bytes32 mintedKey = keccak256(abi.encode(USER, MINTED_SLOT));
        vm.store(address(engine), mintedKey, bytes32(MINT_AMOUNT));
        // deposited[USER] stays 0 → health factor = 0 after any partial burn

        vm.startPrank(USER);
        sbt.approve(address(engine), MINT_AMOUNT / 2);
        vm.expectRevert(StabletokenEngine.StabletokenEngine__BrokenHealthFactor.selector);
        engine.burn(MINT_AMOUNT / 2);
        vm.stopPrank();
    }
}
