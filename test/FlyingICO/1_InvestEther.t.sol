// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "./BaseTest.sol";
import {FlyingICO} from "../../src/FlyingICO.sol";

contract FlyingICOInvestEtherTest is BaseTest {
    function test_InvestEther_Success() public {
        uint256 ethAmount = 1 ether; // 1 ETH = $2000 USD
        // Expected tokens: $2000 * 10 tokens/USD = 20000 tokens

        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit FlyingICO__Invested(user1, 0, address(0), ethAmount, 20000e18);

        uint256 positionId = ico.investEther{value: ethAmount}();

        assertEq(positionId, 0);
        assertEq(ico.nextPositionId(), 1);

        (address user, address asset, uint256 assetAmount, uint256 tokenAmount,) = ico.positions(positionId);
        assertEq(user, user1);
        assertEq(asset, address(0));
        assertEq(assetAmount, ethAmount);
        assertEq(tokenAmount, 20000e18);

        assertEq(ico.backingBalances(address(0)), ethAmount);
        assertEq(ico.balanceOf(address(ico)), 20000e18);
        assertEq(ico.totalSupply(), 20000e18);

        uint256[] memory positions = ico.positionsOfUser(user1);
        assertEq(positions.length, 1);
        assertEq(positions[0], 0);
    }

    function test_InvestEther_MultipleInvestments() public {
        vm.prank(user1);
        uint256 positionId1 = ico.investEther{value: 1 ether}();

        vm.prank(user1);
        uint256 positionId2 = ico.investEther{value: 0.5 ether}();

        assertEq(positionId1, 0);
        assertEq(positionId2, 1);

        uint256[] memory positions = ico.positionsOfUser(user1);
        assertEq(positions.length, 2);
        assertEq(positions[0], 0);
        assertEq(positions[1], 1);
    }

    function test_InvestEther_RevertWhen_ZeroValue() public {
        vm.prank(user1);
        vm.expectRevert(FlyingICO.FlyingICO__ZeroValue.selector);
        ico.investEther{value: 0}();
    }

    function test_InvestEther_RevertWhen_TokensCapExceeded() public {
        // Invest enough to exceed cap
        // Cap is 1M tokens = 1e6 * 1e18 = 1e24
        // At $2000/ETH and 10 tokens/USD, 1 ETH = 20000 tokens
        // Need 1e24 / 20000e18 = 50,000 ETH

        // This would require too much ETH, so let's test with a lower cap
        address[] memory acceptedAssets = new address[](1);
        acceptedAssets[0] = address(0);

        address[] memory priceFeeds = new address[](1);
        priceFeeds[0] = address(ethPriceFeed);

        uint256[] memory testFrequencies = new uint256[](1);
        testFrequencies[0] = 1 hours;

        FlyingICO smallCapIco = new FlyingICO(
            "Small Cap",
            "SMALL",
            100, // 100 tokens cap
            10,
            acceptedAssets,
            priceFeeds,
            testFrequencies,
            sequencer,
            treasury,
            vestingStart,
            vestingEnd
        );

        // 1 ETH = 20000 tokens, but cap is only 100 tokens
        vm.prank(user1);
        vm.expectRevert(FlyingICO.FlyingICO__TokensCapExceeded.selector);
        smallCapIco.investEther{value: 1 ether}();
    }
}

