// SPDX-License-Identifier: MIT

pragma solidity ^0.8.29;

import {Script, console} from "forge-std/Script.sol";
import {StabletokenEngine} from "../src/StabletokenEngine.sol";
import {Stabletoken} from "../src/Stabletoken.sol";

contract Liquidate is Script {
    function run() external {
        address engineAddr = vm.envAddress("STABLETOKEN_ENGINE");
        address sbtAddr = vm.envAddress("STABLETOKEN");
        address user = vm.envAddress("USER_ADDRESS");
        uint256 sbtAmount = vm.envUint("SBT_AMOUNT");

        StabletokenEngine engine = StabletokenEngine(engineAddr);
        Stabletoken sbt = Stabletoken(sbtAddr);

        vm.startBroadcast();

        sbt.approve(engineAddr, sbtAmount);
        engine.liquidate(user);

        vm.stopBroadcast();

        address sender = msg.sender;
        console.log("Liquidator:             ", sender);
        console.log("User liquidated:        ", user);
        console.log("SBT approved:           ", sbtAmount);
        console.log("Liquidator SBT balance: ", sbt.balanceOf(sender));
    }
}
