// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "./BaseTest.sol";
import {StakVault} from "../../src/StakVault.sol";

contract StakVaultWithdrawTest is BaseTest {
    function test_Withdraw_Success() public {
        // Deposit first
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Unlock shares to user
        vm.startPrank(user1);
        vault.unlock(0, 1000e18);
        vm.stopPrank();

        // Enable NAV
        vm.prank(owner);
        vault.enableRedeemsAtNav();

        // Withdraw
        uint256 assetsToWithdraw = 500e18;
        uint256 userBalanceBefore = asset.balanceOf(user1);

        vm.startPrank(user1);
        uint256 shares = vault.withdraw(assetsToWithdraw, user1, user1);
        vm.stopPrank();

        assertEq(asset.balanceOf(user1), userBalanceBefore + assetsToWithdraw);
        assertLe(shares, 500e18); // At most 1:1, might be less with NAV
        assertEq(vault.balanceOf(user1), 1000e18 - shares);
    }

    function test_Withdraw_Success_WithNav() public {
        // Deposit
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Unlock shares to user
        vm.startPrank(user1);
        vault.unlock(0, 1000e18);
        vm.stopPrank();

        // Add assets and set invested assets
        asset.mint(address(vault), 1000e18);
        vm.prank(owner);
        vault.updateInvestedAssets(2000e18);

        // Enable NAV
        vm.prank(owner);
        vault.enableRedeemsAtNav();

        // Withdraw
        uint256 assetsToWithdraw = 1000e18;
        vm.startPrank(user1);
        uint256 shares = vault.withdraw(assetsToWithdraw, user1, user1);
        vm.stopPrank();

        // Should burn fewer shares due to NAV increase
        assertLt(shares, 1000e18);
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
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        vm.prank(owner);
        vault.enableRedeemsAtNav();

        vm.startPrank(user1);
        vm.expectRevert();
        vault.withdraw(1001e18, user1, user1);
        vm.stopPrank();
    }

    function test_Withdraw_AllAssets() public {
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Unlock shares to user
        vm.startPrank(user1);
        vault.unlock(0, 1000e18);
        vm.stopPrank();

        vm.prank(owner);
        vault.enableRedeemsAtNav();

        vm.startPrank(user1);
        uint256 shares = vault.withdraw(1000e18, user1, user1);
        vm.stopPrank();

        assertEq(vault.balanceOf(user1), 1000e18 - shares);
        assertLe(shares, 1000e18);
    }

    function test_Withdraw_WithDelegation() public {
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Unlock shares to user
        vm.startPrank(user1);
        vault.unlock(0, 1000e18);
        vault.approve(user2, 1000e18);
        vm.stopPrank();

        vm.prank(owner);
        vault.enableRedeemsAtNav();

        vm.startPrank(user2);
        uint256 shares = vault.withdraw(500e18, user2, user1);
        vm.stopPrank();

        assertEq(vault.balanceOf(user1), 1000e18 - shares);
        assertEq(asset.balanceOf(user2), 1000000e18 + 500e18);
    }
}

