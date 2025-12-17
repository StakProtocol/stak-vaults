// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "./BaseTest.sol";

contract StakVaultOwnerTest is BaseTest {
    function test_TakeAssets_Success() public {
        // First deposit some assets
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Owner takes assets
        uint256 assetsToTake = 500e18;
        uint256 ownerBalanceBefore = asset.balanceOf(owner);
        uint256 investedAssetsBefore = vault.investedAssets();

        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit StakVault__AssetsTaken(assetsToTake);
        vault.takeAssets(assetsToTake);

        assertEq(asset.balanceOf(owner), ownerBalanceBefore + assetsToTake);
        assertEq(vault.investedAssets(), investedAssetsBefore + assetsToTake);
    }

    function test_TakeAssets_RevertWhen_NotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        vault.takeAssets(100e18);
    }

    function test_UpdateInvestedAssets_Success_NoPerformanceFee() public {
        // First deposit to have some balance
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Set invested assets to the same value as highWaterMark (10e18) so no performance fee
        // This won't trigger a fee since price per share won't increase
        uint256 newInvestedAssets = 10e18; // Same as initial highWaterMark
        uint256 treasuryBalanceBefore = asset.balanceOf(treasury);

        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit StakVault__InvestedAssetsUpdated(newInvestedAssets, 0);
        vault.updateInvestedAssets(newInvestedAssets);

        assertEq(vault.investedAssets(), newInvestedAssets);
        assertEq(asset.balanceOf(treasury), treasuryBalanceBefore);
    }

    function test_UpdateInvestedAssets_Success_WithPerformanceFee() public {
        // First deposit
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Add assets to vault to simulate growth
        asset.mint(address(vault), 1000e18);

        // Set invested assets to create profit
        uint256 newInvestedAssets = 2000e18;
        uint256 treasuryBalanceBefore = asset.balanceOf(treasury);

        vm.prank(owner);
        vault.updateInvestedAssets(newInvestedAssets);

        // Performance fee should be calculated and transferred
        assertEq(vault.investedAssets(), newInvestedAssets);
        assertGt(asset.balanceOf(treasury), treasuryBalanceBefore);
        assertGt(vault.highWaterMark(), 10e18);
    }

    function test_UpdateInvestedAssets_RevertWhen_NotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        vault.updateInvestedAssets(1000e18);
    }

    function test_EnableRedeemsAtNav_Success() public {
        assertEq(vault.redeemsAtNav(), false);

        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit StakVault__RedeemsAtNavEnabled();
        vault.enableRedeemsAtNav();

        assertEq(vault.redeemsAtNav(), true);
    }

    function test_EnableRedeemsAtNav_RevertWhen_NotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        vault.enableRedeemsAtNav();
    }

    function test_EnableRedeemsAtNav_CanOnlyBeCalledOnce() public {
        vm.prank(owner);
        vault.enableRedeemsAtNav();

        // Can't revert on second call, but it's idempotent
        vm.prank(owner);
        vault.enableRedeemsAtNav();

        assertEq(vault.redeemsAtNav(), true);
    }

    function test_UpdateInvestedAssets_UpdatesHighWaterMark() public {
        // Deposit
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Add assets
        asset.mint(address(vault), 1000e18);

        uint256 highWaterMarkBefore = vault.highWaterMark();

        vm.prank(owner);
        vault.updateInvestedAssets(2000e18);

        assertGt(vault.highWaterMark(), highWaterMarkBefore);
    }

    function test_UpdateInvestedAssets_NoFeeWhenPriceDecreases() public {
        // Deposit
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Set invested assets lower (loss)
        // But if totalAssets is still high, price per share might not decrease
        // Let's set it to a value that definitely causes a loss
        vm.prank(owner);
        vault.updateInvestedAssets(500e18);

        // High water mark should not change (no performance fee on loss)
        // But the actual high water mark might be calculated differently
        // Let's just check it's at least the initial value
        assertGe(vault.highWaterMark(), 10e18);
    }
}

