// SPDX-License-Identifier: MIT

pragma solidity ^0.8.29;

import {Script, console} from "forge-std/Script.sol";
import {Stabletoken} from "../src/Stabletoken.sol";
import {StabletokenEngine} from "../src/StabletokenEngine.sol";

contract Deploy is Script {
    function run() external {
        address wavax = vm.envAddress("WAVAX_ADDRESS");
        address weth = vm.envAddress("WETH_ADDRESS");
        address avaxFeed = vm.envAddress("AVAX_PRICE_FEED");
        address ethFeed = vm.envAddress("ETH_PRICE_FEED");

        address[] memory collaterals = new address[](2);
        collaterals[0] = wavax;
        collaterals[1] = weth;

        address[] memory feeds = new address[](2);
        feeds[0] = avaxFeed;
        feeds[1] = ethFeed;

        vm.startBroadcast();

        Stabletoken sbt = new Stabletoken();
        StabletokenEngine engine = new StabletokenEngine(collaterals, feeds, address(sbt));

        sbt.transferOwnership(address(engine));

        vm.stopBroadcast();

        console.log("Stabletoken deployed at:       ", address(sbt));
        console.log("StabletokenEngine deployed at: ", address(engine));
        console.log("Stabletoken owner:             ", sbt.owner());
    }
}
