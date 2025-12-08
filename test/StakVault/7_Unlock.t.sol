// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "./BaseTest.sol";
import {StakVault} from "../../src/StakVault.sol";

contract StakVaultUnlockTest is BaseTest {
    function test_Unlock_Success_BeforeVesting() public {
        // Deposit
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        uint256 positionId = 0;
        uint256 sharesToUnlock = 500e18;
        uint256 backingBefore = vault.backingBalance();

        vm.startPrank(user1);
        vm.expectEmit(true, true, false, true);
        emit StakVault__Unlocked(user1, positionId, sharesToUnlock, 500e18);
        uint256 assetAmount = vault.unlock(positionId, sharesToUnlock);
        vm.stopPrank();

        assertEq(assetAmount, 500e18);
        assertEq(vault.balanceOf(user1), sharesToUnlock);
        assertEq(vault.balanceOf(address(vault)), 500e18);
        assertEq(vault.backingBalance(), backingBefore - 500e18);

        (address posUser, uint256 assetAmountPos, uint256 shareAmount, uint256 vestingAmount) =
            vault.positions(positionId);
        assertEq(posUser, user1);
        assertEq(assetAmountPos, 500e18);
        assertEq(shareAmount, 500e18);
        assertEq(vestingAmount, 500e18); // Reduced because before vesting
    }

    function test_Unlock_Success_DuringVesting() public {
        // Deposit
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Move to middle of vesting
        vm.warp(vestingStart + 15 days);

        uint256 positionId = 0;
        uint256 sharesToUnlock = 500e18;

        vm.startPrank(user1);
        uint256 assetAmount = vault.unlock(positionId, sharesToUnlock);
        vm.stopPrank();

        assertEq(assetAmount, 500e18);
        assertEq(vault.balanceOf(user1), sharesToUnlock);

        (,, uint256 shareAmount, uint256 vestingAmount) = vault.positions(positionId);
        assertEq(shareAmount, 500e18);
        assertEq(vestingAmount, 1000e18); // Not reduced during vesting
    }

    function test_Unlock_Success_AllShares() public {
        // Deposit
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        uint256 positionId = 0;

        vm.startPrank(user1);
        uint256 assetAmount = vault.unlock(positionId, 1000e18);
        vm.stopPrank();

        assertEq(assetAmount, 1000e18);
        assertEq(vault.balanceOf(user1), 1000e18);
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

        vm.startPrank(user2);
        vm.expectRevert(StakVault.StakVault__Unauthorized.selector);
        vault.unlock(0, 500e18);
        vm.stopPrank();
    }

    function test_Unlock_RevertWhen_NotEnoughLocked() public {
        // Deposit
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        vm.startPrank(user1);
        vm.expectRevert(StakVault.StakVault__NotEnoughLockedShares.selector);
        vault.unlock(0, 1001e18);
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
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Enable NAV
        vm.prank(owner);
        vault.enableRedeemsAtNav();

        // Unlock should still work
        vm.startPrank(user1);
        uint256 assetAmount = vault.unlock(0, 500e18);
        vm.stopPrank();

        assertEq(assetAmount, 500e18);
        assertEq(vault.balanceOf(user1), 500e18);
    }

    function test_Unlock_MultiplePositions() public {
        // Create two positions
        vm.startPrank(user1);
        asset.approve(address(vault), 2000e18);
        vault.deposit(1000e18, user1);
        vault.deposit(500e18, user1);
        vm.stopPrank();

        // Unlock from first position
        vm.startPrank(user1);
        vault.unlock(0, 500e18);
        vm.stopPrank();

        // Unlock from second position
        vm.startPrank(user1);
        vault.unlock(1, 250e18);
        vm.stopPrank();

        assertEq(vault.balanceOf(user1), 750e18);

        (,, uint256 shareAmount1,) = vault.positions(0);
        (,, uint256 shareAmount2,) = vault.positions(1);
        assertEq(shareAmount1, 500e18);
        assertEq(shareAmount2, 250e18);
    }
}

