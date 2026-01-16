// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {StakVault} from "../../src/StakVault.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/interfaces/IERC4626.sol";

/// @notice Test-only harness exposing internal functions/branches for coverage.
contract StakVaultHarness is StakVault {
    constructor(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        address owner_,
        address treasury_,
        address redeemableVault_,
        address vestingVault_,
        uint256 performanceRate_,
        uint256 vestingStart_,
        uint256 vestingEnd_,
        uint256 redemptionFee_,
        uint256 maxSlippage_
    )
        StakVault(
            asset_,
            name_,
            symbol_,
            owner_,
            treasury_,
            redeemableVault_,
            vestingVault_,
            performanceRate_,
            vestingStart_,
            vestingEnd_,
            redemptionFee_,
            maxSlippage_
        )
    {}

    function exposed_calculatePerformanceFee() external returns (uint256) {
        return _calculatePerformanceFee();
    }

    function exposed_depositPosition(address receiver, uint256 assets, uint256 shares) external returns (uint256 positionId) {
        return _depositPosition(receiver, assets, shares);
    }

    function exposed_safeDepositToExternalVault(IERC4626 vault, uint256 assets) external returns (uint256) {
        return _safeDepositToExternalVault(vault, assets);
    }

    function exposed_safeWithdrawFromExternalVault(IERC4626 vault, uint256 assetsRequested) external returns (uint256) {
        return _safeWithdrawFromExternalVault(vault, assetsRequested);
    }

    function exposed_redeemPosition(uint256 positionId, uint256 shares) external returns (uint256) {
        return _redeemPosition(positionId, shares);
    }

    function exposed_calculateVestingRate() external view returns (uint256) {
        return _calculateVestingRate();
    }

    function exposed_redeemableVaultAssets() external view returns (uint256) {
        return _redeemableVaultAssets();
    }

    function exposed_vestingVaultAssets() external view returns (uint256) {
        return _vestingVaultAssets();
    }

    function exposed_setPosition(
        uint256 positionId,
        address user,
        uint256 assetAmount,
        uint256 shareAmount,
        uint256 totalShares
    ) external {
        positions[positionId] = Position({
            user: user,
            assets: assetAmount,
            shares: shareAmount,
            totalShares: totalShares
        });
    }
}

