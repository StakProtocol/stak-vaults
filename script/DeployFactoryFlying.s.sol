// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/src/Script.sol";
import {FactoryFlyingICO} from "../src/FactoryFlyingICO.sol";

contract DeployFactoryFlyingICO is Script {
    function run() public returns (FactoryFlyingICO factory) {
        // For simulation: forge script script/DeployFactoryFlyingICO.s.sol:DeployFactoryFlyingICO
        // For deployment: forge script script/DeployFactoryFlyingICO.s.sol:DeployFactoryFlyingICO --rpc-url <RPC_URL> --private-key <PRIVATE_KEY> --broadcast
        vm.startBroadcast();

        factory = new FactoryFlyingICO();

        vm.stopBroadcast();

        console.log("Factory deployed at:", address(factory));
    }
}
