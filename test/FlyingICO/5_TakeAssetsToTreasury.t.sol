// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "./BaseTest.sol";
import {FlyingICO} from "../../src/FlyingICO.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract FlyingICOTakeAssetsToTreasuryTest is BaseTest {
    function test_TakeAssetsToTreasury_ETH_Success() public {
        // First, invest some ETH
        vm.prank(user1);
        ico.investEther{value: 1 ether}();

        // Verify backing is set correctly
        assertEq(ico.backingBalances(address(0)), 1 ether);
        assertEq(address(ico).balance, 1 ether);

        // Unlock some tokens - this reduces backing and makes assets available
        vm.prank(user1);
        ico.unlock(0, 10000e18); // Unlock half (0.5 ether worth)

        // Backing should be reduced by the withdrawn amount
        assertEq(ico.backingBalances(address(0)), 0.5 ether);

        // Available ETH should now be 0.5 ether (total balance - backing)
        uint256 availableEther = address(ico).balance - ico.backingBalances(address(0));
        assertEq(availableEther, 0.5 ether);

        // Treasury should be able to take the available assets
        uint256 treasuryBalanceBefore = address(treasury).balance;
        vm.prank(treasury);
        ico.takeAssetsToTreasury(address(0), 0.3 ether);

        // Verify treasury received the ETH
        assertEq(address(treasury).balance, treasuryBalanceBefore + 0.3 ether);

        // Verify contract balance decreased
        assertEq(address(ico).balance, 0.7 ether);

        // Backing should remain unchanged
        assertEq(ico.backingBalances(address(0)), 0.5 ether);

        // Available ETH should now be 0.2 ether
        uint256 availableEtherAfter = address(ico).balance - ico.backingBalances(address(0));
        assertEq(availableEtherAfter, 0.2 ether);
    }

    function test_TakeAssetsToTreasury_ERC20_Success() public {
        vm.startPrank(user1);
        usdc.approve(address(ico), 1000e6);
        ico.investERC20(address(usdc), 1000e6);
        vm.stopPrank();

        // Verify backing is set correctly
        assertEq(ico.backingBalances(address(usdc)), 1000e6);
        assertEq(usdc.balanceOf(address(ico)), 1000e6);

        // Unlock some tokens - this reduces backing and makes assets available
        vm.prank(user1);
        ico.unlock(0, 5000e18); // Unlock half (500e6 worth)

        // Backing should be reduced by the withdrawn amount
        assertEq(ico.backingBalances(address(usdc)), 500e6);

        // Available USDC should now be 500e6 (total balance - backing)
        uint256 availableUsdc = usdc.balanceOf(address(ico)) - ico.backingBalances(address(usdc));
        assertEq(availableUsdc, 500e6);

        // Treasury should be able to take the available assets
        uint256 treasuryBalanceBefore = usdc.balanceOf(treasury);
        vm.prank(treasury);
        ico.takeAssetsToTreasury(address(usdc), 300e6);

        // Verify treasury received the USDC
        assertEq(usdc.balanceOf(treasury), treasuryBalanceBefore + 300e6);

        // Verify contract balance decreased
        assertEq(usdc.balanceOf(address(ico)), 700e6);

        // Backing should remain unchanged
        assertEq(ico.backingBalances(address(usdc)), 500e6);

        // Available USDC should now be 200e6
        uint256 availableUsdcAfter = usdc.balanceOf(address(ico)) - ico.backingBalances(address(usdc));
        assertEq(availableUsdcAfter, 200e6);
    }

    function test_TakeAssetsToTreasury_RevertWhen_ZeroValue() public {
        vm.prank(treasury);
        vm.expectRevert(FlyingICO.FlyingICO__ZeroValue.selector);
        ico.takeAssetsToTreasury(address(0), 0);
    }

    function test_TakeAssetsToTreasury_RevertWhen_AssetNotAccepted() public {
        MockERC20 invalidToken = new MockERC20("Invalid", "INV", 18);

        vm.prank(treasury);
        vm.expectRevert(abi.encodeWithSelector(FlyingICO.FlyingICO__AssetNotAccepted.selector, address(invalidToken)));
        ico.takeAssetsToTreasury(address(invalidToken), 1000e18);
    }

    function test_TakeAssetsToTreasury_RevertWhen_InsufficientETH() public {
        vm.prank(user1);
        ico.investEther{value: 1 ether}();

        // Try to take more than available (all is in backing)
        vm.prank(treasury);
        vm.expectRevert(FlyingICO.FlyingICO__InsufficientEther.selector);
        ico.takeAssetsToTreasury(address(0), 0.1 ether);
    }

    function test_TakeAssetsToTreasury_RevertWhen_InsufficientAssetAmount() public {
        vm.startPrank(user1);
        usdc.approve(address(ico), 1000e6);
        ico.investERC20(address(usdc), 1000e6);
        vm.stopPrank();

        // Try to take more than available (all is in backing)
        vm.prank(treasury);
        vm.expectRevert(FlyingICO.FlyingICO__InsufficientAssetAmount.selector);
        ico.takeAssetsToTreasury(address(usdc), 100e6);
    }
}

