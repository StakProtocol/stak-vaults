// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

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
        address redeemableVault,
        address vestingVault,
        uint256 performanceRate,
        uint256 vestingStart,
        uint256 vestingEnd,
        uint256 redemptionFee,
        uint256 maxSlippage
    ) external returns (address vault) {
        vault = address(
            new StakVault(
                IERC20(asset),
                name,
                symbol,
                owner,
                treasury,
                redeemableVault,
                vestingVault,
                performanceRate,
                vestingStart,
                vestingEnd,
                redemptionFee,
                maxSlippage
            )
        );
        emit VaultFactory__VaultCreated(vault);
    }
}
