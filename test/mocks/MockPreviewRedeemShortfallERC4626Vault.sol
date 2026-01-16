// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/token/ERC20/extensions/ERC4626.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/utils/math/Math.sol";

/// @notice ERC4626 test vault that under-reports assets on `previewRedeem`, simulating a vault with a
///         predictable haircut / deposit fee that the preview functions reflect.
/// @dev Used to trigger `StakVault__UnderlyingDepositShortfall` in `_safeDepositToExternalVault`.
contract MockPreviewRedeemShortfallERC4626Vault is ERC4626 {
    using Math for uint256;

    uint256 public immutable previewRedeemBps;

    constructor(IERC20 asset_, string memory name_, string memory symbol_, uint256 previewRedeemBps_)
        ERC20(name_, symbol_)
        ERC4626(asset_)
    {
        previewRedeemBps = previewRedeemBps_;
    }

    function previewRedeem(uint256 shares) public view override returns (uint256) {
        uint256 base = super.previewRedeem(shares);
        return base.mulDiv(previewRedeemBps, 10_000, Math.Rounding.Floor);
    }
}

