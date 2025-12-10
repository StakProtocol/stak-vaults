// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "./BaseTest.sol";

contract FlyingICOPositionsOfUserTest is BaseTest {
    function test_PositionsOfUser_SinglePosition() public {
        vm.prank(user1);
        ico.investEther{value: 1 ether}();

        uint256[] memory positions = ico.positionsOf(user1);
        assertEq(positions.length, 1);
        assertEq(positions[0], 0);
    }

    function test_PositionsOfUser_MultiplePositions() public {
        vm.startPrank(user1);
        ico.investEther{value: 1 ether}();
        ico.investEther{value: 0.5 ether}();
        usdc.approve(address(ico), 1000e6);
        ico.investERC20(address(usdc), 1000e6);
        vm.stopPrank();

        uint256[] memory positions = ico.positionsOf(user1);
        assertEq(positions.length, 3);
        assertEq(positions[0], 0);
        assertEq(positions[1], 1);
        assertEq(positions[2], 2);
    }

    function test_PositionsOfUser_NoPositions() public view {
        uint256[] memory positions = ico.positionsOf(user1);
        assertEq(positions.length, 0);
    }

    function test_PositionsOfUser_MultipleUsers() public {
        vm.prank(user1);
        ico.investEther{value: 1 ether}();

        vm.prank(user2);
        ico.investEther{value: 1 ether}();

        uint256[] memory positions1 = ico.positionsOf(user1);
        uint256[] memory positions2 = ico.positionsOf(user2);

        assertEq(positions1.length, 1);
        assertEq(positions1[0], 0);
        assertEq(positions2.length, 1);
        assertEq(positions2[0], 1);
    }
}

