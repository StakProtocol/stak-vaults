// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/src/Script.sol";
import {FactoryStakeVault} from "../src/FactoryStakeVault.sol";

contract DeployFactoryStakeVault is Script {
    function run() public returns (FactoryStakeVault factory) {
        // For simulation: forge script script/DeployFactoryStakeVault.s.sol:DeployFactoryStakeVault
        // For deployment: forge script script/DeployFactoryStakeVault.s.sol:DeployFactoryStakeVault --rpc-url <RPC_URL> --private-key <PRIVATE_KEY> --broadcast
        vm.startBroadcast();

        factory = new FactoryStakeVault();

        vm.stopBroadcast();

        console.log("Factory deployed at:", address(factory));
    }
}
