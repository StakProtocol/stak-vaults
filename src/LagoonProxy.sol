// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {ILagoonVault} from "./interfaces/ILagoonVault.sol";
import {Ownable} from "@openzeppelin-contracts/access/Ownable.sol";

contract LagoonProxy is Ownable {
  
  using SafeERC20 for IERC20;

  struct Deposit {
    uint256 assets;
    uint256 shares;
  }

  ILagoonVault lagoonVault;
  mapping(address => Deposit) public deposits;

  constructor(address owner, address lagoonVault_) Ownable(owner) {
    lagoonVault = ILagoonVault(lagoonVault_);
    IERC20(lagoonVault.asset()).approve(address(lagoonVault), type(uint256).max);
  }

  // function requestDeposit(uint256 assets, address controller, address owner) external payable returns (uint256 requestId);
  function requestDeposit(uint256 assets) external returns (uint256) {    
    IERC20(lagoonVault.asset()).safeTransferFrom(msg.sender, address(this), assets);
    return lagoonVault.requestDeposit(assets, msg.sender, address(this));
  }

  // function deposit(uint256 assets, address receiver, address controller) external returns (uint256);
  function deposit(uint256 assets) external returns (uint256) {
    uint256 shares = lagoonVault.deposit(assets, msg.sender, msg.sender);

    deposits[msg.sender].assets += assets;
    deposits[msg.sender].shares += shares;

    return shares;
  }

  // function requestRedeem(uint256 shares, address controller, address owner) external returns (uint256 requestId);
  function requestRedeem(uint256 shares) external returns (uint256) {
    return lagoonVault.requestRedeem(shares, msg.sender, address(this));
  }

  // function redeem(uint256 shares, address receiver, address controller) external returns (uint256 assets);
  function redeem(uint256 shares, address receiver, address controller) external {
    deposits[controller].shares -= shares;
    lagoonVault.redeem(shares, receiver, controller);
  }

}
