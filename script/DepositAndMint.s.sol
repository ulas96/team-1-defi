// SPDX-License-Identifier: MIT

pragma solidity ^0.8.29;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {StabletokenEngine} from "../src/StabletokenEngine.sol";
import {Stabletoken} from "../src/Stabletoken.sol";

interface IWAVAX is IERC20 {
    function deposit() external payable;
}

contract DepositAndMint is Script {
    function run() external {
        address wavax = vm.envAddress("WAVAX_ADDRESS");
        address engineAddr = vm.envAddress("STABLETOKEN_ENGINE");
        address sbtAddr = vm.envAddress("STABLETOKEN");
        uint256 collateralAmount = vm.envUint("COLLATERAL_AMOUNT");
        uint256 mintAmount = vm.envUint("MINT_AMOUNT");
        uint256 wrapAmount = vm.envOr("WRAP_AMOUNT", uint256(0));

        StabletokenEngine engine = StabletokenEngine(engineAddr);
        IWAVAX token = IWAVAX(wavax);

        vm.startBroadcast();

        if (wrapAmount > 0) {
            token.deposit{value: wrapAmount}();
        }

        token.approve(engineAddr, collateralAmount);
        engine.deposit(collateralAmount);
        engine.mint(mintAmount);

        vm.stopBroadcast();

        address sender = msg.sender;
        console.log("Depositor:              ", sender);
        console.log("WAVAX deposited:        ", collateralAmount);
        console.log("SBT minted:             ", mintAmount);
        console.log("SBT balance:            ", Stabletoken(sbtAddr).balanceOf(sender));
        console.log("Health factor:          ", engine.getHealthFactor(sender));
    }
}
