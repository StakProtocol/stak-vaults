# 🏦 SemiRedeemableVault

> **A flexible ERC-4626 vault implementation with dual redemption modes and per-user deposit tracking**

[![Solidity](https://img.shields.io/badge/Solidity-0.8.24-blue.svg)](https://soliditylang.org/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Foundry](https://img.shields.io/badge/Built%20with-Foundry-ff6b6b.svg)](https://book.getfoundry.sh/)

## 📖 Overview

**SemiRedeemableVault** is an innovative ERC-4626 compliant vault that provides two distinct redemption mechanisms, giving vault operators flexibility in managing user redemptions while maintaining fair accounting for all participants.

### ✨ Key Features

- **🔀 Dual Redemption Modes**
  - **NAV Mode**: Standard ERC-4626 redemption at current Net Asset Value
  - **Deposit Price Mode**: Redemption at original deposit price using per-user ledger

- **📊 Per-User Ledger System**
  - Tracks individual user deposits (assets & shares)
  - Enables fair redemption pricing based on personal deposit history
  - Prevents cross-subsidization between users

- **🎛️ Owner Controls**
  - Set total assets externally (allows for off-chain investment strategies)
  - Toggle between redemption modes dynamically
  - Maintains vault accounting independently of contract balance

- **🛡️ Security First**
  - Built on OpenZeppelin's battle-tested contracts
  - SafeERC20 for secure token transfers
  - Comprehensive access controls

## 🎯 Use Cases

### Investment Vaults
Perfect for vaults that invest assets off-chain or in other protocols, where the owner needs to:
- Update total assets based on investment performance
- Switch between redemption modes based on market conditions
- Provide fair redemption terms to early vs. late depositors

### Managed Funds
Ideal for funds where:
- The manager needs flexibility in redemption terms
- Users should be able to redeem at their entry price when NAV is disabled
- Transparent accounting is required

### Structured Products
Suitable for products that:
- Have different redemption windows
- Need to protect early investors from late-comer redemptions
- Require owner-controlled asset accounting

## 🏗️ Architecture

### Core Components

```
SemiRedeemableVault
├── ERC4626 (OpenZeppelin)
│   ├── Standard deposit/mint/withdraw/redeem
│   └── Share calculation logic
├── Ownable (OpenZeppelin)
│   └── Owner-only functions
└── Custom Logic
    ├── Ledger System (per-user tracking)
    ├── Dual Redemption Modes
    └── External Asset Management
```

### Ledger System

Each user has a `Ledger` that tracks:
- **Assets**: Total assets deposited by the user
- **Shares**: Total shares received by the user

This enables fair redemption calculations when not redeeming at NAV.

## 📚 How It Works

### Deposit Flow

1. User calls `deposit()` or `mint()`
2. Standard ERC-4626 deposit logic executes
3. User's ledger is updated with assets and shares
4. Shares are minted to the user

### Redemption Flow

#### When `redeemsAtNav = true` (NAV Mode)
- Standard ERC-4626 redemption
- Assets returned = `shares * (totalAssets / totalSupply)`
- Ledger is updated to reflect redemption

#### When `redeemsAtNav = false` (Deposit Price Mode)
- Redemption uses user's personal ledger
- Assets returned = `shares * (userAssets / userShares)`
- Ensures users redeem at their original deposit price
- Ledger is updated to reflect redemption

### Owner Functions

- **`setTotalAssets(uint256)`**: Update the vault's total assets (for off-chain investments)
- **`setRedeemsAtNav(bool)`**: Toggle between redemption modes

## 🚀 Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Solidity ^0.8.24

### Installation

```bash
# Clone the repository
git clone <repository-url>
cd semi-redeemable-vault

# Install dependencies
forge install

# Build the project
forge build
```

### Usage

#### Deploy the Vault

```solidity
// Deploy with an ERC20 asset, name, symbol, and owner
SemiRedeemableVault vault = new SemiRedeemableVault(
    assetToken,      // IERC20 asset address
    "Vault Token",   // Name
    "VAULT",         // Symbol
    owner            // Owner address
);
```

#### Deposit Assets

```solidity
// Deposit 1000 assets
uint256 shares = vault.deposit(1000e18, msg.sender);

// Or mint specific shares
uint256 assets = vault.mint(500e18, msg.sender);
```

#### Redeem Shares

```solidity
// Redeem shares (mode depends on redeemsAtNav setting)
uint256 assets = vault.redeem(shares, receiver, owner);
```

#### Owner Operations

```solidity
// Set total assets (e.g., after off-chain investment)
vault.setTotalAssets(newTotalAssets);

// Toggle redemption mode
vault.setRedeemsAtNav(true);  // Enable NAV redemptions
vault.setRedeemsAtNav(false); // Enable deposit price redemptions
```

## 🧪 Testing

```bash
# Run all tests
forge test

# Run with verbosity
forge test -vvv

# Run specific test
forge test --match-test testDeposit

# Gas snapshots
forge snapshot
```

## 📖 API Reference

### View Functions

| Function | Description |
|----------|-------------|
| `totalAssets()` | Returns total assets managed by vault |
| `redeemsAtNav()` | Returns current redemption mode |
| `getLedger(address)` | Returns user's ledger (assets, shares) |
| `convertToShares(uint256, address)` | Convert assets to shares for user |
| `convertToAssets(uint256, address)` | Convert shares to assets for user |
| `previewWithdraw(uint256)` | Preview shares for withdrawal |
| `previewRedeem(uint256)` | Preview assets for redemption |

### State-Changing Functions

| Function | Description | Access |
|----------|-------------|--------|
| `deposit(uint256, address)` | Deposit assets | Public |
| `mint(uint256, address)` | Mint shares | Public |
| `withdraw(uint256, address, address)` | Withdraw assets | Public |
| `redeem(uint256, address, address)` | Redeem shares | Public |
| `setTotalAssets(uint256)` | Set total assets | Owner |
| `setRedeemsAtNav(bool)` | Toggle redemption mode | Owner |

## 🔒 Security Considerations

- **Owner Controls**: The owner has significant control over the vault. Ensure owner is a multisig or trusted entity.
- **Asset Accounting**: `totalAssets` can be set externally. Ensure proper off-chain accounting.
- **Redemption Mode Switching**: Users should be aware when redemption modes change.
- **Ledger Updates**: Ledger is updated on every deposit/redemption to maintain accuracy.

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📞 Support

For questions or issues, please open an issue on GitHub.

---

**Built with ❤️ using Foundry and OpenZeppelin**
