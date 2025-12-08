// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "./BaseTest.sol";

contract FlyingICOIntegrationTest is BaseTest {
    function test_FullLifecycle() public {
        // 1. Invest
        vm.prank(user1);
        uint256 positionId = ico.investEther{value: 1 ether}();

        // 2. Partial divest (5000 tokens out of 20000)
        vm.prank(user1);
        ico.divest(positionId, 5000e18);

        // 3. Partial unlock (5000 tokens out of remaining 15000)
        vm.prank(user1);
        ico.unlock(positionId, 5000e18);

        // 4. Invest again
        vm.prank(user1);
        uint256 positionId2 = ico.investEther{value: 0.5 ether}();

        // 5. Full divest of position 2
        vm.prank(user1);
        ico.divest(positionId2, 10000e18);

        // Verify final state
        (,, uint256 assetAmount1, uint256 tokenAmount1,) = ico.positions(positionId);
        (,, uint256 assetAmount2, uint256 tokenAmount2,) = ico.positions(positionId2);
        // Position 1: started with 20000 tokens, divested 5000, withdrew 5000, so 10000 remaining
        assertEq(tokenAmount1, 10000e18);
        assertGt(assetAmount1, 0); // Some asset remaining
        // Position 2: fully divested
        assertEq(tokenAmount2, 0);
        assertEq(assetAmount2, 0);
    }

    function test_MultipleUsers_MultiplePositions() public {
        // User1 invests
        vm.prank(user1);
        ico.investEther{value: 1 ether}(); // 20000 tokens

        // User2 invests
        vm.prank(user2);
        ico.investEther{value: 1 ether}(); // 20000 tokens

        // User3 invests
        vm.startPrank(user3);
        usdc.approve(address(ico), 1000e6);
        ico.investERC20(address(usdc), 1000e6); // 10000 tokens
        vm.stopPrank();

        // All should have positions
        assertEq(ico.positionsOfUser(user1).length, 1);
        assertEq(ico.positionsOfUser(user2).length, 1);
        assertEq(ico.positionsOfUser(user3).length, 1);

        // Total supply should be 50000 tokens (20000 + 20000 + 10000)
        assertEq(ico.totalSupply(), 50000e18);
    }
}

