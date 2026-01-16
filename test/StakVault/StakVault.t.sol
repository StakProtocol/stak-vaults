// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/src/Test.sol";

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/interfaces/IERC4626.sol";

import {StakVault} from "../../src/StakVault.sol";
import {StakVaultHarness} from "../mocks/StakVaultHarness.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockERC4626Vault} from "../mocks/MockERC4626Vault.sol";
import {MockIlliquidERC4626Vault} from "../mocks/MockIlliquidERC4626Vault.sol";
import {MockFeeChargingERC4626Vault} from "../mocks/MockFeeChargingERC4626Vault.sol";
import {MockDepositReturnMismatchERC4626Vault} from "../mocks/MockDepositReturnMismatchERC4626Vault.sol";
import {MockPreviewRedeemShortfallERC4626Vault} from "../mocks/MockPreviewRedeemShortfallERC4626Vault.sol";

contract StakVaultTest is Test {
    uint256 internal constant BPS = 10_000;

    address internal owner = address(0xA11CE);
    address internal treasury = address(0xB0B);
    address internal user1 = address(0x1111);
    address internal user2 = address(0x2222);

    MockERC20 internal asset;

    uint256 internal vestingStart;
    uint256 internal vestingEnd;

    function _deployHarness(
        IERC4626 redeemable_,
        IERC4626 vesting_,
        uint256 performanceRate,
        uint256 redemptionFee,
        uint256 maxSlippage
    ) internal returns (StakVaultHarness h) {
        vestingStart = block.timestamp + 7 days;
        vestingEnd = block.timestamp + 37 days;

        vm.prank(owner);
        h = new StakVaultHarness(
            IERC20(address(asset)),
            "StakVault",
            "SVLT",
            owner,
            treasury,
            address(redeemable_),
            address(vesting_),
            performanceRate,
            vestingStart,
            vestingEnd,
            redemptionFee,
            maxSlippage
        );
    }

    function setUp() public {
        asset = new MockERC20("Asset", "AST", 18);

        asset.mint(user1, 1_000_000e18);
        asset.mint(user2, 1_000_000e18);
        asset.mint(owner, 1_000_000e18);
    }

    // =========================================================================
    // Constructor
    // =========================================================================

    function test_constructor_sets_expected_state_and_allowances() public {
        MockERC4626Vault redeemable = new MockERC4626Vault(IERC20(address(asset)), "Redeem", "rAST");
        MockERC4626Vault vesting = new MockERC4626Vault(IERC20(address(asset)), "Vesting", "vAST");

        StakVaultHarness h = _deployHarness(redeemable, vesting, 2000, 0, 0);

        assertEq(h.owner(), owner);
        assertEq(uint256(h.redemptionState()), uint256(StakVault.RedemptionState.SemiRedeemable));
        assertTrue(h.takesDeposits());
        assertEq(h.highWaterMark(), 1e18);
        assertEq(h.totalRedemptionLiability(), 0);
        assertEq(h.nextPositionId(), 0);
        assertEq(h.totalSupply(), 0);

        assertEq(asset.allowance(address(h), address(redeemable)), type(uint256).max);
        assertEq(asset.allowance(address(h), address(vesting)), type(uint256).max);
    }

    function test_constructor_reverts_on_zero_addresses() public {
        MockERC4626Vault redeemable = new MockERC4626Vault(IERC20(address(asset)), "Redeem", "rAST");
        MockERC4626Vault vesting = new MockERC4626Vault(IERC20(address(asset)), "Vesting", "vAST");

        vestingStart = block.timestamp + 7 days;
        vestingEnd = block.timestamp + 37 days;

        vm.expectRevert(StakVault.StakVault__ZeroAddress.selector);
        vm.prank(owner);
        new StakVault(
            IERC20(address(asset)),
            "StakVault",
            "SVLT",
            owner,
            address(0),
            address(redeemable),
            address(vesting),
            2000,
            vestingStart,
            vestingEnd,
            0,
            0
        );
    }

    function test_constructor_reverts_on_invalid_performance_rate() public {
        MockERC4626Vault redeemable = new MockERC4626Vault(IERC20(address(asset)), "Redeem", "rAST");
        MockERC4626Vault vesting = new MockERC4626Vault(IERC20(address(asset)), "Vesting", "vAST");

        vestingStart = block.timestamp + 7 days;
        vestingEnd = block.timestamp + 37 days;

        vm.expectRevert(abi.encodeWithSelector(StakVault.StakVault__InvalidPerformanceRate.selector, 5001));
        vm.prank(owner);
        new StakVault(
            IERC20(address(asset)),
            "StakVault",
            "SVLT",
            owner,
            treasury,
            address(redeemable),
            address(vesting),
            5001,
            vestingStart,
            vestingEnd,
            0,
            0
        );
    }

    function test_constructor_reverts_on_invalid_vesting_schedule_start_in_past() public {
        MockERC4626Vault redeemable = new MockERC4626Vault(IERC20(address(asset)), "Redeem", "rAST");
        MockERC4626Vault vesting = new MockERC4626Vault(IERC20(address(asset)), "Vesting", "vAST");

        uint256 vs = block.timestamp - 1;
        uint256 ve = block.timestamp + 1;

        vm.expectRevert(abi.encodeWithSelector(StakVault.StakVault__InvalidVestingSchedule.selector, block.timestamp, vs, ve));
        vm.prank(owner);
        new StakVault(
            IERC20(address(asset)),
            "StakVault",
            "SVLT",
            owner,
            treasury,
            address(redeemable),
            address(vesting),
            0,
            vs,
            ve,
            0,
            0
        );
    }

    function test_constructor_reverts_on_invalid_vesting_schedule_end_before_start() public {
        MockERC4626Vault redeemable = new MockERC4626Vault(IERC20(address(asset)), "Redeem", "rAST");
        MockERC4626Vault vesting = new MockERC4626Vault(IERC20(address(asset)), "Vesting", "vAST");

        uint256 vs = block.timestamp + 10;
        uint256 ve = vs - 1;

        vm.expectRevert(abi.encodeWithSelector(StakVault.StakVault__InvalidVestingSchedule.selector, block.timestamp, vs, ve));
        vm.prank(owner);
        new StakVault(
            IERC20(address(asset)),
            "StakVault",
            "SVLT",
            owner,
            treasury,
            address(redeemable),
            address(vesting),
            0,
            vs,
            ve,
            0,
            0
        );
    }

    function test_constructor_reverts_on_invalid_max_slippage() public {
        MockERC4626Vault redeemable = new MockERC4626Vault(IERC20(address(asset)), "Redeem", "rAST");
        MockERC4626Vault vesting = new MockERC4626Vault(IERC20(address(asset)), "Vesting", "vAST");

        vestingStart = block.timestamp + 7 days;
        vestingEnd = block.timestamp + 37 days;

        vm.expectRevert(abi.encodeWithSelector(StakVault.StakVault__InvalidMaxSlippage.selector, BPS + 1));
        vm.prank(owner);
        new StakVault(
            IERC20(address(asset)),
            "StakVault",
            "SVLT",
            owner,
            treasury,
            address(redeemable),
            address(vesting),
            0,
            vestingStart,
            vestingEnd,
            0,
            BPS + 1
        );
    }

    // =========================================================================
    // Owner controls / pause
    // =========================================================================

    function test_setTakesDeposits_blocks_deposit_and_mint() public {
        MockERC4626Vault redeemable = new MockERC4626Vault(IERC20(address(asset)), "Redeem", "rAST");
        MockERC4626Vault vesting = new MockERC4626Vault(IERC20(address(asset)), "Vesting", "vAST");
        StakVaultHarness h = _deployHarness(redeemable, vesting, 0, 0, 0);

        vm.prank(owner);
        h.setTakesDeposits(false);

        vm.startPrank(user1);
        asset.approve(address(h), type(uint256).max);

        vm.expectRevert(StakVault.StakVault__DepositsDisabled.selector);
        h.deposit(1e18, user1);

        vm.expectRevert(StakVault.StakVault__DepositsDisabled.selector);
        h.mint(1e18, user1);

        vm.stopPrank();
    }

    function test_pause_unpause_gates_whenNotPaused_functions() public {
        MockERC4626Vault redeemable = new MockERC4626Vault(IERC20(address(asset)), "Redeem", "rAST");
        MockERC4626Vault vesting = new MockERC4626Vault(IERC20(address(asset)), "Vesting", "vAST");
        StakVaultHarness h = _deployHarness(redeemable, vesting, 0, 0, 0);

        vm.prank(owner);
        h.pause();

        vm.startPrank(user1);
        asset.approve(address(h), type(uint256).max);
        vm.expectRevert();
        h.deposit(1e18, user1);
        vm.stopPrank();

        vm.prank(owner);
        h.unpause();

        vm.startPrank(user1);
        asset.approve(address(h), type(uint256).max);
        h.deposit(1e18, user1);
        vm.stopPrank();
    }

    function test_pause_unpause_on_base_contract_instance() public {
        MockERC4626Vault redeemable = new MockERC4626Vault(IERC20(address(asset)), "Redeem", "rAST");
        MockERC4626Vault vesting = new MockERC4626Vault(IERC20(address(asset)), "Vesting", "vAST");

        uint256 vs = block.timestamp + 7 days;
        uint256 ve = block.timestamp + 37 days;

        vm.prank(owner);
        StakVault v = new StakVault(
            IERC20(address(asset)),
            "BaseVault",
            "BVAULT",
            owner,
            treasury,
            address(redeemable),
            address(vesting),
            0,
            vs,
            ve,
            0,
            0
        );

        vm.prank(owner);
        v.pause();
        assertTrue(v.paused());

        vm.prank(owner);
        v.unpause();
        assertFalse(v.paused());
    }

    function test_setMaxSlippage_enforces_bounds_and_affects_withdraw_shortfall_tolerance() public {
        // Fee-charging redeemable vault creates a withdraw shortfall.
        MockFeeChargingERC4626Vault feeRedeemable =
            new MockFeeChargingERC4626Vault(IERC20(address(asset)), "FeeRedeem", "frAST", 100, address(0xFEE));
        MockERC4626Vault vesting = new MockERC4626Vault(IERC20(address(asset)), "Vesting", "vAST");

        // Start with 0 slippage tolerance.
        StakVaultHarness h = _deployHarness(feeRedeemable, vesting, 0, 0, 0);

        vm.startPrank(user1);
        asset.approve(address(h), type(uint256).max);
        uint256 shares = h.deposit(100e18, user1);
        vm.stopPrank();

        // Redeem in semi mode -> underlying withdraw returns 99%, should revert with 0 slippage tolerance.
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(StakVault.StakVault__UnderlyingWithdrawShortfall.selector, 100e18, 99e18));
        h.redeem(0, shares, user1);

        // Increase slippage tolerance to 1% and retry: should now succeed.
        vm.prank(owner);
        h.setMaxSlippage(100);

        vm.prank(user1);
        h.redeem(0, shares, user1);
    }

    function test_setMaxSlippage_reverts_when_over_bps() public {
        MockERC4626Vault redeemable = new MockERC4626Vault(IERC20(address(asset)), "Redeem", "rAST");
        MockERC4626Vault vesting = new MockERC4626Vault(IERC20(address(asset)), "Vesting", "vAST");
        StakVaultHarness h = _deployHarness(redeemable, vesting, 0, 0, 0);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(StakVault.StakVault__InvalidMaxSlippage.selector, BPS + 1));
        h.setMaxSlippage(BPS + 1);
    }

    function test_takeRewards_transfers_entire_token_balance_to_treasury() public {
        MockERC4626Vault redeemable = new MockERC4626Vault(IERC20(address(asset)), "Redeem", "rAST");
        MockERC4626Vault vesting = new MockERC4626Vault(IERC20(address(asset)), "Vesting", "vAST");
        StakVaultHarness h = _deployHarness(redeemable, vesting, 0, 0, 0);

        MockERC20 reward = new MockERC20("Reward", "RWD", 18);
        reward.mint(address(h), 123e18);

        uint256 treasuryBefore = reward.balanceOf(treasury);
        vm.prank(owner);
        h.takeRewards(address(reward));
        assertEq(reward.balanceOf(treasury) - treasuryBefore, 123e18);
        assertEq(reward.balanceOf(address(h)), 0);
    }

    // =========================================================================
    // Vesting math / redeemableShares
    // =========================================================================

    function test_vestingRate_phases() public {
        MockERC4626Vault redeemable = new MockERC4626Vault(IERC20(address(asset)), "Redeem", "rAST");
        MockERC4626Vault vesting = new MockERC4626Vault(IERC20(address(asset)), "Vesting", "vAST");
        StakVaultHarness h = _deployHarness(redeemable, vesting, 0, 0, 0);

        // Pre-start: 100%
        assertEq(h.vestingRate(), BPS);
        assertEq(h.exposed_calculateVestingRate(), BPS);

        // Mid-vesting: strictly between (0, BPS)
        vm.warp(vestingStart + (vestingEnd - vestingStart) / 2);
        uint256 mid = h.vestingRate();
        assertTrue(mid > 0 && mid < BPS);

        // Post-end: 0%
        vm.warp(vestingEnd + 1);
        assertEq(h.vestingRate(), 0);
    }

    function test_redeemableShares_becomes_zero_once_all_position_shares_claimed() public {
        MockERC4626Vault redeemable = new MockERC4626Vault(IERC20(address(asset)), "Redeem", "rAST");
        MockERC4626Vault vesting = new MockERC4626Vault(IERC20(address(asset)), "Vesting", "vAST");
        StakVaultHarness h = _deployHarness(redeemable, vesting, 0, 0, 0);

        vm.startPrank(user1);
        asset.approve(address(h), type(uint256).max);
        uint256 shares = h.deposit(10e18, user1);
        h.claim(0, shares, user1);
        vm.stopPrank();

        assertEq(h.redeemableShares(0), 0);
    }

    function test_positionsOf_returns_position_ids() public {
        MockERC4626Vault redeemable = new MockERC4626Vault(IERC20(address(asset)), "Redeem", "rAST");
        MockERC4626Vault vesting = new MockERC4626Vault(IERC20(address(asset)), "Vesting", "vAST");
        StakVaultHarness h = _deployHarness(redeemable, vesting, 0, 0, 0);

        vm.startPrank(user1);
        asset.approve(address(h), type(uint256).max);
        h.deposit(1e18, user1);
        h.deposit(2e18, user1);
        vm.stopPrank();

        uint256[] memory ids = h.positionsOf(user1);
        assertEq(ids.length, 2);
        assertEq(ids[0], 0);
        assertEq(ids[1], 1);
    }

    // =========================================================================
    // Semi-redeemable flow: deposit -> claim / redeem(positionId)
    // =========================================================================

    function test_deposit_creates_position_moves_assets_and_tracks_liability() public {
        MockERC4626Vault redeemable = new MockERC4626Vault(IERC20(address(asset)), "Redeem", "rAST");
        MockERC4626Vault vesting = new MockERC4626Vault(IERC20(address(asset)), "Vesting", "vAST");
        StakVaultHarness h = _deployHarness(redeemable, vesting, 0, 0, 0);

        vm.startPrank(user1);
        asset.approve(address(h), type(uint256).max);
        uint256 shares = h.deposit(100e18, user1);
        vm.stopPrank();

        (address posUser, uint256 posAssets, uint256 posShares, uint256 totalShares) = h.positions(0);
        assertEq(posUser, user1);
        assertEq(posAssets, 100e18);
        assertEq(posShares, shares);
        assertEq(totalShares, shares);

        assertEq(h.totalRedemptionLiability(), 100e18);

        // Assets should end up in redeemable vault.
        assertEq(asset.balanceOf(address(redeemable)), 100e18);
        assertEq(asset.balanceOf(address(h)), 0);
        assertGt(redeemable.balanceOf(address(h)), 0);
    }

    function test_claim_transfers_shares_and_reduces_liability_proportionally() public {
        MockERC4626Vault redeemable = new MockERC4626Vault(IERC20(address(asset)), "Redeem", "rAST");
        MockERC4626Vault vesting = new MockERC4626Vault(IERC20(address(asset)), "Vesting", "vAST");
        StakVaultHarness h = _deployHarness(redeemable, vesting, 0, 0, 0);

        vm.startPrank(user1);
        asset.approve(address(h), type(uint256).max);
        uint256 shares = h.deposit(100e18, user1);
        uint256 toClaim = shares / 2;
        uint256 assetsReturned = h.claim(0, toClaim, user1);
        vm.stopPrank();

        // Claim does not transfer assets; it transfers shares and returns the par value removed from liability.
        assertEq(assetsReturned, 50e18);
        assertEq(h.balanceOf(user1), toClaim);
        assertEq(h.totalRedemptionLiability(), 50e18);

        (,, uint256 remainingShares, uint256 totalSharesAfter) = h.positions(0);
        assertEq(remainingShares, shares - toClaim);
        // Pre-vesting-start branch reduces totalShares as well.
        assertEq(totalSharesAfter, shares - toClaim);
    }

    function test_claim_during_vesting_does_not_reduce_totalShares() public {
        MockERC4626Vault redeemable = new MockERC4626Vault(IERC20(address(asset)), "Redeem", "rAST");
        MockERC4626Vault vesting = new MockERC4626Vault(IERC20(address(asset)), "Vesting", "vAST");
        StakVaultHarness h = _deployHarness(redeemable, vesting, 0, 0, 0);

        vm.startPrank(user1);
        asset.approve(address(h), type(uint256).max);
        uint256 shares = h.deposit(100e18, user1);
        vm.warp(vestingStart + (vestingEnd - vestingStart) / 2);
        h.claim(0, shares / 2, user1);
        vm.stopPrank();

        (,,, uint256 totalSharesAfter) = h.positions(0);
        assertEq(totalSharesAfter, shares);
    }

    function test_redeem_semi_transfers_assets_minus_fee_and_burns_locked_shares() public {
        MockERC4626Vault redeemable = new MockERC4626Vault(IERC20(address(asset)), "Redeem", "rAST");
        MockERC4626Vault vesting = new MockERC4626Vault(IERC20(address(asset)), "Vesting", "vAST");
        StakVaultHarness h = _deployHarness(redeemable, vesting, 0, 100, 0); // 1% redemption fee

        vm.startPrank(user1);
        asset.approve(address(h), type(uint256).max);
        uint256 shares = h.deposit(100e18, user1);
        vm.stopPrank();

        uint256 userBefore = asset.balanceOf(user1);
        uint256 treasuryBefore = asset.balanceOf(treasury);

        vm.prank(user1);
        uint256 assetsPaid = h.redeem(0, shares, user1);

        // With 0 slippage and compliant vault, safeWithdraw should receive full 100e18.
        assertEq(assetsPaid, 100e18);
        assertEq(asset.balanceOf(user1) - userBefore, 99e18);
        assertEq(asset.balanceOf(treasury) - treasuryBefore, 1e18);
        assertEq(h.totalSupply(), 0);
    }

    function test_redeem_semi_reverts_when_shares_exceed_redeemableShares() public {
        MockERC4626Vault redeemable = new MockERC4626Vault(IERC20(address(asset)), "Redeem", "rAST");
        MockERC4626Vault vesting = new MockERC4626Vault(IERC20(address(asset)), "Vesting", "vAST");
        StakVaultHarness h = _deployHarness(redeemable, vesting, 0, 0, 0);

        vm.startPrank(user1);
        asset.approve(address(h), type(uint256).max);
        uint256 shares = h.deposit(1e18, user1);
        vm.stopPrank();

        vm.warp(vestingEnd + 1);
        uint256 available = h.redeemableShares(0);
        assertEq(available, 0);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(StakVault.StakVault__NotEnoughRedeemableShares.selector, 0, 1, 0));
        h.redeem(0, 1, user1);

        // (cover: shares > redeemableShares branch, even though shares is small)
        assertGt(shares, 0);
    }

    function test_redeem_semi_reverts_on_unauthorized_position() public {
        MockERC4626Vault redeemable = new MockERC4626Vault(IERC20(address(asset)), "Redeem", "rAST");
        MockERC4626Vault vesting = new MockERC4626Vault(IERC20(address(asset)), "Vesting", "vAST");
        StakVaultHarness h = _deployHarness(redeemable, vesting, 0, 0, 0);

        vm.startPrank(user1);
        asset.approve(address(h), type(uint256).max);
        uint256 shares = h.deposit(1e18, user1);
        vm.stopPrank();

        vm.prank(user2);
        vm.expectRevert(StakVault.StakVault__Unauthorized.selector);
        h.redeem(0, shares, user1);
    }

    function test_redeem_and_claim_revert_on_zero_shares() public {
        MockERC4626Vault redeemable = new MockERC4626Vault(IERC20(address(asset)), "Redeem", "rAST");
        MockERC4626Vault vesting = new MockERC4626Vault(IERC20(address(asset)), "Vesting", "vAST");
        StakVaultHarness h = _deployHarness(redeemable, vesting, 0, 0, 0);

        vm.startPrank(user1);
        asset.approve(address(h), type(uint256).max);
        h.deposit(1e18, user1);

        vm.expectRevert(StakVault.StakVault__ZeroValue.selector);
        h.claim(0, 0, user1);

        vm.expectRevert(StakVault.StakVault__ZeroValue.selector);
        h.redeem(0, 0, user1);
        vm.stopPrank();
    }

    function test_claim_reverts_when_not_enough_locked_shares() public {
        MockERC4626Vault redeemable = new MockERC4626Vault(IERC20(address(asset)), "Redeem", "rAST");
        MockERC4626Vault vesting = new MockERC4626Vault(IERC20(address(asset)), "Vesting", "vAST");
        StakVaultHarness h = _deployHarness(redeemable, vesting, 0, 0, 0);

        vm.startPrank(user1);
        asset.approve(address(h), type(uint256).max);
        uint256 shares = h.deposit(1e18, user1);
        h.claim(0, shares, user1);

        vm.expectRevert(StakVault.StakVault__NotEnoughLockedShares.selector);
        h.claim(0, 1, user1);
        vm.stopPrank();
    }

    // =========================================================================
    // Fully redeemable mode: ERC4626 withdraw/redeem
    // =========================================================================

    function test_withdraw_and_redeem_revert_in_semi_mode() public {
        MockERC4626Vault redeemable = new MockERC4626Vault(IERC20(address(asset)), "Redeem", "rAST");
        MockERC4626Vault vesting = new MockERC4626Vault(IERC20(address(asset)), "Vesting", "vAST");
        StakVaultHarness h = _deployHarness(redeemable, vesting, 0, 0, 0);

        vm.prank(user1);
        vm.expectRevert(StakVault.StakVault__FullyRedeemableModeOnly.selector);
        h.withdraw(1e18, user1, user1);

        vm.prank(user1);
        vm.expectRevert(StakVault.StakVault__FullyRedeemableModeOnly.selector);
        h.redeem(1e18, user1, user1);
    }

    function test_enableFullyRedeemableMode_allows_withdraw_and_redeem_and_blocks_vest() public {
        MockERC4626Vault redeemable = new MockERC4626Vault(IERC20(address(asset)), "Redeem", "rAST");
        MockERC4626Vault vesting = new MockERC4626Vault(IERC20(address(asset)), "Vesting", "vAST");
        StakVaultHarness h = _deployHarness(redeemable, vesting, 0, 0, 0);

        // Deposit into position, then claim shares so user can use ERC4626 redeem/withdraw later.
        vm.startPrank(user1);
        asset.approve(address(h), type(uint256).max);
        uint256 shares = h.deposit(100e18, user1);
        h.claim(0, shares, user1);
        vm.stopPrank();

        vm.prank(owner);
        h.enableFullyRedeemableMode();

        vm.prank(user1);
        vm.expectRevert(StakVault.StakVault__SemiRedeemableModeOnly.selector);
        h.vest();

        uint256 userBefore = asset.balanceOf(user1);
        vm.prank(user1);
        uint256 burned = h.withdraw(40e18, user1, user1);
        assertGt(burned, 0);
        assertEq(asset.balanceOf(user1) - userBefore, 40e18);

        // Redeem remaining shares at NAV.
        uint256 remainingShares = h.balanceOf(user1);
        vm.prank(user1);
        h.redeem(remainingShares, user1, user1);
        assertEq(h.balanceOf(user1), 0);
    }

    function test_redeem_position_reverts_in_fully_mode() public {
        MockERC4626Vault redeemable = new MockERC4626Vault(IERC20(address(asset)), "Redeem", "rAST");
        MockERC4626Vault vesting = new MockERC4626Vault(IERC20(address(asset)), "Vesting", "vAST");
        StakVaultHarness h = _deployHarness(redeemable, vesting, 0, 0, 0);

        vm.startPrank(user1);
        asset.approve(address(h), type(uint256).max);
        uint256 shares = h.deposit(10e18, user1);
        vm.stopPrank();

        vm.prank(owner);
        h.enableFullyRedeemableMode();

        vm.prank(user1);
        vm.expectRevert(StakVault.StakVault__SemiRedeemableModeOnly.selector);
        h.redeem(0, shares, user1);
    }

    function test_delegated_withdraw_and_redeem_work_in_fully_mode() public {
        MockERC4626Vault redeemable = new MockERC4626Vault(IERC20(address(asset)), "Redeem", "rAST");
        MockERC4626Vault vesting = new MockERC4626Vault(IERC20(address(asset)), "Vesting", "vAST");
        StakVaultHarness h = _deployHarness(redeemable, vesting, 0, 0, 0);

        vm.startPrank(user1);
        asset.approve(address(h), type(uint256).max);
        uint256 shares = h.deposit(100e18, user1);
        h.claim(0, shares, user1);
        vm.stopPrank();

        vm.prank(owner);
        h.enableFullyRedeemableMode();

        // Delegate shares to user2.
        vm.prank(user1);
        h.approve(user2, type(uint256).max);

        uint256 user1Before = asset.balanceOf(user1);
        vm.prank(user2);
        h.withdraw(10e18, user1, user1);
        assertEq(asset.balanceOf(user1) - user1Before, 10e18);

        uint256 remainingShares = h.balanceOf(user1);
        vm.prank(user2);
        h.redeem(remainingShares, user1, user1);
        assertEq(h.balanceOf(user1), 0);
    }

    // =========================================================================
    // Rebalancing: vest() / liquidate()
    // =========================================================================

    function test_vest_moves_only_surplus_over_redemption_liability() public {
        MockERC4626Vault redeemable = new MockERC4626Vault(IERC20(address(asset)), "Redeem", "rAST");
        MockERC4626Vault vesting = new MockERC4626Vault(IERC20(address(asset)), "Vesting", "vAST");
        StakVaultHarness h = _deployHarness(redeemable, vesting, 0, 0, 0);

        vm.startPrank(user1);
        asset.approve(address(h), type(uint256).max);
        h.deposit(100e18, user1);
        vm.stopPrank();

        // No yield -> redeemableAssets == liability -> vest is no-op.
        assertEq(h.vest(), 0);

        // Add yield to redeemable vault so redeemableAssets > liability.
        asset.mint(address(redeemable), 50e18);
        uint256 moved = h.vest();
        // Rounding in underlying vault conversions can cause off-by-1 wei.
        assertApproxEqAbs(moved, 50e18, 1);
        assertApproxEqAbs(asset.balanceOf(address(vesting)), 50e18, 1);
    }

    function test_liquidate_moves_up_to_maxWithdraw_from_vesting_back_to_redeemable() public {
        MockERC4626Vault redeemable = new MockERC4626Vault(IERC20(address(asset)), "Redeem", "rAST");
        MockIlliquidERC4626Vault illiquidVesting =
            new MockIlliquidERC4626Vault(IERC20(address(asset)), "IlliquidVesting", "ivAST", 10e18);
        // Allow tiny rounding error on deposits back into the redeemable vault.
        StakVaultHarness h = _deployHarness(redeemable, illiquidVesting, 0, 0, 1);

        vm.startPrank(user1);
        asset.approve(address(h), type(uint256).max);
        h.deposit(100e18, user1);
        vm.stopPrank();

        asset.mint(address(redeemable), 25e18);
        uint256 vested = h.vest();
        assertApproxEqAbs(vested, 25e18, 1);

        vm.prank(owner);
        uint256 moved1 = h.liquidate();
        vm.prank(owner);
        uint256 moved2 = h.liquidate();
        vm.prank(owner);
        uint256 moved3 = h.liquidate();

        assertEq(moved1, 10e18);
        assertEq(moved2, 10e18);
        assertApproxEqAbs(moved3, 5e18, 1);
    }

    // =========================================================================
    // Performance fees
    // =========================================================================

    function test_takePerformanceFees_transfers_redeemable_vault_shares_to_treasury() public {
        MockERC4626Vault redeemable = new MockERC4626Vault(IERC20(address(asset)), "Redeem", "rAST");
        MockERC4626Vault vesting = new MockERC4626Vault(IERC20(address(asset)), "Vesting", "vAST");
        StakVaultHarness h = _deployHarness(redeemable, vesting, 2000, 0, 0); // 20% perf fee

        vm.startPrank(user1);
        asset.approve(address(h), type(uint256).max);
        h.deposit(100e18, user1);
        vm.stopPrank();

        // No profit yet -> 0 fee.
        assertEq(h.takePerformanceFees(), 0);

        // Add profit to redeemable vault -> PPS increases -> fee > 0.
        asset.mint(address(redeemable), 100e18);

        uint256 treasurySharesBefore = redeemable.balanceOf(treasury);
        uint256 feeAssets = h.takePerformanceFees();
        uint256 treasurySharesAfter = redeemable.balanceOf(treasury);

        assertGt(feeAssets, 0);
        assertGt(treasurySharesAfter - treasurySharesBefore, 0);

        // Re-running without additional profit yields 0 (highWaterMark updated).
        assertEq(h.takePerformanceFees(), 0);
    }

    // =========================================================================
    // Underlying vault protection (slippage / preview mismatches)
    // =========================================================================

    function test_deposit_reverts_on_underlying_preview_shortfall() public {
        MockPreviewRedeemShortfallERC4626Vault badPreviewRedeem =
            new MockPreviewRedeemShortfallERC4626Vault(IERC20(address(asset)), "BadPreview", "bpAST", 9_000);
        MockERC4626Vault vesting = new MockERC4626Vault(IERC20(address(asset)), "Vesting", "vAST");

        StakVaultHarness h = _deployHarness(badPreviewRedeem, vesting, 0, 0, 0);

        vm.startPrank(user1);
        asset.approve(address(h), type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(StakVault.StakVault__UnderlyingDepositShortfall.selector, 100e18, 90e18));
        h.deposit(100e18, user1);
        vm.stopPrank();
    }

    function test_deposit_reverts_on_underlying_deposit_preview_mismatch() public {
        MockDepositReturnMismatchERC4626Vault badDepositReturn =
            new MockDepositReturnMismatchERC4626Vault(IERC20(address(asset)), "BadDeposit", "bdAST");
        MockERC4626Vault vesting = new MockERC4626Vault(IERC20(address(asset)), "Vesting", "vAST");

        StakVaultHarness h = _deployHarness(badDepositReturn, vesting, 0, 0, 0);

        vm.startPrank(user1);
        asset.approve(address(h), type(uint256).max);
        vm.expectRevert();
        h.deposit(1e18, user1);
        vm.stopPrank();
    }

    // =========================================================================
    // Harness-only coverage helpers
    // =========================================================================

    function test_harness_exposed_helpers_cover_remaining_branches() public {
        MockERC4626Vault redeemable = new MockERC4626Vault(IERC20(address(asset)), "Redeem", "rAST");
        MockERC4626Vault vesting = new MockERC4626Vault(IERC20(address(asset)), "Vesting", "vAST");
        StakVaultHarness h = _deployHarness(redeemable, vesting, 0, 0, 0);

        // _safeWithdrawFromExternalVault early return.
        assertEq(h.exposed_safeWithdrawFromExternalVault(redeemable, 0), 0);

        // _depositPosition no longer reverts on assets==0 in the current StakVault version.
        // Ensure it records a position and advances the id counter (assets/liability remain unchanged).
        uint256 pid = h.exposed_depositPosition(user1, 0, 1);
        assertEq(pid, 0);
        assertEq(h.nextPositionId(), 1);
        assertEq(h.totalRedemptionLiability(), 0);

        // _computeAssetAmount() was removed; its checks now live inside _redeemPosition().
        // Cover _redeemPosition revert branches.

        // Unauthorized
        h.exposed_setPosition(1, user2, 1e18, 1e18, 1e18);
        vm.prank(user1);
        vm.expectRevert(StakVault.StakVault__Unauthorized.selector);
        h.exposed_redeemPosition(1, 1);

        // NotEnoughLockedShares
        h.exposed_setPosition(2, user1, 1e18, 1, 1);
        vm.prank(user1);
        vm.expectRevert(StakVault.StakVault__NotEnoughLockedShares.selector);
        h.exposed_redeemPosition(2, 2);

        // ZeroValue when position.shares == 0 (and shares==0 bypasses the < check)
        h.exposed_setPosition(3, user1, 1e18, 0, 0);
        vm.prank(user1);
        vm.expectRevert(StakVault.StakVault__ZeroValue.selector);
        h.exposed_redeemPosition(3, 0);

        // ZeroValue when computed assets == 0
        h.exposed_setPosition(4, user1, 0, 1, 1);
        vm.prank(user1);
        vm.expectRevert(StakVault.StakVault__ZeroValue.selector);
        h.exposed_redeemPosition(4, 1);

        // Underlying vault asset helpers are callable.
        assertEq(h.exposed_redeemableVaultAssets(), 0);
        assertEq(h.exposed_vestingVaultAssets(), 0);
        assertEq(h.totalAssets(), 0);
    }

    function test_mint_success_creates_position_and_moves_assets() public {
        MockERC4626Vault redeemable = new MockERC4626Vault(IERC20(address(asset)), "Redeem", "rAST");
        MockERC4626Vault vesting = new MockERC4626Vault(IERC20(address(asset)), "Vesting", "vAST");
        StakVaultHarness h = _deployHarness(redeemable, vesting, 0, 0, 0);

        vm.startPrank(user1);
        asset.approve(address(h), type(uint256).max);
        uint256 assetsIn = h.mint(5e18, user1);
        vm.stopPrank();

        assertEq(assetsIn, 5e18);
        (address posUser, uint256 posAssets, uint256 posShares, uint256 totalShares) = h.positions(0);
        assertEq(posUser, user1);
        assertEq(posAssets, 5e18);
        assertEq(posShares, 5e18);
        assertEq(totalShares, 5e18);
        assertEq(h.totalRedemptionLiability(), 5e18);
        assertEq(asset.balanceOf(address(redeemable)), 5e18);
    }

    function test_liquidate_returns_zero_when_no_vested_assets() public {
        MockERC4626Vault redeemable = new MockERC4626Vault(IERC20(address(asset)), "Redeem", "rAST");
        MockERC4626Vault vesting = new MockERC4626Vault(IERC20(address(asset)), "Vesting", "vAST");
        StakVaultHarness h = _deployHarness(redeemable, vesting, 0, 0, 0);

        vm.prank(owner);
        assertEq(h.liquidate(), 0);
    }
}

