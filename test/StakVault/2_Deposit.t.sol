// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "./BaseTest.sol";
import {StakVault} from "../../src/StakVault.sol";

contract StakVaultDepositTest is BaseTest {
    function test_Deposit_Success_BeforeNav() public {
        uint256 depositAmount = 1000e18;

        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);

        vm.expectEmit(true, true, false, true);
        emit StakVault__Invested(user1, 0, depositAmount, depositAmount);

        uint256 shares = vault.deposit(depositAmount, user1);
        vm.stopPrank();

        assertEq(shares, depositAmount);
        assertEq(vault.balanceOf(address(vault)), depositAmount);
        assertEq(vault.balanceOf(user1), 0);
        assertEq(asset.balanceOf(address(vault)), depositAmount);
        assertEq(vault.backingBalance(), depositAmount);

        (uint256 assets, uint256 userShares) = getLedger(user1);
        assertEq(assets, depositAmount);
        assertEq(userShares, depositAmount);

        uint256[] memory positions = vault.positionsOf(user1);
        assertEq(positions.length, 1);
        assertEq(positions[0], 0);
    }

    function test_Deposit_Success_AfterNav() public {
        vm.prank(owner);
        vault.enableRedeemsAtNav();

        uint256 depositAmount = 1000e18;

        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, user1);
        vm.stopPrank();

        assertEq(shares, depositAmount);
        assertEq(vault.balanceOf(user1), depositAmount);
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

        assertEq(vault.balanceOf(address(vault)), 1500e18);
        assertEq(vault.backingBalance(), 1500e18);

        (uint256 assets1, uint256 shares1) = getLedger(user1);
        assertEq(assets1, 1000e18);
        assertEq(shares1, 1000e18);

        (uint256 assets2, uint256 shares2) = getLedger(user2);
        assertEq(assets2, 500e18);
        assertEq(shares2, 500e18);
    }

    function test_Deposit_MultipleTimes_SameUser() public {
        vm.startPrank(user1);
        asset.approve(address(vault), 2000e18);
        vault.deposit(1000e18, user1);
        vault.deposit(500e18, user1);
        vm.stopPrank();

        assertEq(vault.balanceOf(address(vault)), 1500e18);
        assertEq(vault.backingBalance(), 1500e18);

        uint256[] memory positions = vault.positionsOf(user1);
        assertEq(positions.length, 2);

        (uint256 assets, uint256 shares) = getLedger(user1);
        assertEq(assets, 1500e18);
        assertEq(shares, 1500e18);
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
        // totalAssets = 1500e18 (balance) + 1000e18 (invested) = 2500e18
        // totalSupply = 500e18 (from first deposit)
        // Shares will be calculated by ERC4626 formula
        assertGt(shares, 0);

        // Verify position was created
        (address posUser, uint256 assetAmount, uint256 shareAmount,) = vault.positions(1);
        assertEq(posUser, user1);
        assertEq(assetAmount, 1000e18);
        assertEq(shareAmount, shares);
    }
}

