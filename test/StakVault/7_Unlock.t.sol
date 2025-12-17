// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "./BaseTest.sol";
import {StakVault} from "../../src/StakVault.sol";

contract StakVaultUnlockTest is BaseTest {
    function test_Unlock_Success_BeforeVesting() public {
        // Deposit
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        uint256 sharesMinted = vault.deposit(1000e18, user1);
        vm.stopPrank();
        // With 10:1 NAV, shares ≈ 100e18

        uint256 positionId = 0;
        uint256 sharesToUnlock = sharesMinted / 2; // Half of shares
        uint256 expectedAssetAmount = 500e18; // Half of 1000e18 assets

        vm.startPrank(user1);
        vm.expectEmit(true, true, false, false); // Allow rounding in assetAmount
        emit StakVault__Unlocked(user1, positionId, expectedAssetAmount, sharesToUnlock);
        uint256 assetAmount = vault.unlock(positionId, sharesToUnlock);
        vm.stopPrank();

        // Allow for rounding
        assertGe(assetAmount, expectedAssetAmount - 10);
        assertLe(assetAmount, expectedAssetAmount + 10);
        assertEq(vault.balanceOf(user1), sharesToUnlock);
        // Remaining shares in vault (initial share is in address(1))
        uint256 expectedRemainingShares = sharesMinted - sharesToUnlock;
        assertGe(vault.balanceOf(address(vault)), expectedRemainingShares - 1);
        assertLe(vault.balanceOf(address(vault)), expectedRemainingShares + 1);

        (address posUser, uint256 assetAmountPos, uint256 shareAmount, uint256 vestingAmount) =
            vault.positions(positionId);
        assertEq(posUser, user1);
        assertGe(assetAmountPos, expectedAssetAmount - 10);
        assertLe(assetAmountPos, expectedAssetAmount + 10);
        assertGe(shareAmount, sharesMinted / 2 - 1);
        assertLe(shareAmount, sharesMinted / 2 + 1);
        assertGe(vestingAmount, sharesMinted / 2 - 1);
        assertLe(vestingAmount, sharesMinted / 2 + 1); // Reduced because before vesting
    }

    function test_Unlock_Success_DuringVesting() public {
        // Deposit
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        uint256 sharesMinted = vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Move to middle of vesting
        vm.warp(vestingStart + 15 days);

        uint256 positionId = 0;
        uint256 sharesToUnlock = sharesMinted / 2; // Half of shares
        uint256 expectedAssetAmount = 500e18; // Half of 1000e18 assets

        vm.startPrank(user1);
        uint256 assetAmount = vault.unlock(positionId, sharesToUnlock);
        vm.stopPrank();

        // Allow for rounding
        assertGe(assetAmount, expectedAssetAmount - 10);
        assertLe(assetAmount, expectedAssetAmount + 10);
        assertEq(vault.balanceOf(user1), sharesToUnlock);

        (,, uint256 shareAmount, uint256 vestingAmount) = vault.positions(positionId);
        assertGe(shareAmount, sharesMinted / 2 - 1);
        assertLe(shareAmount, sharesMinted / 2 + 1);
        assertEq(vestingAmount, sharesMinted); // Not reduced during vesting
    }

    function test_Unlock_Success_AllShares() public {
        // Deposit
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        uint256 sharesMinted = vault.deposit(1000e18, user1);
        vm.stopPrank();

        uint256 positionId = 0;

        vm.startPrank(user1);
        uint256 assetAmount = vault.unlock(positionId, sharesMinted);
        vm.stopPrank();

        assertGe(assetAmount, 1000e18 - 10);
        assertLe(assetAmount, 1000e18 + 10);
        assertEq(vault.balanceOf(user1), sharesMinted);
        // All user shares unlocked, vault should have 0 (initial share is in address(1))
        assertEq(vault.balanceOf(address(vault)), 0);

        (,, uint256 shareAmount, uint256 vestingAmount) = vault.positions(positionId);
        assertEq(shareAmount, 0);
        assertEq(vestingAmount, 0);
    }

    function test_Unlock_RevertWhen_NotOwner() public {
        // Deposit
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Get actual share amount
        (,, uint256 shareAmount,) = vault.positions(0);

        vm.startPrank(user2);
        vm.expectRevert(StakVault.StakVault__Unauthorized.selector);
        vault.unlock(0, shareAmount / 2);
        vm.stopPrank();
    }

    function test_Unlock_RevertWhen_NotEnoughLocked() public {
        // Deposit
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        uint256 sharesMinted = vault.deposit(1000e18, user1);
        vm.stopPrank();

        vm.startPrank(user1);
        vm.expectRevert(StakVault.StakVault__NotEnoughLockedShares.selector);
        vault.unlock(0, sharesMinted + 1);
        vm.stopPrank();
    }

    function test_Unlock_RevertWhen_ZeroShares() public {
        // Deposit
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        vm.startPrank(user1);
        vm.expectRevert(StakVault.StakVault__ZeroValue.selector);
        vault.unlock(0, 0);
        vm.stopPrank();
    }

    function test_Unlock_WorksAfterNavEnabled() public {
        // Deposit
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        uint256 sharesMinted = vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Enable NAV
        vm.prank(owner);
        vault.enableRedeemsAtNav();

        // Unlock should still work
        uint256 sharesToUnlock = sharesMinted / 2;
        vm.startPrank(user1);
        uint256 assetAmount = vault.unlock(0, sharesToUnlock);
        vm.stopPrank();

        assertGe(assetAmount, 500e18 - 10);
        assertLe(assetAmount, 500e18 + 10);
        assertEq(vault.balanceOf(user1), sharesToUnlock);
    }

    function test_Unlock_MultiplePositions() public {
        // Create two positions
        vm.startPrank(user1);
        asset.approve(address(vault), 2000e18);
        uint256 shares1 = vault.deposit(1000e18, user1);
        uint256 shares2 = vault.deposit(500e18, user1);
        vm.stopPrank();

        // Get actual share amounts
        (,, uint256 shareAmount1Initial,) = vault.positions(0);
        (,, uint256 shareAmount2Initial,) = vault.positions(1);

        // Unlock half from first position
        vm.startPrank(user1);
        vault.unlock(0, shareAmount1Initial / 2);
        vm.stopPrank();

        // Unlock half from second position
        vm.startPrank(user1);
        vault.unlock(1, shareAmount2Initial / 2);
        vm.stopPrank();

        assertEq(vault.balanceOf(user1), shareAmount1Initial / 2 + shareAmount2Initial / 2);

        (,, uint256 shareAmount1,) = vault.positions(0);
        (,, uint256 shareAmount2,) = vault.positions(1);
        assertGe(shareAmount1, shareAmount1Initial / 2 - 1);
        assertLe(shareAmount1, shareAmount1Initial / 2 + 1);
        assertGe(shareAmount2, shareAmount2Initial / 2 - 1);
        assertLe(shareAmount2, shareAmount2Initial / 2 + 1);
    }
}
