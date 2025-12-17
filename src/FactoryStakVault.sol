// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {StakVault} from "./StakVault.sol";

contract FactoryStakVault {
    event Factory__StakVaultCreated(address indexed stakVault);

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
        address stakVault = address(
            new StakVault(IERC20(asset), name, symbol, owner, treasury, performanceRate, vestingStart, vestingEnd, startingPrice, divestFee)
        );

        emit Factory__StakVaultCreated(stakVault);

        return stakVault;
    }
}
