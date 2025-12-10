// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "./BaseTest.sol";

contract StakVaultGetterTest is BaseTest {
    function test_TotalAssets_Initial() public view {
        assertEq(vault.totalAssets(), 0);
    }

    function test_TotalAssets_WithBalance() public {
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        assertEq(vault.totalAssets(), 1000e18);
    }

    function test_TotalAssets_WithInvestedAssets() public {
        vm.prank(owner);
        vault.updateInvestedAssets(2000e18);

        assertEq(vault.totalAssets(), 2000e18);
    }

    function test_TotalAssets_WithBoth() public {
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Add assets to simulate growth before updating
        asset.mint(address(vault), 1000e18);

        vm.prank(owner);
        vault.updateInvestedAssets(2000e18);

        // totalAssets = balance + investedAssets
        // Performance fee might reduce balance
        uint256 totalAssets = vault.totalAssets();
        uint256 balance = asset.balanceOf(address(vault));
        uint256 investedAssets = vault.investedAssets();

        assertEq(totalAssets, balance + investedAssets);
    }

    function test_UtilizationRate_Zero() public view {
        assertEq(vault.utilizationRate(), 0);
    }

    function test_UtilizationRate_Partial() public {
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        vm.prank(owner);
        vault.updateInvestedAssets(500e18);

        // utilization = investedAssets / totalAssets * 10000
        // totalAssets = balance + investedAssets
        // If performance fee was taken, balance might be less
        uint256 utilization = vault.utilizationRate();
        uint256 totalAssets = vault.totalAssets();
        uint256 investedAssets = vault.investedAssets();

        // Recalculate expected: investedAssets / totalAssets * 10000
        uint256 expected = 10000 * investedAssets / totalAssets;
        assertEq(utilization, expected);
    }

    function test_UtilizationRate_Full() public {
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        vm.prank(owner);
        vault.updateInvestedAssets(1000e18);

        // utilization = investedAssets / totalAssets * 10000
        // Performance fee might reduce balance, affecting totalAssets
        uint256 utilization = vault.utilizationRate();
        uint256 totalAssets = vault.totalAssets();
        uint256 investedAssets = vault.investedAssets();

        // Recalculate expected
        uint256 expected = totalAssets > 0 ? 10000 * investedAssets / totalAssets : 0;
        assertEq(utilization, expected);
    }

    function test_PositionsOfUser_Empty() public view {
        uint256[] memory positions = vault.positionsOf(user1);
        assertEq(positions.length, 0);
    }

    function test_PositionsOfUser_WithPositions() public {
        vm.startPrank(user1);
        asset.approve(address(vault), 2000e18);
        vault.deposit(1000e18, user1);
        vault.deposit(500e18, user1);
        vm.stopPrank();

        uint256[] memory positions = vault.positionsOf(user1);
        assertEq(positions.length, 2);
        assertEq(positions[0], 0);
        assertEq(positions[1], 1);
    }

    function test_DivestibleShares_BeforeVesting() public {
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        uint256 divestible = vault.divestibleShares(0);
        assertEq(divestible, 1000e18); // 100% before vesting
    }

    function test_DivestibleShares_DuringVesting() public {
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Move to middle of vesting
        vm.warp(vestingStart + 15 days);

        uint256 divestible = vault.divestibleShares(0);
        assertLt(divestible, 1000e18);
        assertGt(divestible, 0);
    }

    function test_DivestibleShares_AfterVesting() public {
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Move after vesting
        vm.warp(vestingEnd + 1 days);

        uint256 divestible = vault.divestibleShares(0);
        assertEq(divestible, 0); // 0% after vesting
    }

    function test_VestingRate_BeforeVesting() public view {
        uint256 rate = vault.vestingRate();
        assertEq(rate, 10000); // 100%
    }

    function test_VestingRate_DuringVesting() public {
        vm.warp(vestingStart + 15 days);
        uint256 rate = vault.vestingRate();
        assertLt(rate, 10000);
        assertGt(rate, 0);
    }

    function test_VestingRate_AfterVesting() public {
        vm.warp(vestingEnd + 1 days);
        uint256 rate = vault.vestingRate();
        assertEq(rate, 0); // 0%
    }

    function test_VestingRate_ExactStart() public {
        vm.warp(vestingStart);
        uint256 rate = vault.vestingRate();
        assertLe(rate, 10000);
        assertGt(rate, 0);
    }

    function test_VestingRate_ExactEnd() public {
        vm.warp(vestingEnd);
        uint256 rate = vault.vestingRate();
        assertEq(rate, 0);
    }

    function test_Positions_Struct() public {
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        (address posUser, uint256 assetAmount, uint256 shareAmount, uint256 vestingAmount) = vault.positions(0);
        assertEq(posUser, user1);
        assertEq(assetAmount, 1000e18);
        assertEq(shareAmount, 1000e18);
        assertEq(vestingAmount, 1000e18);
    }

    function test_HighWaterMark() public view {
        assertEq(vault.highWaterMark(), 1e18);
    }

    function test_NextPositionId() public {
        assertEq(vault.nextPositionId(), 0);

        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        assertEq(vault.nextPositionId(), 1);
    }
}

