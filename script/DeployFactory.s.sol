// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/src/Script.sol";
import {Factory} from "../src/Factory.sol";

contract DeployFactory is Script {
    function run() public returns (Factory factory) {
        // For simulation: forge script script/DeployFactory.s.sol:DeployFactory
        // For deployment: forge script script/DeployFactory.s.sol:DeployFactory --rpc-url <RPC_URL> --private-key <PRIVATE_KEY> --broadcast
        vm.startBroadcast();

        factory = new Factory();

        vm.stopBroadcast();

        console.log("Factory deployed at:", address(factory));
    }
}
