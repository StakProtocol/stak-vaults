// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {FlyingICO} from "./FlyingICO.sol";

contract FactoryFlyingICO {
    event Factory__FlyingIcoCreated(address indexed flyingIco);

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
