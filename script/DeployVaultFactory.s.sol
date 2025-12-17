// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/src/Script.sol";
import {VaultFactory} from "../src/VaultFactory.sol";

contract DeployVaultFactory is Script {
    function run() public returns (VaultFactory factory) {
        vm.startBroadcast();

        factory = new VaultFactory();

        vm.stopBroadcast();

        console.log("VaultFactory deployed at:", address(factory));
    }
}
