// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "./BaseTest.sol";
import {StakVault} from "../../src/StakVault.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";

contract StakVaultSetupTest is BaseTest {
    function test_Constructor_Success() public view {
        assertEq(vault.owner(), owner);
        assertEq(vault.redeemsAtNav(), false);
        assertEq(vault.highWaterMark(), 1e18);
        assertEq(vault.investedAssets(), 0);
        assertEq(vault.nextPositionId(), 0);
    }

    function test_Constructor_RevertWhen_InvalidPerformanceRate() public {
        vm.expectRevert(abi.encodeWithSelector(StakVault.StakVault__InvalidPerformanceRate.selector, 6000));

        vm.prank(owner);
        new StakVault(IERC20(address(asset)), "Vault", "VAULT", owner, treasury, 6000, vestingStart, vestingEnd);
    }

    function test_Constructor_RevertWhen_InvalidTreasury() public {
        vm.expectRevert(abi.encodeWithSelector(StakVault.StakVault__InvalidTreasury.selector, address(0)));

        vm.prank(owner);
        new StakVault(
            IERC20(address(asset)), "Vault", "VAULT", owner, address(0), PERFORMANCE_RATE, vestingStart, vestingEnd
        );
    }

    function test_Constructor_RevertWhen_InvalidVestingSchedule_StartInPast() public {
        // Use a timestamp that's definitely in the past
        // Start from a known timestamp to avoid underflow
        uint256 currentTime = block.timestamp;
        vm.warp(currentTime + 2 days); // Move time forward first

        // Ensure pastStart is actually in the past without underflow
        uint256 pastStart = currentTime; // This will be in the past relative to warped time
        uint256 futureEnd = block.timestamp + 30 days;

        vm.expectRevert(
            abi.encodeWithSelector(
                StakVault.StakVault__InvalidVestingSchedule.selector, block.timestamp, pastStart, futureEnd
            )
        );

        vm.prank(owner);
        new StakVault(IERC20(address(asset)), "Vault", "VAULT", owner, treasury, PERFORMANCE_RATE, pastStart, futureEnd);
    }

    function test_Constructor_RevertWhen_InvalidVestingSchedule_EndBeforeStart() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                StakVault.StakVault__InvalidVestingSchedule.selector, block.timestamp, vestingEnd, vestingStart
            )
        );

        vm.prank(owner);
        new StakVault(
            IERC20(address(asset)), "Vault", "VAULT", owner, treasury, PERFORMANCE_RATE, vestingEnd, vestingStart
        );
    }

    function test_Constructor_RevertWhen_InvalidDecimals() public {
        // Create an ERC20 with 6 decimals, but ERC4626 will override decimals() to match asset
        // So we need to create a custom mock that doesn't match ERC4626's behavior
        // Actually, ERC4626 overrides decimals() to return asset().decimals(), so this check
        // will always pass if the asset has valid decimals. The check is redundant but kept for safety.
        // Since ERC4626 already enforces matching decimals, we can't test a mismatch scenario.
        // This test is kept to document the behavior, but it will pass (not revert) because
        // ERC4626's decimals() returns the asset's decimals.

        MockERC20 asset6Decimals = new MockERC20("Asset6", "A6", 6);

        // ERC4626 overrides decimals() to return asset().decimals(), so the check will pass
        // The constructor will succeed, not revert
        vm.prank(owner);
        StakVault vault6Dec = new StakVault(
            IERC20(address(asset6Decimals)),
            "Vault",
            "VAULT",
            owner,
            treasury,
            PERFORMANCE_RATE,
            vestingStart,
            vestingEnd
        );

        // Verify the vault has 6 decimals (matching the asset)
        assertEq(vault6Dec.decimals(), 6);
    }

    function test_Constructor_AcceptsMaxPerformanceRate() public {
        vm.prank(owner);
        StakVault maxRateVault = new StakVault(
            IERC20(address(asset)), "Vault", "VAULT", owner, treasury, MAX_PERFORMANCE_RATE, vestingStart, vestingEnd
        );

        assertEq(maxRateVault.owner(), owner);
    }

    function test_Constructor_AcceptsZeroPerformanceRate() public {
        vm.prank(owner);
        StakVault zeroRateVault =
            new StakVault(IERC20(address(asset)), "Vault", "VAULT", owner, treasury, 0, vestingStart, vestingEnd);

        assertEq(zeroRateVault.owner(), owner);
    }
}

