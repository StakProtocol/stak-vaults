// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "./BaseTest.sol";
import {FlyingICO} from "../../src/FlyingICO.sol";

contract FlyingICODivestTest is BaseTest {
    function test_Divest_ETH_Success() public {
        uint256 ethAmount = 1 ether;

        vm.prank(user1);
        uint256 positionId = ico.investEther{value: ethAmount}();

        uint256 tokensToBurn = 10000e18; // Half of the tokens
        uint256 expectedAssetReturn = 0.5 ether; // Half of the ETH

        uint256 balanceBefore = user1.balance;

        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit FlyingICO__Divested(user1, positionId, tokensToBurn, address(0), expectedAssetReturn);

        ico.divest(positionId, tokensToBurn);

        assertEq(user1.balance, balanceBefore + expectedAssetReturn);

        (,, uint256 assetAmount, uint256 tokenAmount,) = ico.positions(positionId);
        assertEq(tokenAmount, 10000e18);
        assertEq(assetAmount, 0.5 ether);
        assertEq(ico.backingBalances(address(0)), 0.5 ether);
        assertEq(ico.balanceOf(address(ico)), 10000e18);
    }

    function test_Divest_ERC20_Success() public {
        uint256 usdcAmount = 1000e6;

        vm.startPrank(user1);
        usdc.approve(address(ico), usdcAmount);
        uint256 positionId = ico.investERC20(address(usdc), usdcAmount);
        vm.stopPrank();

        uint256 tokensToBurn = 5000e18; // Half of the tokens
        uint256 expectedAssetReturn = 500e6; // Half of the USDC

        uint256 balanceBefore = usdc.balanceOf(user1);

        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit FlyingICO__Divested(user1, positionId, tokensToBurn, address(usdc), expectedAssetReturn);

        ico.divest(positionId, tokensToBurn);

        assertEq(usdc.balanceOf(user1), balanceBefore + expectedAssetReturn);

        (,, uint256 assetAmount, uint256 tokenAmount,) = ico.positions(positionId);
        assertEq(tokenAmount, 5000e18);
        assertEq(assetAmount, 500e6);
    }

    function test_Divest_AllTokens() public {
        uint256 ethAmount = 1 ether;

        vm.prank(user1);
        uint256 positionId = ico.investEther{value: ethAmount}();

        uint256 tokensToBurn = 20000e18; // All tokens

        vm.prank(user1);
        ico.divest(positionId, tokensToBurn);

        (,, uint256 assetAmount, uint256 tokenAmount,) = ico.positions(positionId);
        assertEq(tokenAmount, 0);
        assertEq(assetAmount, 0);
        assertEq(ico.backingBalances(address(0)), 0);
        assertEq(ico.balanceOf(address(ico)), 0);
    }

    function test_Divest_RevertWhen_ZeroValue() public {
        uint256 ethAmount = 1 ether;

        vm.prank(user1);
        uint256 positionId = ico.investEther{value: ethAmount}();

        vm.prank(user1);
        vm.expectRevert(FlyingICO.FlyingICO__ZeroValue.selector);
        ico.divest(positionId, 0);
    }

    function test_Divest_RevertWhen_NotEnoughLockedTokens() public {
        uint256 ethAmount = 1 ether;

        vm.prank(user1);
        uint256 positionId = ico.investEther{value: ethAmount}();

        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlyingICO.FlyingICO__NotEnoughDivestibleTokens.selector, positionId, 20001e18, 20000e18
            )
        );
        ico.divest(positionId, 20001e18); // More than available
    }

    function test_Divest_RevertWhen_NotPositionOwner() public {
        uint256 ethAmount = 1 ether;

        vm.prank(user1);
        uint256 positionId = ico.investEther{value: ethAmount}();

        // Only the position owner can divest
        vm.prank(user2);
        vm.expectRevert(FlyingICO.FlyingICO__Unauthorized.selector);
        ico.divest(positionId, 10000e18);
    }

    function test_Divest_WithRounding() public {
        // Test divest with amounts that cause rounding
        uint256 usdcAmount = 3e6; // 3 USDC = $3 USD = 30 tokens

        vm.startPrank(user1);
        usdc.approve(address(ico), usdcAmount);
        uint256 positionId = ico.investERC20(address(usdc), usdcAmount);
        vm.stopPrank();

        // Divest 1 token (should return 0.1 USDC, but with 6 decimals = 100000)
        uint256 tokensToBurn = 1e18;

        vm.prank(user1);
        ico.divest(positionId, tokensToBurn);

        // Position should have 29 tokens and 2.9 USDC remaining
        (,, uint256 assetAmount, uint256 tokenAmount,) = ico.positions(positionId);
        assertEq(tokenAmount, 29e18);
        // Asset amount should be approximately 2.9 USDC (with rounding)
        assertGe(assetAmount, 2900000); // At least 2.9 USDC
        assertLe(assetAmount, 3000000); // At most 3 USDC
    }
}

