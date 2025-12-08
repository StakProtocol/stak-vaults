// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/src/Script.sol";
import {FactoryStakVault} from "../src/FactoryStakVault.sol";

contract DeployFactoryStakVault is Script {
    function run() public returns (FactoryStakVault factory) {
        // For simulation: forge script script/DeployFactoryStakVault.s.sol:DeployFactoryStakVault
        // For deployment: forge script script/DeployFactoryStakVault.s.sol:DeployFactoryStakVault --rpc-url <RPC_URL> --private-key <PRIVATE_KEY> --broadcast
        vm.startBroadcast();

        factory = new FactoryStakVault();

        vm.stopBroadcast();

        console.log("Factory deployed at:", address(factory));
    }
}
