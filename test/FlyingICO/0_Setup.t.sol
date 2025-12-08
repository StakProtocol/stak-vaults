// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "./BaseTest.sol";
import {FlyingICO} from "../../src/FlyingICO.sol";
import {AggregatorV3Interface} from "@chainlink/shared/interfaces/AggregatorV3Interface.sol";

contract FlyingICOSetupTest is BaseTest {
    function test_Constructor_Success() public view {
        (AggregatorV3Interface usdcFeed,) = ico.priceFeeds(address(usdc));
        (AggregatorV3Interface wethFeed,) = ico.priceFeeds(address(weth));
        (AggregatorV3Interface ethFeed,) = ico.priceFeeds(address(0));

        assertEq(address(usdcFeed), address(usdcPriceFeed));
        assertEq(address(wethFeed), address(wethPriceFeed));
        assertEq(address(ethFeed), address(ethPriceFeed));
        assertEq(ico.nextPositionId(), 0);
    }

    function test_Constructor_RevertWhen_InvalidArraysLength() public {
        address[] memory acceptedAssets = new address[](2);
        acceptedAssets[0] = address(usdc);
        acceptedAssets[1] = address(weth);

        address[] memory priceFeeds = new address[](1);
        priceFeeds[0] = address(usdcPriceFeed);

        uint256[] memory testFrequencies = new uint256[](3);
        testFrequencies[0] = 1 hours;
        testFrequencies[1] = 1 hours;
        testFrequencies[2] = 1 hours;

        vm.expectRevert(abi.encodeWithSelector(FlyingICO.InvalidArraysLength.selector, 2, 1, 3));

        new FlyingICO(
            "Flying Token",
            "FLY",
            TOKEN_CAP,
            TOKENS_PER_USD,
            acceptedAssets,
            priceFeeds,
            testFrequencies,
            sequencer,
            treasury,
            vestingStart,
            vestingEnd
        );
    }

    function test_Constructor_EmitsInitialized() public {
        address[] memory acceptedAssets = new address[](1);
        acceptedAssets[0] = address(usdc);

        address[] memory priceFeeds = new address[](1);
        priceFeeds[0] = address(usdcPriceFeed);

        uint256[] memory testFrequencies = new uint256[](1);
        testFrequencies[0] = 1 hours;

        vm.expectEmit(true, true, true, true);
        emit FlyingICO__Initialized(
            "Test Token",
            "TEST",
            TOKEN_CAP,
            TOKENS_PER_USD,
            acceptedAssets,
            priceFeeds,
            testFrequencies,
            sequencer,
            treasury,
            vestingStart,
            vestingEnd
        );

        new FlyingICO(
            "Test Token",
            "TEST",
            TOKEN_CAP,
            TOKENS_PER_USD,
            acceptedAssets,
            priceFeeds,
            testFrequencies,
            sequencer,
            treasury,
            vestingStart,
            vestingEnd
        );
    }

    function test_Constructor_RevertWhen_TreasuryIsZeroAddress() public {
        address[] memory acceptedAssets = new address[](1);
        acceptedAssets[0] = address(usdc);

        address[] memory priceFeeds = new address[](1);
        priceFeeds[0] = address(usdcPriceFeed);

        uint256[] memory testFrequencies = new uint256[](1);
        testFrequencies[0] = 1 hours;

        vm.expectRevert(FlyingICO.FlyingICO__ZeroAddress.selector);

        new FlyingICO(
            "Flying Token",
            "FLY",
            TOKEN_CAP,
            TOKENS_PER_USD,
            acceptedAssets,
            priceFeeds,
            testFrequencies,
            sequencer,
            address(0),
            vestingStart,
            vestingEnd
        );
    }
}

