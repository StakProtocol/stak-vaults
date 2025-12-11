// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "./BaseTest.sol";

contract StakVaultMintTest is BaseTest {
    function test_Mint_Success_BeforeNav() public {
        uint256 shares = 1000e18;
        uint256 assets = vault.previewMint(shares);

        vm.startPrank(user1);
        asset.approve(address(vault), assets);

        vm.expectEmit(true, true, false, true);
        emit StakVault__Invested(user1, 0, assets, shares);

        uint256 assetsDeposited = vault.mint(shares, user1);
        vm.stopPrank();

        assertEq(assetsDeposited, assets);
        assertEq(vault.balanceOf(address(vault)), shares);
        assertEq(vault.balanceOf(user1), 0);

        (uint256 userAssets, uint256 userShares) = getLedger(user1);
        assertEq(userAssets, assets);
        assertEq(userShares, shares);
    }

    function test_Mint_Success_AfterNav() public {
        vm.prank(owner);
        vault.enableRedeemsAtNav();

        uint256 shares = 1000e18;
        uint256 assets = vault.previewMint(shares);

        vm.startPrank(user1);
        asset.approve(address(vault), assets);
        uint256 assetsDeposited = vault.mint(shares, user1);
        vm.stopPrank();

        assertEq(assetsDeposited, assets);
        assertEq(vault.balanceOf(user1), shares);
        assertEq(vault.balanceOf(address(vault)), 0);

        (uint256 userAssets, uint256 userShares) = getLedger(user1);
        assertEq(userAssets, 0);
        assertEq(userShares, 0);
    }

    function test_Mint_RevertWhen_ZeroShares() public {
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vm.expectRevert();
        vault.mint(0, user1);
        vm.stopPrank();
    }

    function test_Mint_RevertWhen_InsufficientAllowance() public {
        vm.startPrank(user1);
        asset.approve(address(vault), 100e18);
        vm.expectRevert();
        vault.mint(1000e18, user1);
        vm.stopPrank();
    }

    function test_Mint_WithInvestedAssets() public {
        // Deposit first to have some balance
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Add assets to simulate growth (before setting invested assets)
        asset.mint(address(vault), 500e18);

        // Set invested assets to 1000e18 (same as initial deposit)
        // This means totalAssets = 1500e18 (backing + invested)
        // totalSupply = 1000e18 (shares held by vault)
        // price per share = 1500e18 / 1000e18 = 1.5
        vm.prank(owner);
        vault.updateInvestedAssets(1000e18);

        uint256 shares = 1000e18;
        uint256 expectedAssets = vault.previewMint(shares);

        vm.startPrank(user1);
        asset.approve(address(vault), expectedAssets);
        uint256 assetsDeposited = vault.mint(shares, user1);
        vm.stopPrank();

        assertEq(assetsDeposited, expectedAssets);
        // When NAV > 1, assets needed for minting shares will be greater than shares
        // price per share = 1.5, so to mint 1000e18 shares, need 1500e18 assets
        assertGt(assetsDeposited, shares); // Assets should be greater than shares when NAV > 1
    }
}

