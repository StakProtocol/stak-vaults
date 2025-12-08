// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "./BaseTest.sol";

contract StakVaultFuzzTest is BaseTest {
    function testFuzz_Deposit(uint256 amount) public {
        // Bound amount to reasonable values
        amount = bound(amount, 1, 1000000e18);
        
        // Mint tokens to user
        asset.mint(user1, amount);
        
        vm.startPrank(user1);
        asset.approve(address(vault), amount);
        uint256 shares = vault.deposit(amount, user1);
        vm.stopPrank();
        
        // Verify shares were minted
        assertGt(shares, 0);
        
        // If not NAV mode, shares should be in contract
        if (!vault.redeemsAtNav()) {
            assertEq(vault.balanceOf(address(vault)), shares);
            assertEq(vault.balanceOf(user1), 0);
        } else {
            assertEq(vault.balanceOf(user1), shares);
        }
    }

    function testFuzz_Divest(uint256 depositAmount, uint256 divestAmount) public {
        // Bound amounts
        depositAmount = bound(depositAmount, 1e18, 100000e18);
        
        // Mint and deposit
        asset.mint(user1, depositAmount);
        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();
        
        // Get position info
        uint256[] memory positions = vault.positionsOfUser(user1);
        uint256 positionId = positions[0];
        
        // Get divestible shares
        uint256 divestible = vault.divestibleShares(positionId);
        
        // Bound divest amount to divestible shares
        divestAmount = bound(divestAmount, 1, divestible);
        
        // Divest
        vm.prank(user1);
        uint256 assetReturned = vault.divest(positionId, divestAmount);
        
        // Verify asset was returned
        assertGt(assetReturned, 0);
        assertLe(assetReturned, depositAmount);
    }

    function testFuzz_Unlock(uint256 depositAmount, uint256 unlockAmount) public {
        // Bound amounts
        depositAmount = bound(depositAmount, 1e18, 100000e18);
        
        // Mint and deposit
        asset.mint(user1, depositAmount);
        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();
        
        // Get position info
        uint256[] memory positions = vault.positionsOfUser(user1);
        uint256 positionId = positions[0];
        
        // Get position shares
        (,, uint256 shareAmount,) = vault.positions(positionId);
        
        // Bound unlock amount to available shares
        unlockAmount = bound(unlockAmount, 1, shareAmount);
        
        // Unlock
        vm.prank(user1);
        uint256 assetReturned = vault.unlock(positionId, unlockAmount);
        
        // Verify asset was returned
        assertGt(assetReturned, 0);
        assertLe(assetReturned, depositAmount);
        
        // Verify shares were transferred to user
        assertGe(vault.balanceOf(user1), unlockAmount);
    }

    function testFuzz_DivestibleShares(uint256 depositAmount, uint256 timeOffset) public {
        // Bound amounts
        depositAmount = bound(depositAmount, 1e18, 100000e18);
        
        // Mint and deposit
        asset.mint(user1, depositAmount);
        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();
        
        // Get position info
        uint256[] memory positions = vault.positionsOfUser(user1);
        uint256 positionId = positions[0];
        
        // Get vesting info
        (,,, uint256 vestingAmount) = vault.positions(positionId);
        
        // Bound time offset
        timeOffset = bound(timeOffset, 0, vestingEnd - block.timestamp + 1 days);
        vm.warp(block.timestamp + timeOffset);
        
        // Get divestible shares
        uint256 divestible = vault.divestibleShares(positionId);
        
        // Divestible should be <= vesting amount
        assertLe(divestible, vestingAmount);
        
        // If before vesting start, should be 100%
        if (block.timestamp < vestingStart) {
            assertEq(divestible, vestingAmount);
        }
        // If after vesting end, should be 0
        else if (block.timestamp > vestingEnd) {
            assertEq(divestible, 0);
        }
        // During vesting, should be between 0 and vestingAmount
        else {
            assertGe(divestible, 0);
            assertLe(divestible, vestingAmount);
        }
    }

    function testFuzz_VestingRate(uint256 timeOffset) public {
        // Bound time offset
        timeOffset = bound(timeOffset, 0, vestingEnd - block.timestamp + 1 days);
        vm.warp(block.timestamp + timeOffset);
        
        uint256 rate = vault.vestingRate();
        
        // Rate should be between 0 and 10000 (BPS)
        assertGe(rate, 0);
        assertLe(rate, 10000);
        
        // If before vesting start, should be 10000
        if (block.timestamp < vestingStart) {
            assertEq(rate, 10000);
        }
        // If after vesting end, should be 0
        else if (block.timestamp > vestingEnd) {
            assertEq(rate, 0);
        }
    }

    function testFuzz_UpdateInvestedAssets(uint256 investedAssets) public {
        // First deposit some assets
        uint256 depositAmount = 1000e18;
        asset.mint(user1, depositAmount);
        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();
        
        // Bound to reasonable values that don't exceed vault balance
        // The vault has depositAmount + any existing balance
        uint256 vaultBalance = asset.balanceOf(address(vault));
        uint256 maxInvested = vaultBalance > 0 ? vaultBalance : depositAmount;
        
        // Bound investedAssets to not exceed vault balance
        investedAssets = bound(investedAssets, 0, maxInvested);
        
        // Update invested assets
        vm.prank(owner);
        vault.updateInvestedAssets(investedAssets);
        
        // Verify it was updated
        assertEq(vault.investedAssets(), investedAssets);
    }

    function testFuzz_UtilizationRate(uint256 depositAmount, uint256 investedAssets) public {
        // Bound amounts
        depositAmount = bound(depositAmount, 1e18, 100000e18);
        
        // Deposit
        asset.mint(user1, depositAmount);
        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();
        
        // Bound investedAssets to not exceed vault balance
        uint256 vaultBalance = asset.balanceOf(address(vault));
        uint256 maxInvested = vaultBalance > 0 ? vaultBalance : depositAmount;
        investedAssets = bound(investedAssets, 0, maxInvested);
        
        // Update invested assets
        vm.prank(owner);
        vault.updateInvestedAssets(investedAssets);
        
        // Get utilization rate
        uint256 utilization = vault.utilizationRate();
        
        // Utilization should be between 0 and 10000 (BPS)
        assertGe(utilization, 0);
        assertLe(utilization, 10000);
        
        // If total assets is 0, utilization should be 0
        if (vault.totalAssets() == 0) {
            assertEq(utilization, 0);
        }
    }
}

