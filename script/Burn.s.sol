// SPDX-License-Identifier: MIT

pragma solidity ^0.8.29;

import {Script, console} from "forge-std/Script.sol";
import {StabletokenEngine} from "../src/StabletokenEngine.sol";
import {Stabletoken} from "../src/Stabletoken.sol";

contract Burn is Script {
    function run() external {
        address engineAddr = vm.envAddress("STABLETOKEN_ENGINE");
        address sbtAddr = vm.envAddress("STABLETOKEN");
        uint256 burnAmount = vm.envUint("BURN_AMOUNT");

        StabletokenEngine engine = StabletokenEngine(engineAddr);
        Stabletoken sbt = Stabletoken(sbtAddr);

        vm.startBroadcast();

        sbt.approve(engineAddr, burnAmount);
        engine.burn(burnAmount);

        vm.stopBroadcast();

        address sender = msg.sender;
        console.log("Burner:                 ", sender);
        console.log("SBT burned:             ", burnAmount);
        console.log("SBT balance:            ", sbt.balanceOf(sender));
        console.log("Health factor:          ", engine.getHealthFactor(sender));
    }
}
