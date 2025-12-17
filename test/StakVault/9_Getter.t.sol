// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "./BaseTest.sol";

contract StakVaultGetterTest is BaseTest {
    function test_TotalAssets_Initial() public view {
        assertEq(vault.totalAssets(), 10e18); // Initial investedAssets = 10e18
    }

    function test_TotalAssets_WithBalance() public {
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        // totalAssets = balance + investedAssets = 1000e18 + 10e18 = 1010e18
        assertEq(vault.totalAssets(), 1010e18);
    }

    function test_TotalAssets_WithInvestedAssets() public {
        // First deposit to have some balance for performance fee transfers
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        vm.prank(owner);
        vault.updateInvestedAssets(2000e18);

        uint256 totalAssets = vault.totalAssets();
        uint256 balance = asset.balanceOf(address(vault));
        uint256 investedAssets = vault.investedAssets();

        assertEq(totalAssets, balance + investedAssets);
    }

    function test_TotalAssets_WithBoth() public {
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Add assets to simulate growth before updating
        asset.mint(address(vault), 1000e18);

        vm.prank(owner);
        vault.updateInvestedAssets(2000e18);

        // totalAssets = balance + investedAssets
        // Performance fee might reduce balance
        uint256 totalAssets = vault.totalAssets();
        uint256 balance = asset.balanceOf(address(vault));
        uint256 investedAssets = vault.investedAssets();

        assertEq(totalAssets, balance + investedAssets);
    }

    // TODO: Add utilizationRate function to StakVault contract
    // function test_UtilizationRate_Zero() public view {
    //     assertEq(vault.utilizationRate(), 0);
    // }

    // TODO: Add utilizationRate function to StakVault contract
    // function test_UtilizationRate_Partial() public {
    //     vm.startPrank(user1);
    //     asset.approve(address(vault), 1000e18);
    //     vault.deposit(1000e18, user1);
    //     vm.stopPrank();
    //
    //     vm.prank(owner);
    //     vault.updateInvestedAssets(500e18);
    //
    //     // utilization = investedAssets / totalAssets * 10000
    //     // totalAssets = balance + investedAssets
    //     // If performance fee was taken, balance might be less
    //     uint256 utilization = vault.utilizationRate();
    //     uint256 totalAssets = vault.totalAssets();
    //     uint256 investedAssets = vault.investedAssets();
    //
    //     // Recalculate expected: investedAssets / totalAssets * 10000
    //     uint256 expected = 10000 * investedAssets / totalAssets;
    //     assertEq(utilization, expected);
    // }

    // TODO: Add utilizationRate function to StakVault contract
    // function test_UtilizationRate_Full() public {
    //     vm.startPrank(user1);
    //     asset.approve(address(vault), 1000e18);
    //     vault.deposit(1000e18, user1);
    //     vm.stopPrank();
    //
    //     vm.prank(owner);
    //     vault.updateInvestedAssets(1000e18);
    //
    //     // utilization = investedAssets / totalAssets * 10000
    //     // Performance fee might reduce balance, affecting totalAssets
    //     uint256 utilization = vault.utilizationRate();
    //     uint256 totalAssets = vault.totalAssets();
    //     uint256 investedAssets = vault.investedAssets();
    //
    //     // Recalculate expected
    //     uint256 expected = totalAssets > 0 ? 10000 * investedAssets / totalAssets : 0;
    //     assertEq(utilization, expected);
    // }

    function test_PositionsOfUser_Empty() public view {
        uint256[] memory positions = vault.positionsOf(user1);
        assertEq(positions.length, 0);
    }

    function test_PositionsOfUser_WithPositions() public {
        vm.startPrank(user1);
        asset.approve(address(vault), 2000e18);
        vault.deposit(1000e18, user1);
        vault.deposit(500e18, user1);
        vm.stopPrank();

        uint256[] memory positions = vault.positionsOf(user1);
        assertEq(positions.length, 2);
        assertEq(positions[0], 0);
        assertEq(positions[1], 1);
    }

    function test_DivestibleShares_BeforeVesting() public {
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        uint256 sharesMinted = vault.deposit(1000e18, user1);
        vm.stopPrank();

        uint256 divestible = vault.divestibleShares(0);
        // 100% before vesting, so should equal sharesMinted (with rounding)
        assertGe(divestible, sharesMinted - 1);
        assertLe(divestible, sharesMinted + 1);
    }

    function test_DivestibleShares_DuringVesting() public {
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Move to middle of vesting
        vm.warp(vestingStart + 15 days);

        uint256 divestible = vault.divestibleShares(0);
        assertLt(divestible, 1000e18);
        assertGt(divestible, 0);
    }

    function test_DivestibleShares_AfterVesting() public {
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Move after vesting
        vm.warp(vestingEnd + 1 days);

        uint256 divestible = vault.divestibleShares(0);
        assertEq(divestible, 0); // 0% after vesting
    }

    function test_DivestibleShares_AfterPartialDivest_BeforeVesting() public {
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        uint256 sharesMinted = vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Initially, all shares should be divestible
        uint256 initialDivestible = vault.divestibleShares(0);
        (,,, uint256 vestingAmount) = vault.positions(0);
        assertGe(initialDivestible, vestingAmount - 1);
        assertLe(initialDivestible, vestingAmount + 1);

        // Divest half of the shares
        vm.startPrank(user1);
        vault.divest(0, sharesMinted / 2);
        vm.stopPrank();

        // After divest, divestible should be reduced
        uint256 divestibleAfter = vault.divestibleShares(0);
        (,, uint256 shareAmountAfter,) = vault.positions(0);
        
        // Divestible should equal remaining shares (since before vesting)
        assertGe(divestibleAfter, shareAmountAfter - 1);
        assertLe(divestibleAfter, shareAmountAfter + 1);
    }

    function test_DivestibleShares_AfterPartialUnlock_BeforeVesting() public {
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        uint256 sharesMinted = vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Initially, all shares should be divestible
        uint256 initialDivestible = vault.divestibleShares(0);
        (,,, uint256 vestingAmount) = vault.positions(0);
        assertGe(initialDivestible, vestingAmount - 1);
        assertLe(initialDivestible, vestingAmount + 1);

        // Unlock half of the shares
        vm.startPrank(user1);
        vault.unlock(0, sharesMinted / 2);
        vm.stopPrank();

        // After unlock, divestible should be reduced
        uint256 divestibleAfter = vault.divestibleShares(0);
        (,, uint256 shareAmountAfter,) = vault.positions(0);
        
        // Divestible should equal remaining shares (since before vesting)
        assertGe(divestibleAfter, shareAmountAfter - 1);
        assertLe(divestibleAfter, shareAmountAfter + 1);
    }

    function test_DivestibleShares_AfterDivestAndUnlock_BeforeVesting() public {
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        uint256 sharesMinted = vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Divest some shares
        vm.startPrank(user1);
        vault.divest(0, sharesMinted / 4);
        vm.stopPrank();

        // Unlock some shares
        vm.startPrank(user1);
        vault.unlock(0, sharesMinted / 4);
        vm.stopPrank();

        // Check divestible after both operations
        uint256 divestibleAfter = vault.divestibleShares(0);
        (,, uint256 shareAmountAfter,) = vault.positions(0);
        
        // Should equal remaining shares
        assertGe(divestibleAfter, shareAmountAfter - 1);
        assertLe(divestibleAfter, shareAmountAfter + 1);
    }

    function test_DivestibleShares_AfterPartialDivest_DuringVesting() public {
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Move to middle of vesting period
        vm.warp(vestingStart + 15 days);

        // Get initial divestible (should be less than vestingAmount due to vesting)
        uint256 initialDivestible = vault.divestibleShares(0);
        (,,, uint256 vestingAmount) = vault.positions(0);
        assertLt(initialDivestible, vestingAmount);
        assertGt(initialDivestible, 0);

        // Divest half of the divestible shares
        uint256 sharesToDivest = initialDivestible / 2;
        vm.startPrank(user1);
        vault.divest(0, sharesToDivest);
        vm.stopPrank();

        // After divest, divestible should be reduced
        uint256 divestibleAfter = vault.divestibleShares(0);
        
        // Should be approximately half of initial (accounting for rounding)
        assertLe(divestibleAfter, initialDivestible - sharesToDivest + 10);
        assertGt(divestibleAfter, 0);
    }

    function test_DivestibleShares_AfterPartialUnlock_DuringVesting() public {
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Move to middle of vesting period
        vm.warp(vestingStart + 15 days);

        // Get initial divestible
        uint256 initialDivestible = vault.divestibleShares(0);
        assertGt(initialDivestible, 0);

        // Unlock some shares (less than divestible)
        uint256 sharesToUnlock = initialDivestible / 2;
        vm.startPrank(user1);
        vault.unlock(0, sharesToUnlock);
        vm.stopPrank();

        // After unlock, divestible should be reduced
        uint256 divestibleAfter = vault.divestibleShares(0);
        
        // Should be less than initial
        assertLt(divestibleAfter, initialDivestible);
        assertGt(divestibleAfter, 0);
    }

    function test_DivestibleShares_AfterAllSharesDivested() public {
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        uint256 sharesMinted = vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Divest all shares
        vm.startPrank(user1);
        vault.divest(0, sharesMinted);
        vm.stopPrank();

        // After all shares divested, divestible should be 0
        uint256 divestibleAfter = vault.divestibleShares(0);
        assertEq(divestibleAfter, 0);
    }

    function test_DivestibleShares_AfterAllSharesUnlocked() public {
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        uint256 sharesMinted = vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Unlock all shares
        vm.startPrank(user1);
        vault.unlock(0, sharesMinted);
        vm.stopPrank();

        // After all shares unlocked, divestible should be 0
        uint256 divestibleAfter = vault.divestibleShares(0);
        assertEq(divestibleAfter, 0);
    }

    function test_DivestibleShares_AfterVestingEnds_WithPartialDivest() public {
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        uint256 sharesMinted = vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Divest some shares before vesting ends
        vm.startPrank(user1);
        vault.divest(0, sharesMinted / 2);
        vm.stopPrank();

        // Move after vesting ends
        vm.warp(vestingEnd + 1 days);

        // After vesting ends, divestible should be 0 regardless of remaining shares
        uint256 divestible = vault.divestibleShares(0);
        assertEq(divestible, 0);
    }

    function test_DivestibleShares_EdgeCase_AllDivestibleTaken() public {
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Move to middle of vesting
        vm.warp(vestingStart + 15 days);

        // Get divestible amount
        uint256 divestible = vault.divestibleShares(0);
        assertGt(divestible, 0);

        // Divest all divestible shares
        vm.startPrank(user1);
        vault.divest(0, divestible);
        vm.stopPrank();

        // After divesting all divestible, should be 0
        uint256 divestibleAfter = vault.divestibleShares(0);
        assertEq(divestibleAfter, 0);
    }

    function test_DivestibleShares_EdgeCase_MoreThanDivestibleUnlocked() public {
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Move to middle of vesting
        vm.warp(vestingStart + 15 days);

        // Get divestible amount
        uint256 divestible = vault.divestibleShares(0);
        assertGt(divestible, 0);

        // Unlock more than divestible (but less than total shares)
        // This should work because unlock doesn't check divestible amount
        uint256 sharesToUnlock = divestible + 100e18;
        (,, uint256 shareAmount,) = vault.positions(0);
        if (sharesToUnlock <= shareAmount) {
            vm.startPrank(user1);
            vault.unlock(0, sharesToUnlock);
            vm.stopPrank();

            // After unlocking more than divestible, divestible should be 0
            uint256 divestibleAfter = vault.divestibleShares(0);
            assertEq(divestibleAfter, 0);
        }
    }

    function test_DivestibleShares_Calculation_WithTakenShares() public {
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Move to middle of vesting
        vm.warp(vestingStart + 15 days);

        // Get initial values
        uint256 vestingRate = vault.vestingRate();
        (,,, uint256 vestingAmount) = vault.positions(0);
        
        // Calculate expected divestible: vestingRate * vestingAmount / BPS
        uint256 expectedDivestible = vestingRate * vestingAmount / 10000;
        uint256 actualDivestible = vault.divestibleShares(0);
        
        // Should match (accounting for rounding)
        assertGe(actualDivestible, expectedDivestible - 1);
        assertLe(actualDivestible, expectedDivestible + 1);

        // Divest some shares
        uint256 sharesToDivest = actualDivestible / 2;
        vm.startPrank(user1);
        vault.divest(0, sharesToDivest);
        vm.stopPrank();

        // Recalculate after divest
        (,, uint256 shareAmountAfter,) = vault.positions(0);
        uint256 takenShares = vestingAmount - shareAmountAfter;
        uint256 expectedDivestibleAfter = expectedDivestible > takenShares ? (expectedDivestible - takenShares) : 0;
        uint256 actualDivestibleAfter = vault.divestibleShares(0);

        assertGe(actualDivestibleAfter, expectedDivestibleAfter - 1);
        assertLe(actualDivestibleAfter, expectedDivestibleAfter + 1);
    }

    function test_DivestibleShares_MultipleOperations() public {
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        uint256 sharesMinted = vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Operation 1: Divest
        vm.startPrank(user1);
        vault.divest(0, sharesMinted / 4);
        vm.stopPrank();
        uint256 divestible1 = vault.divestibleShares(0);
        (,, uint256 shareAmount1,) = vault.positions(0);
        assertGe(divestible1, shareAmount1 - 1);
        assertLe(divestible1, shareAmount1 + 1);

        // Operation 2: Unlock
        vm.startPrank(user1);
        vault.unlock(0, sharesMinted / 4);
        vm.stopPrank();
        uint256 divestible2 = vault.divestibleShares(0);
        (,, uint256 shareAmount2,) = vault.positions(0);
        assertGe(divestible2, shareAmount2 - 1);
        assertLe(divestible2, shareAmount2 + 1);

        // Operation 3: Divest again
        vm.startPrank(user1);
        vault.divest(0, sharesMinted / 4);
        vm.stopPrank();
        uint256 divestible3 = vault.divestibleShares(0);
        (,, uint256 shareAmount3,) = vault.positions(0);
        assertGe(divestible3, shareAmount3 - 1);
        assertLe(divestible3, shareAmount3 + 1);

        // Operation 4: Unlock remaining
        (,, uint256 shareAmount4,) = vault.positions(0);
        vm.startPrank(user1);
        vault.unlock(0, shareAmount4);
        vm.stopPrank();
        uint256 divestible4 = vault.divestibleShares(0);
        assertEq(divestible4, 0);
    }

    function test_VestingRate_BeforeVesting() public view {
        uint256 rate = vault.vestingRate();
        assertEq(rate, 10000); // 100%
    }

    function test_VestingRate_DuringVesting() public {
        vm.warp(vestingStart + 15 days);
        uint256 rate = vault.vestingRate();
        assertLt(rate, 10000);
        assertGt(rate, 0);
    }

    function test_VestingRate_AfterVesting() public {
        vm.warp(vestingEnd + 1 days);
        uint256 rate = vault.vestingRate();
        assertEq(rate, 0); // 0%
    }

    function test_VestingRate_ExactStart() public {
        vm.warp(vestingStart);
        uint256 rate = vault.vestingRate();
        assertLe(rate, 10000);
        assertGt(rate, 0);
    }

    function test_VestingRate_ExactEnd() public {
        vm.warp(vestingEnd);
        uint256 rate = vault.vestingRate();
        assertEq(rate, 0);
    }

    function test_Positions_Struct() public {
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        uint256 sharesMinted = vault.deposit(1000e18, user1);
        vm.stopPrank();

        (address posUser, uint256 assetAmount, uint256 shareAmount, uint256 vestingAmount) = vault.positions(0);
        assertEq(posUser, user1);
        assertEq(assetAmount, 1000e18);
        // Allow for rounding in share amounts
        assertGe(shareAmount, sharesMinted - 1);
        assertLe(shareAmount, sharesMinted + 1);
        assertGe(vestingAmount, sharesMinted - 1);
        assertLe(vestingAmount, sharesMinted + 1);
    }

    function test_HighWaterMark() public view {
        assertEq(vault.highWaterMark(), 10e18);
    }

    function test_NextPositionId() public {
        assertEq(vault.nextPositionId(), 0);

        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        assertEq(vault.nextPositionId(), 1);
    }
}
