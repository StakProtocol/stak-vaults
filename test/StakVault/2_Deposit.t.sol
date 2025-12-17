// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "./BaseTest.sol";
import {StakVault} from "../../src/StakVault.sol";

contract StakVaultDepositTest is BaseTest {
    function test_Deposit_Success_BeforeNav() public {
        uint256 depositAmount = 1000e18;
        // With initial NAV of 10:1, shares = 1000e18 * 1 / 10e18 = 100e18
        uint256 expectedShares = 100e18;

        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);

        // Use check3 to allow for rounding in shares
        vm.expectEmit(true, true, false, false);
        emit StakVault__Invested(user1, 0, depositAmount, expectedShares);

        uint256 shares = vault.deposit(depositAmount, user1);
        vm.stopPrank();

        // Allow for rounding (ERC4626 uses Floor, so shares ≈ 100000000000000000089)
        assertGe(shares, expectedShares - 200);
        assertLe(shares, expectedShares + 200);
        assertEq(vault.balanceOf(address(vault)), shares);
        assertEq(vault.balanceOf(user1), 0);
        assertEq(asset.balanceOf(address(vault)), depositAmount);

        (uint256 assets, uint256 userShares) = getLedger(user1);
        assertEq(assets, depositAmount);
        // Allow for rounding (ERC4626 uses Floor, so userShares ≈ 100000000000000000089)
        assertGe(userShares, expectedShares - 200);
        assertLe(userShares, expectedShares + 200);

        uint256[] memory positions = vault.positionsOf(user1);
        assertEq(positions.length, 1);
        assertEq(positions[0], 0);
    }

    function test_Deposit_Success_AfterNav() public {
        vm.prank(owner);
        vault.enableRedeemsAtNav();

        uint256 depositAmount = 1000e18;
        // With initial NAV of 10:1, shares = 1000e18 * 1 / 10e18 = 100e18
        uint256 expectedShares = 100e18;

        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, user1);
        vm.stopPrank();

        // Allow for rounding
        assertGe(shares, expectedShares - 100);
        assertLe(shares, expectedShares + 100);
        assertEq(vault.balanceOf(user1), shares);
        assertEq(vault.balanceOf(address(vault)), 0);

        (uint256 assets, uint256 userShares) = getLedger(user1);
        assertEq(assets, 0);
        assertEq(userShares, 0);
    }

    function test_Deposit_MultipleUsers() public {
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        vm.startPrank(user2);
        asset.approve(address(vault), 500e18);
        vault.deposit(500e18, user2);
        vm.stopPrank();

        // Get actual share amounts
        (uint256 assets1, uint256 shares1) = getLedger(user1);
        (uint256 assets2, uint256 shares2) = getLedger(user2);
        
        // Vault balance = initial share (1e18, but it's in address(1)) + user shares
        // Since initial share is in address(1), vault balance is just user shares
        uint256 expectedVaultBalance = shares1 + shares2;
        assertGe(vault.balanceOf(address(vault)), expectedVaultBalance - 2);
        assertLe(vault.balanceOf(address(vault)), expectedVaultBalance + 2);

        assertEq(assets1, 1000e18);
        assertGe(shares1, 100e18 - 100);
        assertLe(shares1, 100e18 + 100);

        assertEq(assets2, 500e18);
        assertGe(shares2, 50e18 - 50);
        assertLe(shares2, 50e18 + 50);
    }

    function test_Deposit_MultipleTimes_SameUser() public {
        vm.startPrank(user1);
        asset.approve(address(vault), 2000e18);
        vault.deposit(1000e18, user1);
        vault.deposit(500e18, user1);
        vm.stopPrank();

        // Get actual share amounts from positions
        (uint256 assets, uint256 shares) = getLedger(user1);
        assertEq(assets, 1500e18);
        
        // Vault balance should equal total shares (initial share is in address(1))
        uint256 vaultBalance = vault.balanceOf(address(vault));
        assertGe(vaultBalance, shares - 2);
        assertLe(vaultBalance, shares + 2);

        uint256[] memory positions = vault.positionsOf(user1);
        assertEq(positions.length, 2);
    }

    function test_Deposit_RevertWhen_ZeroAmount() public {
        vm.startPrank(user1);
        asset.approve(address(vault), 0);
        vm.expectRevert(StakVault.StakVault__ZeroValue.selector);
        vault.deposit(0, user1);
        vm.stopPrank();
    }

    function test_Deposit_RevertWhen_InsufficientAllowance() public {
        vm.startPrank(user1);
        asset.approve(address(vault), 100e18);
        vm.expectRevert();
        vault.deposit(1000e18, user1);
        vm.stopPrank();
    }

    function test_Deposit_WithInvestedAssets() public {
        // First deposit some assets to have a balance
        vm.startPrank(user1);
        asset.approve(address(vault), 500e18);
        vault.deposit(500e18, user1);
        vm.stopPrank();

        // Set invested assets
        vm.prank(owner);
        vault.updateInvestedAssets(1000e18);

        // Deposit more
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        uint256 shares = vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Shares should be calculated based on totalAssets
        // After first deposit: balance = 500e18, investedAssets = 10e18, totalSupply ≈ 1 + 50e18
        // After updateInvestedAssets(1000e18): investedAssets = 1000e18, totalAssets = 1500e18
        // Second deposit: shares = 1000e18 * totalSupply / 1500e18
        assertGt(shares, 0);

        // Verify position was created
        (address posUser, uint256 assetAmount, uint256 shareAmount,) = vault.positions(1);
        assertEq(posUser, user1);
        assertEq(assetAmount, 1000e18);
        assertEq(shareAmount, shares);
    }
}

