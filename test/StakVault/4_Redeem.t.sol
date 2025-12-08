// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "./BaseTest.sol";
import {StakVault} from "../../src/StakVault.sol";

contract StakVaultRedeemTest is BaseTest {
    function test_Redeem_Success() public {
        // Deposit first
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Enable NAV - this transfers shares from contract to user
        vm.prank(owner);
        vault.enableRedeemsAtNav();

        // Transfer shares from contract to user (simulating what would happen)
        // Actually, when NAV is enabled, new deposits go to user, but old shares stay in contract
        // So we need to unlock or the shares need to be transferred
        // For this test, let's unlock first, then enable NAV
        vm.startPrank(user1);
        vault.unlock(0, 1000e18); // Unlock all shares to user
        vm.stopPrank();

        // Now enable NAV
        vm.prank(owner);
        vault.enableRedeemsAtNav();

        // Redeem
        uint256 sharesToRedeem = 500e18;
        uint256 userBalanceBefore = asset.balanceOf(user1);

        vm.startPrank(user1);
        uint256 assets = vault.redeem(sharesToRedeem, user1, user1);
        vm.stopPrank();

        assertEq(asset.balanceOf(user1), userBalanceBefore + assets);
        assertEq(vault.balanceOf(user1), 500e18);
        assertGe(assets, 500e18); // At least 1:1, might be more with NAV
    }

    function test_Redeem_Success_WithNav() public {
        // Deposit
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Unlock shares to user
        vm.startPrank(user1);
        vault.unlock(0, 1000e18);
        vm.stopPrank();

        // Add assets to vault (need enough for redemption)
        asset.mint(address(vault), 2000e18);

        // Set invested assets to create NAV
        vm.prank(owner);
        vault.updateInvestedAssets(2000e18);

        // Enable NAV
        vm.prank(owner);
        vault.enableRedeemsAtNav();

        // Redeem
        uint256 sharesToRedeem = 500e18;
        vm.startPrank(user1);
        uint256 assets = vault.redeem(sharesToRedeem, user1, user1);
        vm.stopPrank();

        // Should get more assets due to NAV increase
        assertGt(assets, 500e18);
    }

    function test_Redeem_RevertWhen_NotEnabled() public {
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        vm.startPrank(user1);
        vm.expectRevert(StakVault.StakVault__RedeemsAtNavNotEnabled.selector);
        vault.redeem(500e18, user1, user1);
        vm.stopPrank();
    }

    function test_Redeem_RevertWhen_ExceedsBalance() public {
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        vm.prank(owner);
        vault.enableRedeemsAtNav();

        vm.startPrank(user1);
        vm.expectRevert();
        vault.redeem(1001e18, user1, user1);
        vm.stopPrank();
    }

    function test_Redeem_AllShares() public {
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
        uint256 assets = vault.redeem(1000e18, user1, user1);
        vm.stopPrank();

        assertEq(vault.balanceOf(user1), 0);
        assertGe(assets, 1000e18);
    }

    function test_Redeem_WithDelegation() public {
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Unlock shares to user
        vm.startPrank(user1);
        vault.unlock(0, 1000e18);
        vault.approve(user2, 500e18);
        vm.stopPrank();

        vm.prank(owner);
        vault.enableRedeemsAtNav();

        vm.startPrank(user2);
        uint256 assets = vault.redeem(500e18, user2, user1);
        vm.stopPrank();

        assertEq(vault.balanceOf(user1), 500e18);
        assertEq(asset.balanceOf(user2), 1000000e18 + assets);
    }
}

