// SPDX-License-Identifier: MIT

pragma solidity ^0.8.29;

import {Script, console} from "forge-std/Script.sol";
import {Stabletoken} from "../src/Stabletoken.sol";
import {StabletokenEngine} from "../src/StabletokenEngine.sol";

contract Deploy is Script {
    function run() external {
        address wavax = vm.envAddress("WAVAX_ADDRESS");
        address priceFeed = vm.envAddress("AVAX_PRICE_FEED");

        vm.startBroadcast();

        Stabletoken sbt = new Stabletoken();
        StabletokenEngine engine = new StabletokenEngine(wavax, priceFeed, address(sbt));

        sbt.transferOwnership(address(engine));

        vm.stopBroadcast();

        console.log("Stabletoken deployed at:       ", address(sbt));
        console.log("StabletokenEngine deployed at: ", address(engine));
        console.log("Stabletoken owner:             ", sbt.owner());
    }
}
