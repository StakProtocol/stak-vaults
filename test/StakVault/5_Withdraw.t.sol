// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "./BaseTest.sol";
import {StakVault} from "../../src/StakVault.sol";

contract StakVaultWithdrawTest is BaseTest {
    function test_Withdraw_Success() public {
        // Deposit first
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        uint256 sharesMinted = vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Unlock shares to user
        vm.startPrank(user1);
        vault.unlock(0, sharesMinted);
        vm.stopPrank();

        // Enable NAV
        vm.prank(owner);
        vault.enableRedeemsAtNav();

        // Withdraw half the assets (approximately)
        uint256 assetsToWithdraw = 500e18;
        uint256 userBalanceBefore = asset.balanceOf(user1);
        uint256 userSharesBefore = vault.balanceOf(user1);

        vm.startPrank(user1);
        uint256 shares = vault.withdraw(assetsToWithdraw, user1, user1);
        vm.stopPrank();

        assertEq(asset.balanceOf(user1), userBalanceBefore + assetsToWithdraw);
        assertLe(shares, sharesMinted / 2 + 10); // Allow for rounding
        assertEq(vault.balanceOf(user1), userSharesBefore - shares);
    }

    function test_Withdraw_Success_WithNav() public {
        // Deposit
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        uint256 sharesMinted = vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Unlock shares to user
        vm.startPrank(user1);
        vault.unlock(0, sharesMinted);
        vm.stopPrank();

        // Add assets and set invested assets
        asset.mint(address(vault), 1000e18);
        vm.prank(owner);
        vault.updateInvestedAssets(2000e18);

        // Enable NAV
        vm.prank(owner);
        vault.enableRedeemsAtNav();

        // Withdraw all assets
        uint256 assetsToWithdraw = 1000e18;
        vm.startPrank(user1);
        uint256 shares = vault.withdraw(assetsToWithdraw, user1, user1);
        vm.stopPrank();

        // Should burn fewer shares due to NAV increase
        assertLt(shares, sharesMinted);
    }

    function test_Withdraw_RevertWhen_NotEnabled() public {
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        vm.startPrank(user1);
        vm.expectRevert(StakVault.StakVault__RedeemsAtNavNotEnabled.selector);
        vault.withdraw(500e18, user1, user1);
        vm.stopPrank();
    }

    function test_Withdraw_RevertWhen_ExceedsMax() public {
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        uint256 sharesMinted = vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Unlock shares
        vm.startPrank(user1);
        vault.unlock(0, sharesMinted);
        vm.stopPrank();

        vm.prank(owner);
        vault.enableRedeemsAtNav();

        vm.startPrank(user1);
        vm.expectRevert();
        // Try to withdraw more assets than the user can redeem
        vault.withdraw(10000e18, user1, user1);
        vm.stopPrank();
    }

    function test_Withdraw_AllAssets() public {
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        uint256 sharesMinted = vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Unlock shares to user
        vm.startPrank(user1);
        vault.unlock(0, sharesMinted);
        vm.stopPrank();

        vm.prank(owner);
        vault.enableRedeemsAtNav();

        // Get max withdrawable assets
        uint256 maxWithdraw = vault.maxWithdraw(user1);
        vm.startPrank(user1);
        uint256 shares = vault.withdraw(maxWithdraw, user1, user1);
        vm.stopPrank();

        assertEq(vault.balanceOf(user1), sharesMinted - shares);
        assertLe(shares, sharesMinted);
    }

    function test_Withdraw_WithDelegation() public {
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        uint256 sharesMinted = vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Unlock shares to user
        vm.startPrank(user1);
        vault.unlock(0, sharesMinted);
        vault.approve(user2, sharesMinted);
        vm.stopPrank();

        vm.prank(owner);
        vault.enableRedeemsAtNav();

        uint256 assetsToWithdraw = 500e18;
        vm.startPrank(user2);
        uint256 shares = vault.withdraw(assetsToWithdraw, user2, user1);
        vm.stopPrank();

        assertEq(vault.balanceOf(user1), sharesMinted - shares);
        assertEq(asset.balanceOf(user2), 1000000e18 + assetsToWithdraw);
    }
}
