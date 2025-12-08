# Semi-Redeemable Vaults and Tokens

A suite of smart contracts for investment and vault management with dual redemption modes and perpetual put options.

## Contracts

### StakVault
ERC-4626 vault with dual redemption modes and performance fees.

**Features:**
- **Dual Redemption Modes**: NAV-based (standard ERC4626) or fair price (1:1 ledger-based)
- **Per-User Position Tracking**: Tracks individual deposits for fair redemption pricing
- **Performance Fees**: Calculated based on high water mark
- **Vesting Mechanics**: Linear vesting schedule for share unlocking

### FlyingICO
Investment contract with perpetual put options and Chainlink price feeds.

**Features:**
- **Multi-Asset Support**: Accepts ETH and ERC20 tokens with Chainlink price feeds
- **Token Minting**: Mints tokens at a fixed rate per USD invested
- **Perpetual PUT Options**: Users can divest (burn tokens, get assets back) or unlock (release tokens, free backing)
- **Vesting Schedule**: Linear vesting for token unlocking

## Installation

```bash
forge soldeer install
forge build
```

## Deployment

Deploy the Factory contract:

```bash
forge script script/DeployFactoryFlying.s.sol --rpc-url <RPC_URL> --private-key <PRIVATE_KEY> --broadcast
forge script script/DeployFactoryVault.s.sol --rpc-url <RPC_URL> --private-key <PRIVATE_KEY> --broadcast
```

Use the Factory to deploy StakVault or FlyingICO instances.

## Testing

```bash
forge test
```

## License

MIT
