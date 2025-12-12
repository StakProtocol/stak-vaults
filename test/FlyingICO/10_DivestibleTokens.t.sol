// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "./BaseTest.sol";

/**
 * @title FlyingICODivestibleTokensTest
 * @dev Tests for the divestibleTokens function, including recent changes that account
 *      for tokens already divested or unlocked (takenTokens calculation)
 */
contract FlyingICODivestibleTokensTest is BaseTest {
    function test_DivestibleTokens_AfterPartialDivest_BeforeVesting() public {
        uint256 ethAmount = 1 ether;
        vm.prank(user1);
        uint256 positionId = ico.investEther{value: ethAmount}();

        // Initially, all tokens should be divestible
        uint256 initialDivestible = ico.divestibleTokens(positionId);
        (,,,, uint256 vestingAmount) = ico.positions(positionId);
        assertEq(initialDivestible, vestingAmount); // 20000e18

        // Divest half of the tokens
        uint256 tokensToDivest = 10000e18;
        vm.prank(user1);
        ico.divest(positionId, tokensToDivest);

        // After divest, divestible should be reduced
        uint256 divestibleAfter = ico.divestibleTokens(positionId);
        (,,, uint256 tokenAmountAfter,) = ico.positions(positionId);
        
        // Divestible should equal remaining tokens (since before vesting)
        assertEq(divestibleAfter, tokenAmountAfter);
        assertEq(divestibleAfter, 10000e18);
    }

    function test_DivestibleTokens_AfterPartialUnlock_BeforeVesting() public {
        uint256 ethAmount = 1 ether;
        vm.prank(user1);
        uint256 positionId = ico.investEther{value: ethAmount}();

        // Initially, all tokens should be divestible
        uint256 initialDivestible = ico.divestibleTokens(positionId);
        (,,,, uint256 vestingAmount) = ico.positions(positionId);
        assertEq(initialDivestible, vestingAmount);

        // Unlock half of the tokens
        uint256 tokensToUnlock = 10000e18;
        vm.prank(user1);
        ico.unlock(positionId, tokensToUnlock);

        // After unlock, divestible should be reduced
        uint256 divestibleAfter = ico.divestibleTokens(positionId);
        (,,, uint256 tokenAmountAfter,) = ico.positions(positionId);
        
        // Divestible should equal remaining tokens (since before vesting)
        assertEq(divestibleAfter, tokenAmountAfter);
        assertEq(divestibleAfter, 10000e18);
    }

    function test_DivestibleTokens_AfterDivestAndUnlock_BeforeVesting() public {
        uint256 ethAmount = 1 ether;
        vm.prank(user1);
        uint256 positionId = ico.investEther{value: ethAmount}();

        // Divest some tokens
        vm.prank(user1);
        ico.divest(positionId, 5000e18);

        // Unlock some tokens
        vm.prank(user1);
        ico.unlock(positionId, 5000e18);

        // Check divestible after both operations
        uint256 divestibleAfter = ico.divestibleTokens(positionId);
        (,,, uint256 tokenAmountAfter,) = ico.positions(positionId);
        
        // Should equal remaining tokens
        assertEq(divestibleAfter, tokenAmountAfter);
        assertEq(divestibleAfter, 10000e18);
    }

    function test_DivestibleTokens_AfterPartialDivest_DuringVesting() public {
        uint256 ethAmount = 1 ether;
        vm.prank(user1);
        uint256 positionId = ico.investEther{value: ethAmount}();

        // Move to middle of vesting period
        vm.warp(vestingStart + 15 days);

        // Get initial divestible (should be less than vestingAmount due to vesting)
        uint256 initialDivestible = ico.divestibleTokens(positionId);
        (,,,, uint256 vestingAmount) = ico.positions(positionId);
        assertLt(initialDivestible, vestingAmount);
        assertGt(initialDivestible, 0);

        // Divest half of the divestible tokens
        uint256 tokensToDivest = initialDivestible / 2;
        vm.prank(user1);
        ico.divest(positionId, tokensToDivest);

        // After divest, divestible should be reduced
        uint256 divestibleAfter = ico.divestibleTokens(positionId);
        
        // Should be approximately half of initial (accounting for rounding)
        assertLe(divestibleAfter, initialDivestible - tokensToDivest);
        assertGt(divestibleAfter, 0);
    }

    function test_DivestibleTokens_AfterPartialUnlock_DuringVesting() public {
        uint256 ethAmount = 1 ether;
        vm.prank(user1);
        uint256 positionId = ico.investEther{value: ethAmount}();

        // Move to middle of vesting period
        vm.warp(vestingStart + 15 days);

        // Get initial divestible
        uint256 initialDivestible = ico.divestibleTokens(positionId);
        assertGt(initialDivestible, 0);

        // Unlock some tokens (less than divestible)
        uint256 tokensToUnlock = initialDivestible / 2;
        vm.prank(user1);
        ico.unlock(positionId, tokensToUnlock);

        // After unlock, divestible should be reduced
        uint256 divestibleAfter = ico.divestibleTokens(positionId);
        
        // Should be less than initial
        assertLt(divestibleAfter, initialDivestible);
        assertGt(divestibleAfter, 0);
    }

    function test_DivestibleTokens_AfterAllTokensDivested() public {
        uint256 ethAmount = 1 ether;
        vm.prank(user1);
        uint256 positionId = ico.investEther{value: ethAmount}();

        // Divest all tokens
        vm.prank(user1);
        ico.divest(positionId, 20000e18);

        // After all tokens divested, divestible should be 0
        uint256 divestibleAfter = ico.divestibleTokens(positionId);
        assertEq(divestibleAfter, 0);
    }

    function test_DivestibleTokens_AfterAllTokensUnlocked() public {
        uint256 ethAmount = 1 ether;
        vm.prank(user1);
        uint256 positionId = ico.investEther{value: ethAmount}();

        // Unlock all tokens
        vm.prank(user1);
        ico.unlock(positionId, 20000e18);

        // After all tokens unlocked, divestible should be 0
        uint256 divestibleAfter = ico.divestibleTokens(positionId);
        assertEq(divestibleAfter, 0);
    }

    function test_DivestibleTokens_AfterVestingEnds() public {
        uint256 ethAmount = 1 ether;
        vm.prank(user1);
        uint256 positionId = ico.investEther{value: ethAmount}();

        // Move after vesting ends
        vm.warp(vestingEnd + 1 days);

        // After vesting ends, divestible should be 0
        uint256 divestible = ico.divestibleTokens(positionId);
        assertEq(divestible, 0);
    }

    function test_DivestibleTokens_AfterVestingEnds_WithPartialDivest() public {
        uint256 ethAmount = 1 ether;
        vm.prank(user1);
        uint256 positionId = ico.investEther{value: ethAmount}();

        // Divest some tokens before vesting ends
        vm.prank(user1);
        ico.divest(positionId, 10000e18);

        // Move after vesting ends
        vm.warp(vestingEnd + 1 days);

        // After vesting ends, divestible should be 0 regardless of remaining tokens
        uint256 divestible = ico.divestibleTokens(positionId);
        assertEq(divestible, 0);
    }

    function test_DivestibleTokens_EdgeCase_AllDivestibleTaken() public {
        uint256 ethAmount = 1 ether;
        vm.prank(user1);
        uint256 positionId = ico.investEther{value: ethAmount}();

        // Move to middle of vesting
        vm.warp(vestingStart + 15 days);

        // Get divestible amount
        uint256 divestible = ico.divestibleTokens(positionId);
        assertGt(divestible, 0);

        // Divest all divestible tokens
        vm.prank(user1);
        ico.divest(positionId, divestible);

        // After divesting all divestible, should be 0
        uint256 divestibleAfter = ico.divestibleTokens(positionId);
        assertEq(divestibleAfter, 0);
    }

    function test_DivestibleTokens_EdgeCase_MoreThanDivestibleUnlocked() public {
        uint256 ethAmount = 1 ether;
        vm.prank(user1);
        uint256 positionId = ico.investEther{value: ethAmount}();

        // Move to middle of vesting
        vm.warp(vestingStart + 15 days);

        // Get divestible amount
        uint256 divestible = ico.divestibleTokens(positionId);
        assertGt(divestible, 0);

        // Unlock more than divestible (but less than total tokens)
        // This should work because unlock doesn't check divestible amount
        uint256 tokensToUnlock = divestible + 1000e18;
        (,,, uint256 tokenAmount,) = ico.positions(positionId);
        if (tokensToUnlock <= tokenAmount) {
            vm.prank(user1);
            ico.unlock(positionId, tokensToUnlock);

            // After unlocking more than divestible, divestible should be 0
            uint256 divestibleAfter = ico.divestibleTokens(positionId);
            assertEq(divestibleAfter, 0);
        }
    }

    function test_DivestibleTokens_Calculation_WithTakenTokens() public {
        uint256 ethAmount = 1 ether;
        vm.prank(user1);
        uint256 positionId = ico.investEther{value: ethAmount}();

        // Move to middle of vesting
        vm.warp(vestingStart + 15 days);

        // Get initial values
        uint256 vestingRate = ico.vestingRate();
        (,,,, uint256 vestingAmount) = ico.positions(positionId);
        
        // Calculate expected divestible: vestingRate * vestingAmount / BPS
        uint256 expectedDivestible = vestingRate * vestingAmount / 10000;
        uint256 actualDivestible = ico.divestibleTokens(positionId);
        
        // Should match (accounting for rounding)
        assertEq(actualDivestible, expectedDivestible);

        // Divest some tokens
        uint256 tokensToDivest = actualDivestible / 2;
        vm.prank(user1);
        ico.divest(positionId, tokensToDivest);

        // Recalculate after divest
        (,,, uint256 tokenAmountAfter,) = ico.positions(positionId);
        uint256 takenTokens = vestingAmount - tokenAmountAfter;
        uint256 expectedDivestibleAfter = expectedDivestible > takenTokens ? (expectedDivestible - takenTokens) : 0;
        uint256 actualDivestibleAfter = ico.divestibleTokens(positionId);

        assertEq(actualDivestibleAfter, expectedDivestibleAfter);
    }

    function test_DivestibleTokens_MultipleOperations() public {
        uint256 ethAmount = 1 ether;
        vm.prank(user1);
        uint256 positionId = ico.investEther{value: ethAmount}();

        // Operation 1: Divest
        vm.prank(user1);
        ico.divest(positionId, 5000e18);
        uint256 divestible1 = ico.divestibleTokens(positionId);
        assertEq(divestible1, 15000e18);

        // Operation 2: Unlock
        vm.prank(user1);
        ico.unlock(positionId, 5000e18);
        uint256 divestible2 = ico.divestibleTokens(positionId);
        assertEq(divestible2, 10000e18);

        // Operation 3: Divest again
        vm.prank(user1);
        ico.divest(positionId, 5000e18);
        uint256 divestible3 = ico.divestibleTokens(positionId);
        assertEq(divestible3, 5000e18);

        // Operation 4: Unlock remaining
        vm.prank(user1);
        ico.unlock(positionId, 5000e18);
        uint256 divestible4 = ico.divestibleTokens(positionId);
        assertEq(divestible4, 0);
    }
}

