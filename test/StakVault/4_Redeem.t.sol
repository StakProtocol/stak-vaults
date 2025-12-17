// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "./BaseTest.sol";
import {StakVault} from "../../src/StakVault.sol";

contract StakVaultRedeemTest is BaseTest {
    function test_Redeem_Success() public {
        // Deposit first
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        uint256 sharesMinted = vault.deposit(1000e18, user1);
        vm.stopPrank();
        // With 10:1 NAV, shares ≈ 100e18

        // Unlock shares to user
        vm.startPrank(user1);
        vault.unlock(0, sharesMinted);
        vm.stopPrank();

        // Enable NAV
        vm.prank(owner);
        vault.enableRedeemsAtNav();

        // Redeem half the shares
        uint256 sharesToRedeem = sharesMinted / 2;
        uint256 userBalanceBefore = asset.balanceOf(user1);
        uint256 userSharesBefore = vault.balanceOf(user1);

        vm.startPrank(user1);
        uint256 assets = vault.redeem(sharesToRedeem, user1, user1);
        vm.stopPrank();

        assertEq(asset.balanceOf(user1), userBalanceBefore + assets);
        assertEq(vault.balanceOf(user1), userSharesBefore - sharesToRedeem);
        assertGe(assets, sharesToRedeem); // At least 1:1, might be more with NAV
    }

    function test_Redeem_Success_WithNav() public {
        // Deposit
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        uint256 sharesMinted = vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Unlock shares to user
        vm.startPrank(user1);
        vault.unlock(0, sharesMinted);
        vm.stopPrank();

        // Add assets to vault (need enough for redemption)
        asset.mint(address(vault), 2000e18);

        // Set invested assets to create NAV
        vm.prank(owner);
        vault.updateInvestedAssets(2000e18);

        // Enable NAV
        vm.prank(owner);
        vault.enableRedeemsAtNav();

        // Redeem half the shares
        uint256 sharesToRedeem = sharesMinted / 2;
        vm.startPrank(user1);
        uint256 assets = vault.redeem(sharesToRedeem, user1, user1);
        vm.stopPrank();

        // Should get more assets due to NAV increase
        assertGt(assets, sharesToRedeem);
    }

    function test_Redeem_RevertWhen_NotEnabled() public {
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        vm.startPrank(user1);
        vm.expectRevert(StakVault.StakVault__RedeemsAtNavNotEnabled.selector);
        vault.redeem(100e18, user1, user1);
        vm.stopPrank();
    }

    function test_Redeem_RevertWhen_ExceedsBalance() public {
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        uint256 sharesMinted = vault.deposit(1000e18, user1);
        vm.stopPrank();

        vm.prank(owner);
        vault.enableRedeemsAtNav();

        vm.startPrank(user1);
        vm.expectRevert();
        vault.redeem(sharesMinted + 1, user1, user1);
        vm.stopPrank();
    }

    function test_Redeem_AllShares() public {
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

        vm.startPrank(user1);
        uint256 assets = vault.redeem(sharesMinted, user1, user1);
        vm.stopPrank();

        assertEq(vault.balanceOf(user1), 0);
        assertGe(assets, sharesMinted);
    }

    function test_Redeem_WithDelegation() public {
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        uint256 sharesMinted = vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Unlock shares to user
        vm.startPrank(user1);
        vault.unlock(0, sharesMinted);
        uint256 sharesToDelegate = sharesMinted / 2;
        vault.approve(user2, sharesToDelegate);
        vm.stopPrank();

        vm.prank(owner);
        vault.enableRedeemsAtNav();

        vm.startPrank(user2);
        uint256 assets = vault.redeem(sharesToDelegate, user2, user1);
        vm.stopPrank();

        assertEq(vault.balanceOf(user1), sharesMinted - sharesToDelegate);
        assertEq(asset.balanceOf(user2), 1000000e18 + assets);
    }
}
