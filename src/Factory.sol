// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {StakVault} from "./StakVault.sol";
import {FlyingICO} from "./FlyingICO.sol";

contract Factory {
    event Factory__StakVaultCreated(address indexed stakVault);
    event Factory__FlyingIcoCreated(address indexed flyingIco);

    function createStakVault(
        address asset,
        string memory name,
        string memory symbol,
        address owner,
        address treasury,
        uint256 performanceRate,
        uint256 vestingStart,
        uint256 vestingEnd
    ) external returns (address) {
        // deploy the stak vault
        address stakVault = address(
            new StakVault(IERC20(asset), name, symbol, owner, treasury, performanceRate, vestingStart, vestingEnd)
        );

        emit Factory__StakVaultCreated(stakVault);

        return stakVault;
    }

    function createFlyingIco(
        string memory name,
        string memory symbol,
        uint256 tokenCap,
        uint256 tokensPerUsd,
        address[] memory acceptedAssets,
        address[] memory priceFeeds,
        uint256[] memory frequencies,
        address sequencer,
        address treasury,
        uint256 vestingStart,
        uint256 vestingEnd
    ) external returns (address) {
        // deploy the flying ICO
        address flyingIco = address(
            new FlyingICO(
                name,
                symbol,
                tokenCap,
                tokensPerUsd,
                acceptedAssets,
                priceFeeds,
                frequencies,
                sequencer,
                treasury,
                vestingStart,
                vestingEnd
            )
        );

        emit Factory__FlyingIcoCreated(flyingIco);

        return flyingIco;
    }
}
