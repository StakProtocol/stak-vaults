// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/token/ERC20/extensions/ERC4626.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";

/// @notice ERC4626 test vault that returns an incorrect share amount from `deposit()`.
/// @dev Used to trigger `StakVault__DepositPreviewMismatch`.
contract MockDepositReturnMismatchERC4626Vault is ERC4626 {
    constructor(IERC20 asset_, string memory name_, string memory symbol_) ERC20(name_, symbol_) ERC4626(asset_) {}

    function deposit(uint256 assets, address receiver) public override returns (uint256) {
        uint256 shares = super.deposit(assets, receiver);
        // Lie about the amount of shares minted.
        return shares + 1;
    }
}

