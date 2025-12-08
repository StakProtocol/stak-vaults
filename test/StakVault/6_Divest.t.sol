// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "./BaseTest.sol";
import {StakVault} from "../../src/StakVault.sol";

contract StakVaultDivestTest is BaseTest {
    function test_Divest_Success_BeforeVesting() public {
        // Deposit
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        uint256 positionId = 0;
        uint256 sharesToBurn = 500e18;
        uint256 userBalanceBefore = asset.balanceOf(user1);
        uint256 backingBefore = vault.backingBalance();

        vm.startPrank(user1);
        vm.expectEmit(true, true, false, true);
        emit StakVault__Divested(user1, positionId, sharesToBurn, 500e18);
        uint256 assetAmount = vault.divest(positionId, sharesToBurn);
        vm.stopPrank();

        assertEq(assetAmount, 500e18);
        assertEq(asset.balanceOf(user1), userBalanceBefore + 500e18);
        assertEq(vault.balanceOf(address(vault)), 500e18);
        assertEq(vault.backingBalance(), backingBefore - 500e18);

        (address posUser, uint256 posAssetAmount, uint256 shareAmount, uint256 vestingAmount) =
            vault.positions(positionId);
        assertEq(posUser, user1);
        assertEq(posAssetAmount, 500e18);
        assertEq(shareAmount, 500e18);
        assertEq(vestingAmount, 500e18); // Reduced because before vesting
    }

    function test_Divest_Success_DuringVesting() public {
        // Deposit
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Move to middle of vesting period
        vm.warp(vestingStart + 15 days);

        uint256 positionId = 0;
        uint256 divestible = vault.divestibleShares(positionId);
        uint256 sharesToBurn = divestible / 2;

        vm.startPrank(user1);
        uint256 assetAmount = vault.divest(positionId, sharesToBurn);
        vm.stopPrank();

        assertGt(assetAmount, 0);
        assertLt(assetAmount, 500e18); // Less than half because vesting

        (,,, uint256 vestingAmount) = vault.positions(positionId);
        assertEq(vestingAmount, 1000e18); // Not reduced during vesting
    }

    function test_Divest_Success_AllShares() public {
        // Deposit
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        uint256 positionId = 0;

        vm.startPrank(user1);
        uint256 assetAmount = vault.divest(positionId, 1000e18);
        vm.stopPrank();

        assertEq(assetAmount, 1000e18);
        assertEq(vault.balanceOf(address(vault)), 0);

        (,, uint256 shareAmount, uint256 vestingAmount) = vault.positions(positionId);
        assertEq(shareAmount, 0);
        assertEq(vestingAmount, 0);
    }

    function test_Divest_RevertWhen_NavEnabled() public {
        // Deposit
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Enable NAV
        vm.prank(owner);
        vault.enableRedeemsAtNav();

        vm.startPrank(user1);
        vm.expectRevert(StakVault.StakVault__RedeemsAtNavAlreadyEnabled.selector);
        vault.divest(0, 500e18);
        vm.stopPrank();
    }

    function test_Divest_RevertWhen_NotOwner() public {
        // Deposit
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        vm.startPrank(user2);
        vm.expectRevert(StakVault.StakVault__Unauthorized.selector);
        vault.divest(0, 500e18);
        vm.stopPrank();
    }

    function test_Divest_RevertWhen_NotEnoughDivestible() public {
        // Deposit
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Move to after vesting
        vm.warp(vestingEnd + 1 days);

        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(StakVault.StakVault__NotEnoughDivestibleShares.selector, 0, 500e18, 0));
        vault.divest(0, 500e18);
        vm.stopPrank();
    }

    function test_Divest_RevertWhen_NotEnoughLocked() public {
        // Deposit
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        vm.startPrank(user1);
        // This will revert with NotEnoughDivestibleShares first (before NotEnoughLockedShares)
        vm.expectRevert(
            abi.encodeWithSelector(StakVault.StakVault__NotEnoughDivestibleShares.selector, 0, 1001e18, 1000e18)
        );
        vault.divest(0, 1001e18);
        vm.stopPrank();
    }

    function test_Divest_RevertWhen_ZeroShares() public {
        // Deposit
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        vm.startPrank(user1);
        vm.expectRevert(StakVault.StakVault__ZeroValue.selector);
        vault.divest(0, 0);
        vm.stopPrank();
    }

    function test_Divest_MultiplePositions() public {
        // Create two positions
        vm.startPrank(user1);
        asset.approve(address(vault), 2000e18);
        vault.deposit(1000e18, user1);
        vault.deposit(500e18, user1);
        vm.stopPrank();

        // Divest from first position
        vm.startPrank(user1);
        vault.divest(0, 500e18);
        vm.stopPrank();

        // Divest from second position
        vm.startPrank(user1);
        vault.divest(1, 250e18);
        vm.stopPrank();

        (,, uint256 shareAmount1,) = vault.positions(0);
        (,, uint256 shareAmount2,) = vault.positions(1);
        assertEq(shareAmount1, 500e18);
        assertEq(shareAmount2, 250e18);
    }
}

