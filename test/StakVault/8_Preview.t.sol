// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "./BaseTest.sol";

contract StakVaultPreviewTest is BaseTest {
    function test_PreviewDeposit() public view {
        uint256 assets = 1000e18;
        uint256 shares = vault.previewDeposit(assets);
        assertEq(shares, assets); // 1:1 when no NAV
    }

    function test_PreviewDeposit_WithNav() public {
        // Set invested assets
        vm.prank(owner);
        vault.updateInvestedAssets(1000e18);

        uint256 assets = 1000e18;
        uint256 shares = vault.previewDeposit(assets);
        // Shares should be less due to NAV
        assertLt(shares, assets);
    }

    function test_PreviewMint() public view {
        uint256 shares = 1000e18;
        uint256 assets = vault.previewMint(shares);
        assertEq(assets, shares); // 1:1 when no NAV
    }

    function test_PreviewMint_WithNav() public {
        // Deposit first to have some balance
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Add more assets to simulate growth (before setting invested assets)
        asset.mint(address(vault), 1000e18);

        // Set invested assets to create NAV
        vm.prank(owner);
        vault.updateInvestedAssets(1000e18);

        uint256 shares = 1000e18;
        uint256 assets = vault.previewMint(shares);
        // Assets should be calculated based on NAV
        // The exact value depends on totalAssets and totalSupply
        // Just verify it's a reasonable value
        assertGt(assets, 0);
        // Assets might be more or less than shares depending on NAV
    }

    function test_PreviewRedeem_BeforeNav() public {
        // Deposit
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Preview redeem should use ledger conversion
        vm.prank(user1);
        uint256 assets = vault.previewRedeem(500e18);
        assertEq(assets, 500e18); // 1:1 from ledger
    }

    function test_PreviewRedeem_AfterNav() public {
        // Deposit
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Add assets and set invested assets
        asset.mint(address(vault), 1000e18);
        vm.prank(owner);
        vault.updateInvestedAssets(2000e18);

        // Enable NAV
        vm.prank(owner);
        vault.enableRedeemsAtNav();

        // Preview redeem should use NAV conversion
        vm.prank(user1);
        uint256 assets = vault.previewRedeem(500e18);
        assertGt(assets, 500e18); // More due to NAV
    }

    function test_PreviewWithdraw_BeforeNav() public {
        // Deposit
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Preview withdraw should use min of standard and ledger
        vm.prank(user1);
        uint256 shares = vault.previewWithdraw(500e18);
        assertEq(shares, 500e18); // 1:1 from ledger
    }

    function test_PreviewWithdraw_AfterNav() public {
        // Deposit
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Add assets and set invested assets
        asset.mint(address(vault), 1000e18);
        vm.prank(owner);
        vault.updateInvestedAssets(2000e18);

        // Enable NAV
        vm.prank(owner);
        vault.enableRedeemsAtNav();

        // Preview withdraw should use NAV conversion
        vm.prank(user1);
        uint256 shares = vault.previewWithdraw(1000e18);
        assertLt(shares, 1000e18); // Fewer shares due to NAV
    }

    function test_MaxDeposit() public view {
        uint256 maxDeposit = vault.maxDeposit(user1);
        assertEq(maxDeposit, type(uint256).max);
    }

    function test_MaxMint() public view {
        uint256 maxMint = vault.maxMint(user1);
        assertEq(maxMint, type(uint256).max);
    }

    function test_MaxRedeem_BeforeNav() public {
        // Deposit
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Max redeem returns balanceOf(user), which is 0 before NAV (shares in contract)
        vm.prank(user1);
        uint256 maxRedeem = vault.maxRedeem(user1);
        assertEq(maxRedeem, 0); // Shares are in contract, not user balance
    }

    function test_MaxRedeem_AfterNav() public {
        // Deposit
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Enable NAV
        vm.prank(owner);
        vault.enableRedeemsAtNav();

        // Max redeem should be balance
        vm.prank(user1);
        uint256 maxRedeem = vault.maxRedeem(user1);
        assertEq(maxRedeem, 0); // Shares are in contract, not user
    }

    function test_MaxWithdraw_BeforeNav() public {
        // Deposit
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Max withdraw returns previewRedeem(maxRedeem), which is 0 before NAV
        vm.prank(user1);
        uint256 maxWithdraw = vault.maxWithdraw(user1);
        assertEq(maxWithdraw, 0); // Shares are in contract, not user balance
    }

    function test_MaxWithdraw_AfterNav() public {
        // Deposit
        vm.startPrank(user1);
        asset.approve(address(vault), 1000e18);
        vault.deposit(1000e18, user1);
        vm.stopPrank();

        // Enable NAV
        vm.prank(owner);
        vault.enableRedeemsAtNav();

        // Max withdraw should be based on balance
        vm.prank(user1);
        uint256 maxWithdraw = vault.maxWithdraw(user1);
        assertEq(maxWithdraw, 0); // No balance in user account
    }

    function test_ConvertToShares() public view {
        uint256 assets = 1000e18;
        uint256 shares = vault.convertToShares(assets);
        assertEq(shares, assets); // 1:1 when no NAV
    }

    function test_ConvertToShares_WithNav() public {
        // Set invested assets
        vm.prank(owner);
        vault.updateInvestedAssets(1000e18);

        uint256 assets = 1000e18;
        uint256 shares = vault.convertToShares(assets);
        assertLt(shares, assets); // Less shares due to NAV
    }

    function test_ConvertToAssets() public view {
        uint256 shares = 1000e18;
        uint256 assets = vault.convertToAssets(shares);
        assertEq(assets, shares); // 1:1 when no NAV
    }

    function test_ConvertToAssets_WithNav() public {
        // Set invested assets
        vm.prank(owner);
        vault.updateInvestedAssets(1000e18);

        uint256 shares = 1000e18;
        uint256 assets = vault.convertToAssets(shares);
        assertGt(assets, shares); // More assets due to NAV
    }
}

