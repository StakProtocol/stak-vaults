// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "./BaseTest.sol";

contract FlyingICOFuzzTest is BaseTest {
    function testFuzz_InvestEther(uint256 amount) public {
        // Bound the amount to reasonable values that won't exceed cap
        // Cap is 1M tokens = 1e24 (1e6 * 1e18)
        // At $2000/ETH and 10 tokens/USD, 1 ETH = 20000 tokens = 20000e18
        // Max ETH = 1e24 / 20000e18 = 50,000 ETH
        // But we need to account for existing supply, so bound more conservatively
        uint256 currentSupply = ico.totalSupply();
        uint256 tokenCap = TOKEN_CAP * WAD; // Convert to units
        uint256 remainingCap = tokenCap > currentSupply ? tokenCap - currentSupply : 0;

        // Calculate max ETH that can be invested: remainingCap / 20000e18
        // At $2000/ETH and 10 tokens/USD: 1 ETH = 20000e18 tokens
        uint256 maxEth = remainingCap > 0 ? remainingCap / 20000e18 : 0;

        // Bound amount to available cap, but cap at reasonable max
        uint256 upperBound = maxEth > 0 && maxEth < 1000 ether ? maxEth : 1000 ether;
        amount = bound(amount, 1 wei, upperBound);

        // Skip if this would exceed cap
        // Calculate tokens this would mint: amount * 2000e8 * 1e18 / (1e18 * 1e8) * 10e18 / 1e18
        // Simplified: amount * 20000e18
        uint256 tokensToMint = amount * 20000e18;
        vm.assume(currentSupply + tokensToMint <= tokenCap);

        vm.deal(user1, amount);

        vm.prank(user1);
        uint256 positionId = ico.investEther{value: amount}();

        // Verify position was created
        (address user, address asset, uint256 assetAmount, uint256 tokenAmount,) = ico.positions(positionId);
        assertEq(user, user1);
        assertEq(asset, address(0));
        assertEq(assetAmount, amount);
        assertGt(tokenAmount, 0);
    }

    function testFuzz_InvestERC20(uint256 amount) public {
        // Bound to reasonable values (USDC has 6 decimals)
        // Check token cap: At $1/USDC and 10 tokens/USD, 1 USDC = 10 tokens = 10e18
        uint256 currentSupply = ico.totalSupply();
        uint256 tokenCap = TOKEN_CAP * WAD; // Convert to units
        uint256 remainingCap = tokenCap > currentSupply ? tokenCap - currentSupply : 0;

        // Calculate max USDC: remainingCap / 10e18
        uint256 maxUsdc = remainingCap > 0 ? remainingCap / 10e18 : 0;
        uint256 upperBound = maxUsdc > 0 && maxUsdc < 1000000e6 ? maxUsdc : 1000000e6;
        amount = bound(amount, 1, upperBound);

        // Skip if this would exceed cap
        // At $1/USDC and 10 tokens/USD: 1 USDC = 10e18 tokens
        uint256 tokensToMint = amount * 10e18 / 1e6; // Convert from 6 decimals to 18
        vm.assume(currentSupply + tokensToMint <= tokenCap);

        // Mint tokens to user
        usdc.mint(user1, amount);

        vm.startPrank(user1);
        usdc.approve(address(ico), amount);
        uint256 positionId = ico.investERC20(address(usdc), amount);
        vm.stopPrank();

        // Verify position was created
        (address user, address asset, uint256 assetAmount, uint256 tokenAmount,) = ico.positions(positionId);
        assertEq(user, user1);
        assertEq(asset, address(usdc));
        assertEq(assetAmount, amount);
        assertGt(tokenAmount, 0);
    }

    function testFuzz_Divest(uint256 investAmount, uint256 divestAmount) public {
        // Check token cap first
        uint256 currentSupply = ico.totalSupply();
        uint256 tokenCap = TOKEN_CAP * WAD;
        uint256 remainingCap = tokenCap > currentSupply ? tokenCap - currentSupply : 0;

        // Bound invest amount conservatively to avoid cap issues
        // At $2000/ETH and 10 tokens/USD: 1 ETH = 20000e18 tokens
        // Use a conservative bound that's well below cap
        uint256 maxEth = remainingCap > 20000e18 ? remainingCap / 20000e18 : 0;
        if (maxEth == 0 || maxEth < 1 ether) {
            // Skip if no reasonable cap remaining
            return;
        }

        uint256 upperBound = maxEth < 100 ether ? maxEth : 100 ether;
        investAmount = bound(investAmount, 1 ether, upperBound);

        vm.deal(user1, investAmount);

        // Invest - this might revert if cap is exceeded, which is fine
        vm.prank(user1);
        uint256 positionId = ico.investEther{value: investAmount}();

        // Get the actual token amount
        (,,, uint256 tokenAmount,) = ico.positions(positionId);

        if (tokenAmount == 0) {
            return; // Skip if no tokens minted
        }

        // Bound divest amount to available tokens
        divestAmount = bound(divestAmount, 1, tokenAmount);

        // Get divestible tokens
        uint256 divestible = ico.divestibleTokens(positionId);
        if (divestible == 0 || divestAmount > divestible) {
            return; // Skip if not divestible
        }

        // Divest
        vm.prank(user1);
        uint256 assetReturned = ico.divest(positionId, divestAmount);

        // Verify asset was returned
        assertGt(assetReturned, 0);
        assertLe(assetReturned, investAmount);
    }

    function testFuzz_Unlock(uint256 investAmount, uint256 unlockAmount) public {
        // Check token cap first
        uint256 currentSupply = ico.totalSupply();
        uint256 tokenCap = TOKEN_CAP * WAD;
        uint256 remainingCap = tokenCap > currentSupply ? tokenCap - currentSupply : 0;

        // Bound invest amount conservatively to avoid cap issues
        // At $2000/ETH and 10 tokens/USD: 1 ETH = 20000e18 tokens
        uint256 maxEth = remainingCap > 20000e18 ? remainingCap / 20000e18 : 0;
        if (maxEth == 0 || maxEth < 1 ether) {
            // Skip if no reasonable cap remaining
            return;
        }

        uint256 upperBound = maxEth < 100 ether ? maxEth : 100 ether;
        investAmount = bound(investAmount, 1 ether, upperBound);

        vm.deal(user1, investAmount);

        // Invest - this might revert if cap is exceeded, which is fine
        vm.prank(user1);
        uint256 positionId = ico.investEther{value: investAmount}();

        // Get the actual token amount
        (,,, uint256 tokenAmount,) = ico.positions(positionId);

        if (tokenAmount == 0) {
            return; // Skip if no tokens minted
        }

        // Bound unlock amount to available tokens
        unlockAmount = bound(unlockAmount, 1, tokenAmount);

        // Unlock
        vm.prank(user1);
        uint256 assetReturned = ico.unlock(positionId, unlockAmount);

        // Verify asset was returned
        assertGt(assetReturned, 0);
        assertLe(assetReturned, investAmount);

        // Verify tokens were transferred to user
        assertGe(ico.balanceOf(user1), unlockAmount);
    }

    function testFuzz_DivestibleTokens(uint256 investAmount, uint256 timeOffset) public {
        // Check token cap first
        uint256 currentSupply = ico.totalSupply();
        uint256 tokenCap = TOKEN_CAP * WAD;
        uint256 remainingCap = tokenCap > currentSupply ? tokenCap - currentSupply : 0;

        // Bound invest amount conservatively to avoid cap issues
        // At $2000/ETH and 10 tokens/USD: 1 ETH = 20000e18 tokens
        uint256 maxEth = remainingCap > 20000e18 ? remainingCap / 20000e18 : 0;
        if (maxEth == 0 || maxEth < 1 ether) {
            // Skip if no reasonable cap remaining
            return;
        }

        uint256 upperBound = maxEth < 100 ether ? maxEth : 100 ether;
        investAmount = bound(investAmount, 1 ether, upperBound);

        vm.deal(user1, investAmount);

        // Invest - this might revert if cap is exceeded, which is fine
        vm.prank(user1);
        uint256 positionId = ico.investEther{value: investAmount}();

        // Get vesting info
        (,,,, uint256 vestingAmount) = ico.positions(positionId);

        // Bound time offset
        timeOffset = bound(timeOffset, 0, vestingEnd - block.timestamp + 1 days);
        vm.warp(block.timestamp + timeOffset);

        // Get divestible tokens
        uint256 divestible = ico.divestibleTokens(positionId);

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

        uint256 rate = ico.vestingRate();

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
}

