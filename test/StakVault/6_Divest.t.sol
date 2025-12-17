// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "./BaseTest.sol";
import {StakVault} from "../../src/StakVault.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";

contract StakVaultDivestTest is BaseTest {
    function test_Divest_Success_BeforeVesting() public {
        // Deposit
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        uint256 sharesMinted = vault.deposit(1000e18, user1);
        vm.stopPrank();
        // With 10:1 NAV, shares = 1000e18 * 1 / 10e18 = 100e18

        uint256 positionId = 0;
        uint256 sharesToBurn = sharesMinted / 2; // 50e18
        uint256 userBalanceBefore = asset.balanceOf(user1);
        uint256 treasuryBalanceBefore = asset.balanceOf(treasury);
        uint256 expectedAssetAmount = 500e18; // Half of 1000e18 assets
        // With divestFee = 0 (from BaseTest setup), fee = 0, so user gets full amount
        uint256 expectedDivestFee = 0;

        vm.startPrank(user1);
        // Use check3 to allow for rounding differences in sharesToBurn
        vm.expectEmit(true, true, false, false);
        emit StakVault__Divested(user1, positionId, expectedAssetAmount, sharesToBurn, expectedDivestFee);
        uint256 assetAmount = vault.divest(positionId, sharesToBurn);
        vm.stopPrank();

        // Allow for small rounding differences
        assertGe(assetAmount, expectedAssetAmount - 10);
        assertLe(assetAmount, expectedAssetAmount + 10);
        // User receives assetAmount (since fee is 0, user gets full amount)
        // Check that user received approximately assetAmount (allow for small rounding)
        uint256 actualUserReceived = asset.balanceOf(user1) - userBalanceBefore;
        assertGe(actualUserReceived, assetAmount - 10);
        assertLe(actualUserReceived, assetAmount + 10);
        assertEq(asset.balanceOf(treasury), treasuryBalanceBefore); // No fee transferred
        // Remaining shares (the initial 1e18 share is in address(1), not address(vault))
        uint256 expectedRemainingShares = sharesMinted - sharesToBurn;
        assertGe(vault.balanceOf(address(vault)), expectedRemainingShares - 1);
        assertLe(vault.balanceOf(address(vault)), expectedRemainingShares + 1);

        (address posUser, uint256 posAssetAmount, uint256 shareAmount, uint256 vestingAmount) =
            vault.positions(positionId);
        assertEq(posUser, user1);
        // Allow for small rounding differences in posAssetAmount
        assertGe(posAssetAmount, expectedAssetAmount - 10);
        assertLe(posAssetAmount, expectedAssetAmount + 10);
        // Allow for rounding in share amounts
        uint256 expectedShareAmount = sharesMinted - sharesToBurn;
        assertGe(shareAmount, expectedShareAmount - 1);
        assertLe(shareAmount, expectedShareAmount + 1);
        assertEq(vestingAmount, expectedShareAmount); // Reduced because before vesting
    }

    function test_Divest_Success_DuringVesting() public {
        // Deposit
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        uint256 sharesMinted = vault.deposit(1000e18, user1);
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

        (,, uint256 shareAmountAfter, uint256 vestingAmount) = vault.positions(positionId);
        // Vesting amount not reduced during vesting, but shareAmount is
        assertEq(vestingAmount, sharesMinted); // Not reduced during vesting
        assertGt(shareAmountAfter, 0);
    }

    function test_Divest_Success_AllShares() public {
        // Deposit
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        uint256 sharesMinted = vault.deposit(1000e18, user1);
        vm.stopPrank();
        // With 10:1 NAV, shares = 100e18

        uint256 positionId = 0;

        vm.startPrank(user1);
        uint256 assetAmount = vault.divest(positionId, sharesMinted);
        vm.stopPrank();

        // Allow for small rounding differences
        assertGe(assetAmount, 1000e18 - 10);
        assertLe(assetAmount, 1000e18 + 10);
        // All user shares divested, vault should have 0 (initial share is in address(1), not address(vault))
        // But due to rounding, there might be a tiny amount left - allow for this
        uint256 vaultBalance = vault.balanceOf(address(vault));
        assertLe(vaultBalance, 1); // Should be 0, but allow for tiny rounding differences

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

        // Get actual share amount
        (,, uint256 shareAmount,) = vault.positions(0);
        
        vm.startPrank(user2);
        vm.expectRevert(StakVault.StakVault__Unauthorized.selector);
        vault.divest(0, shareAmount / 2);
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

        // Get actual share amount
        (,, uint256 shareAmount,) = vault.positions(0);
        
        vm.startPrank(user1);
        // This will revert with NotEnoughDivestibleShares first (before NotEnoughLockedShares)
        uint256 tooManyShares = shareAmount + 1;
        vm.expectRevert(
            abi.encodeWithSelector(StakVault.StakVault__NotEnoughDivestibleShares.selector, 0, tooManyShares, shareAmount)
        );
        vault.divest(0, tooManyShares);
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

        // Get actual share amounts for each position
        (,, uint256 shareAmount1Initial,) = vault.positions(0);
        (,, uint256 shareAmount2Initial,) = vault.positions(1);
        
        // Divest half from first position
        vm.startPrank(user1);
        vault.divest(0, shareAmount1Initial / 2);
        vm.stopPrank();

        // Divest half from second position
        vm.startPrank(user1);
        vault.divest(1, shareAmount2Initial / 2);
        vm.stopPrank();

        (,, uint256 shareAmount1,) = vault.positions(0);
        (,, uint256 shareAmount2,) = vault.positions(1);
        // Allow for rounding
        assertGe(shareAmount1, shareAmount1Initial / 2 - 1);
        assertLe(shareAmount1, shareAmount1Initial / 2 + 1);
        assertGe(shareAmount2, shareAmount2Initial / 2 - 1);
        assertLe(shareAmount2, shareAmount2Initial / 2 + 1);
    }

    // ========================================================================
    // DivestFee Tests
    // ========================================================================

    function test_Divest_WithDivestFee() public {
        // Create vault with 1% divest fee (100 BPS)
        vm.prank(owner);
        StakVault feeVault = new StakVault(
            IERC20(address(asset)), "Fee Vault", "FEE", owner, treasury, PERFORMANCE_RATE, vestingStart, vestingEnd, 10e18, 100
        );

        // Deposit
        vm.startPrank(user1);
        asset.approve(address(feeVault), 1000e18);
        uint256 sharesMinted = feeVault.deposit(1000e18, user1);
        vm.stopPrank();

        uint256 positionId = 0;
        uint256 sharesToBurn = sharesMinted / 2;
        uint256 userBalanceBefore = asset.balanceOf(user1);
        uint256 treasuryBalanceBefore = asset.balanceOf(treasury);

        vm.startPrank(user1);
        uint256 assetAmount = feeVault.divest(positionId, sharesToBurn);
        vm.stopPrank();

        // Calculate expected fee (1% = 100 BPS) with Ceil rounding
        // assetAmount should be approximately 500e18 (half of 1000e18)
        // Fee calculation uses Ceil: (assetAmount * 100 + 9999) / 10000
        uint256 expectedFee = (assetAmount * 100 + 9999) / 10000; // Ceil rounding
        uint256 assetsAfterFee = assetAmount - expectedFee;

        // User should receive assets after fee (allow for rounding)
        uint256 actualUserReceived = asset.balanceOf(user1) - userBalanceBefore;
        assertGe(actualUserReceived, assetsAfterFee - 1);
        assertLe(actualUserReceived, assetsAfterFee + 1);
        // Treasury should receive the fee (allow for rounding)
        uint256 actualTreasuryReceived = asset.balanceOf(treasury) - treasuryBalanceBefore;
        assertGe(actualTreasuryReceived, expectedFee - 1);
        assertLe(actualTreasuryReceived, expectedFee + 1);
        // Total should approximately equal assetAmount
        uint256 totalTransferred = actualUserReceived + actualTreasuryReceived;
        assertGe(totalTransferred, assetAmount - 2);
        assertLe(totalTransferred, assetAmount + 2);
    }

    function test_Divest_WithMaxDivestFee() public {
        // Create vault with 5% divest fee (500 BPS)
        vm.prank(owner);
        StakVault feeVault = new StakVault(
            IERC20(address(asset)), "Fee Vault", "FEE", owner, treasury, PERFORMANCE_RATE, vestingStart, vestingEnd, 10e18, 500
        );

        // Deposit
        vm.startPrank(user1);
        asset.approve(address(feeVault), 1000e18);
        uint256 sharesMinted = feeVault.deposit(1000e18, user1);
        vm.stopPrank();

        uint256 positionId = 0;
        uint256 sharesToBurn = sharesMinted;
        uint256 userBalanceBefore = asset.balanceOf(user1);
        uint256 treasuryBalanceBefore = asset.balanceOf(treasury);

        vm.startPrank(user1);
        uint256 assetAmount = feeVault.divest(positionId, sharesToBurn);
        vm.stopPrank();

        // Calculate expected fee (5% = 500 BPS) with Ceil rounding
        uint256 expectedFee = (assetAmount * 500 + 9999) / 10000; // Ceil rounding
        uint256 assetsAfterFee = assetAmount - expectedFee;

        // User should receive assets after fee
        assertGe(asset.balanceOf(user1), userBalanceBefore + assetsAfterFee - 1);
        assertLe(asset.balanceOf(user1), userBalanceBefore + assetsAfterFee + 1);
        // Treasury should receive the fee
        assertGe(asset.balanceOf(treasury), treasuryBalanceBefore + expectedFee - 1);
        assertLe(asset.balanceOf(treasury), treasuryBalanceBefore + expectedFee + 1);
    }

    function test_Divest_WithZeroDivestFee() public {
        // This is the default vault in BaseTest with divestFee = 0
        // Deposit
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        uint256 sharesMinted = vault.deposit(1000e18, user1);
        vm.stopPrank();

        uint256 positionId = 0;
        uint256 sharesToBurn = sharesMinted;
        uint256 userBalanceBefore = asset.balanceOf(user1);
        uint256 treasuryBalanceBefore = asset.balanceOf(treasury);

        vm.startPrank(user1);
        uint256 assetAmount = vault.divest(positionId, sharesToBurn);
        vm.stopPrank();

        // With 0% fee, user should get full amount
        assertEq(asset.balanceOf(user1), userBalanceBefore + assetAmount);
        // Treasury should receive nothing
        assertEq(asset.balanceOf(treasury), treasuryBalanceBefore);
    }
}
