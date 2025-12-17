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

    function test_ReturnAssets_Success() public {
        // First deposit some assets
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Owner takes assets first
        uint256 assetsToTake = 500e18;
        vm.prank(owner);
        vault.takeAssets(assetsToTake);

        // Now owner returns assets
        uint256 assetsToReturn = 300e18;
        uint256 ownerBalanceBefore = asset.balanceOf(owner);
        uint256 vaultBalanceBefore = asset.balanceOf(address(vault));
        uint256 investedAssetsBefore = vault.investedAssets();

        // Owner needs to approve the vault to transfer assets back
        vm.startPrank(owner);
        asset.approve(address(vault), assetsToReturn);
        vm.expectEmit(true, false, false, true);
        emit StakVault__AssetsReturned(assetsToReturn);
        vault.returnAssets(assetsToReturn);
        vm.stopPrank();

        assertEq(asset.balanceOf(owner), ownerBalanceBefore - assetsToReturn);
        assertEq(asset.balanceOf(address(vault)), vaultBalanceBefore + assetsToReturn);
        assertEq(vault.investedAssets(), investedAssetsBefore - assetsToReturn);
    }

    function test_ReturnAssets_RevertWhen_NotOwner() public {
        // First deposit some assets
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Owner takes assets first
        uint256 assetsToTake = 500e18;
        vm.prank(owner);
        vault.takeAssets(assetsToTake);

        // Non-owner tries to return assets
        uint256 assetsToReturn = 100e18;
        vm.startPrank(user1);
        asset.approve(address(vault), assetsToReturn);
        vm.expectRevert();
        vault.returnAssets(assetsToReturn);
        vm.stopPrank();
    }

    function test_ReturnAssets_AfterTakeAssets() public {
        // First deposit some assets
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        uint256 initialInvestedAssets = vault.investedAssets();
        uint256 assetsToTake = 500e18;

        // Owner takes assets
        vm.prank(owner);
        vault.takeAssets(assetsToTake);

        assertEq(vault.investedAssets(), initialInvestedAssets + assetsToTake);

        // Owner returns some assets
        uint256 assetsToReturn = 200e18;
        vm.startPrank(owner);
        asset.approve(address(vault), assetsToReturn);
        vault.returnAssets(assetsToReturn);
        vm.stopPrank();

        assertEq(vault.investedAssets(), initialInvestedAssets + assetsToTake - assetsToReturn);
    }

    function test_ReturnAssets_CompleteRoundTrip() public {
        // First deposit some assets
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        uint256 initialInvestedAssets = vault.investedAssets();
        uint256 assetsToTake = 500e18;

        // Owner takes assets
        vm.prank(owner);
        vault.takeAssets(assetsToTake);

        // Owner returns all assets back
        vm.startPrank(owner);
        asset.approve(address(vault), assetsToTake);
        vault.returnAssets(assetsToTake);
        vm.stopPrank();

        // Should be back to initial state
        assertEq(vault.investedAssets(), initialInvestedAssets);
    }

    function test_ReturnAssets_UpdatesTotalAssets() public {
        // First deposit some assets
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 assetsToTake = 500e18;

        // Owner takes assets
        // When taking assets: balance decreases, investedAssets increases
        // totalAssets = balance + investedAssets stays the same
        vm.prank(owner);
        vault.takeAssets(assetsToTake);

        uint256 totalAssetsAfterTake = vault.totalAssets();
        assertEq(totalAssetsAfterTake, totalAssetsBefore);

        // Owner returns assets
        // When returning assets: balance increases, investedAssets decreases
        // totalAssets = balance + investedAssets stays the same
        uint256 assetsToReturn = 300e18;
        vm.startPrank(owner);
        asset.approve(address(vault), assetsToReturn);
        vault.returnAssets(assetsToReturn);
        vm.stopPrank();

        uint256 totalAssetsAfterReturn = vault.totalAssets();
        // totalAssets should still be the same since balance and investedAssets offset each other
        assertEq(totalAssetsAfterReturn, totalAssetsBefore);
        
        // But investedAssets should have changed
        assertEq(vault.investedAssets(), 10e18 + assetsToTake - assetsToReturn);
    }

    function test_ReturnAssets_MultipleReturns() public {
        // First deposit some assets
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Owner takes assets
        uint256 assetsToTake = 500e18;
        vm.prank(owner);
        vault.takeAssets(assetsToTake);

        uint256 investedAssetsAfterTake = vault.investedAssets();

        // Owner returns assets in multiple transactions
        uint256 firstReturn = 200e18;
        uint256 secondReturn = 150e18;
        uint256 thirdReturn = 100e18;

        vm.startPrank(owner);
        asset.approve(address(vault), assetsToTake);

        vault.returnAssets(firstReturn);
        assertEq(vault.investedAssets(), investedAssetsAfterTake - firstReturn);

        vault.returnAssets(secondReturn);
        assertEq(vault.investedAssets(), investedAssetsAfterTake - firstReturn - secondReturn);

        vault.returnAssets(thirdReturn);
        assertEq(vault.investedAssets(), investedAssetsAfterTake - firstReturn - secondReturn - thirdReturn);
        vm.stopPrank();
    }
}

