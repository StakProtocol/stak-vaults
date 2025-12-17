// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {StakVault} from "./StakVault.sol";

contract VaultFactory {
    event VaultFactory__VaultCreated(address indexed vault);

    function createStakVault(
        address asset,
        string memory name,
        string memory symbol,
        address owner,
        address treasury,
        uint256 performanceRate,
        uint256 vestingStart,
        uint256 vestingEnd,
        uint256 startingPrice,
        uint256 divestFee
    ) external returns (address) {
        // deploy the stak vault
        address vault = address(
            new StakVault(IERC20(asset), name, symbol, owner, treasury, performanceRate, vestingStart, vestingEnd, startingPrice, divestFee)
        );

        emit VaultFactory__VaultCreated(vault);

        return vault;
    }
}
