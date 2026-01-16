// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/token/ERC20/extensions/ERC4626.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/utils/math/Math.sol";

/// @notice Non-standard ERC4626 test vault that charges a fee on withdrawals by transferring fewer assets than requested.
/// @dev This simulates a fee-on-transfer asset or a non-compliant external position.
contract MockFeeChargingERC4626Vault is ERC4626 {
    using SafeERC20 for IERC20;
    using Math for uint256;

    uint256 public immutable feeBps;
    address public immutable feeRecipient;

    constructor(IERC20 asset_, string memory name_, string memory symbol_, uint256 feeBps_, address feeRecipient_)
        ERC20(name_, symbol_)
        ERC4626(asset_)
    {
        feeBps = feeBps_;
        feeRecipient = feeRecipient_;
    }

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares) internal override {
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        _burn(owner, shares);

        uint256 fee = assets.mulDiv(feeBps, 10_000, Math.Rounding.Ceil);
        uint256 toReceiver = assets - fee;

        IERC20(asset()).safeTransfer(receiver, toReceiver);
        if (fee > 0) {
            IERC20(asset()).safeTransfer(feeRecipient, fee);
        }

        emit Withdraw(caller, receiver, owner, assets, shares);
    }
}

