// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/token/ERC20/extensions/ERC4626.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/utils/math/Math.sol";

/// @notice ERC4626 test vault that is artificially "illiquid" by limiting maxWithdraw per call.
contract MockIlliquidERC4626Vault is ERC4626 {
    using Math for uint256;

    uint256 public immutable maxWithdrawPerCall;

    constructor(IERC20 asset_, string memory name_, string memory symbol_, uint256 maxWithdrawPerCall_)
        ERC20(name_, symbol_)
        ERC4626(asset_)
    {
        maxWithdrawPerCall = maxWithdrawPerCall_;
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        uint256 base = super.maxWithdraw(owner);
        return base.min(maxWithdrawPerCall);
    }
}

