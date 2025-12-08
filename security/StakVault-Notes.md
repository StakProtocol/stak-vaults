# StakVault Security Assessment & Implementation Notes

## Executive Summary

StakVault is a semi-redeemable ERC4626 vault implementation with perpetual put options, vesting mechanics, and performance fees. The vault allows users to deposit assets, receive shares, and provides two redemption modes: fair price (1:1 ledger-based) and NAV (Net Asset Value) based redemptions.

## Contract Architecture

### Core Components
- **ERC4626 Vault**: Extends OpenZeppelin's ERC4626 standard
- **Position Tracking**: Each deposit creates a position tracking user, assetAmount, shareAmount, and vestingAmount
- **Dual Redemption Modes**: 
  - Fair Price Mode: Users redeem at 1:1 based on their ledger
  - NAV Mode: Users redeem at current Net Asset Value (enabled by owner)
- **Performance Fees**: Calculated based on high water mark when NAV increases
- **Vesting Schedule**: Linear vesting that decreases from 100% to 0% over the vesting period

### Key Functions
- `deposit()` / `mint()`: Create investment positions (before NAV) or standard deposits (after NAV)
- `redeem()` / `withdraw()`: Redeem shares for assets (only after NAV enabled)
- `divest()`: Burn shares and receive original asset at par (perpetual PUT)
- `unlock()`: Release shares to user, invalidating PUT and freeing backing
- `updateInvestedAssets()`: Owner sets total assets managed by vault (triggers performance fee calculation)
- `enableRedeemsAtNav()`: Owner enables NAV-based redemptions

## Security Analysis

### ⚠️ Critical Vulnerabilities

#### 1. CRITICAL: Owner Can Manipulate Performance Fees
**Location**: `_calculatePerformanceFee()` line 441, `updateInvestedAssets()` line 144

**Description**: 
The owner can set `investedAssets` to any arbitrary value. The performance fee calculation uses this value to compute the price per share via the parent's `_convertToAssets()` function. By setting an artificially high `investedAssets`, the owner can make it appear as if the vault has made huge profits, triggering excessive performance fees.

**Impact**: 
- **Theft of user funds** through inflated performance fees
- Owner can extract fees based on fake profits
- High severity - direct financial loss to users

**PoC Scenario**:
- User deposits 1,000 tokens
- Owner sets `investedAssets = 10,000 tokens` (10x actual)
- Performance fee calculated on fake 10x profit
- 1,800 tokens extracted as fee from 1,000 token deposit

**Recommendation**:
- Add validation to ensure `investedAssets` is within reasonable bounds
- Consider using time-weighted average or require external oracle for `investedAssets`
- Add maximum fee cap per transaction
- Consider multi-sig or timelock for `updateInvestedAssets()`
- Require external audit/verification for `investedAssets` updates

#### 2. CRITICAL: Owner Can Drain Assets and Hide Losses
**Location**: `takeAssets()` line 133, `updateInvestedAssets()` line 144

**Description**:
The owner can call `takeAssets()` to withdraw funds from the vault, then call `updateInvestedAssets()` to set a value that doesn't reflect the actual loss. When NAV redemptions are enabled, users will receive less than they should because the contract doesn't have enough assets to cover the reported `totalAssets`.

**Impact**:
- **Theft of user funds** - owner can drain vault
- **Hidden losses** - users think vault is healthy when it's not
- High severity - direct financial loss and deception

**PoC Scenario**:
- Vault has 3,000 tokens, users have 3,000 shares
- Owner drains 1,500 tokens via `takeAssets()`
- Owner reports `investedAssets = 3,000` (hiding the drain)
- Users redeeming at NAV will get less than expected

**Recommendation**:
- Require `totalAssets <= actualBalance + investedAssets` or add validation
- Add events/logging for all asset movements
- Consider requiring external audit/verification for `investedAssets` updates
- Implement maximum withdrawal limits per period
- Add checks that vault has sufficient balance for reported `investedAssets`

#### 3. HIGH: PreviewWithdraw Manipulation Leading to Excessive Share Burning
**Location**: `previewWithdraw()` (inherited from ERC4626)

**Description**:
The `previewWithdraw()` function uses `Math.max()` between the standard ERC4626 conversion (which uses `totalAssets()`) and the user's ledger conversion. If the owner sets `investedAssets` to 0 or a very small value, the standard conversion returns an extremely large number. The `Math.max()` then forces users to burn way more shares than they should when withdrawing.

**Impact**:
- **DoS attack** - users cannot withdraw without losing excessive shares
- **Theft of shares** - users lose more value than intended
- Medium-High severity - can prevent legitimate withdrawals

**PoC Scenario**:
- Normal withdrawal: 500 assets = 500 shares
- After manipulation: 500 assets = 250,000,000,000,000,000,000 shares
- Demonstrates massive share inflation

**Recommendation**:
- Add bounds checking on `totalAssets` (minimum value)
- Consider using only ledger-based conversion when not in NAV mode
- Add sanity checks on conversion results
- Cap the maximum shares that can be required

### ⚠️ Medium Severity Issues

#### 4. MEDIUM: Ledger Inconsistency After NAV Switch
**Location**: `deposit()` line 244, `mint()` line 259

**Description**:
When NAV redemptions are enabled, new deposits don't update the user's ledger. However, users who deposited before the NAV switch can still redeem using their ledger at fair price (1:1). This creates an inconsistency where:
- Early depositors redeem at fair price (their original deposit rate)
- Late depositors redeem at NAV (current market rate)
- This can lead to unfairness and potential arbitrage opportunities

**Impact**:
- **Unfair redemption rates** between users
- **Potential arbitrage** opportunities
- Medium severity - fairness and economic issues

**Recommendation**:
- When NAV is enabled, migrate all ledgers to NAV-based pricing
- Or prevent ledger-based redemptions after NAV switch
- Add clear documentation about redemption behavior

#### 5. MEDIUM: Approval Mechanism for Delegated Redemptions
**Location**: `redeem()` line 275, `withdraw()` line 290

**Description**:
When user1 approves user2 to redeem shares, user2 should be able to redeem the shares on behalf of user1. The contract extends ERC4626 which inherits from ERC20, providing standard `approve()` and `transferFrom()` functionality. The `redeem()` and `withdraw()` functions accept a `user` parameter to support delegated redemptions, but the proper handling of allowances through the parent `_withdraw()` function needs to be verified.

**Impact**:
- **Access control failure** - delegated redemptions may not work as expected
- **Functionality break** - users cannot delegate redemption permissions
- Medium severity - affects expected ERC4626/ERC20 behavior

**Recommendation**:
- Verify that the parent ERC4626 `_withdraw()` function properly checks allowances when `_msgSender()` differs from `user`
- Ensure that `redeem()` and `withdraw()` correctly handle the approval mechanism
- Add comprehensive tests for delegated redemption scenarios
- Document the approval and delegation behavior clearly

### ⚠️ Low Severity Issues

#### 6. LOW: Vesting Update Logic in Redeem/Withdraw
**Location**: `_divest()` line 398

**Observation**:
The vesting ledger is only updated when `block.timestamp < _VESTING_START`. After vesting starts, the vesting amount is not decremented when shares are divested/unlocked.

**Analysis**:
This appears intentional - once vesting starts, the `divestibleShares()` calculation uses `vestingRate()` to determine how much of the vested shares are redeemable, so the vesting amount itself doesn't need to be decremented. However, this means the vesting amount will remain constant after vesting starts, which might be confusing.

**Recommendation**:
- Consider whether the vesting amount should be decremented proportionally during the vesting period
- Or document that the current behavior (only decrementing before vesting starts) is the intended design

#### 7. LOW: No Validation on `updateInvestedAssets()` Value
**Location**: `updateInvestedAssets()` line 144

**Observation**:
The function accepts any `uint256` value for `newInvestedAssets` without validation. This could allow setting `investedAssets` to a value that doesn't match reality.

**Analysis**:
This is likely intentional - the owner is trusted to set the correct value. However, this is the root cause of the critical vulnerabilities above.

**Recommendation**:
- Add bounds checking or events to help with off-chain monitoring
- Consider requiring external verification
- Implement maximum change limits per update

## Code Quality Observations

### Positive Aspects

1. **Good separation of concerns**: Fair price mode vs NAV mode is clearly separated
2. **Proper use of ERC4626**: Correctly extends and overrides parent functions
3. **Vesting logic**: Well-documented and implemented
4. **Error handling**: Good use of custom errors for clarity
5. **Reentrancy protection**: All external functions use `nonReentrant` modifier

### Areas for Improvement

1. **Access Control**: Consider implementing timelock or multi-sig for critical owner functions
2. **Validation**: Add bounds checking and validation for all owner-controlled parameters
3. **Transparency**: Add more events and logging for all state changes
4. **Documentation**: Clearly document redemption behavior, especially around NAV switching
5. **Testing**: Add more edge case tests, especially around zero values and boundary conditions

## Vesting Mechanism

### Implementation Details

The vesting mechanism works as follows:

1. **Pre-Vesting** (`block.timestamp < _VESTING_START`):
   - `vestingRate()` returns 10000 (100% in BPS)
   - All shares are divestible

2. **During Vesting** (`_VESTING_START <= block.timestamp <= _VESTING_END`):
   - `vestingRate()` decreases linearly from 10000 to 0
   - Formula: `BPS * (vestingEnd - block.timestamp) / (vestingEnd - vestingStart)`
   - Divestible shares = `vestingRate() * vestingAmount / BPS`

3. **Post-Vesting** (`block.timestamp > _VESTING_END`):
   - `vestingRate()` returns 0
   - No shares are divestible via vesting mechanism
   - Users must wait for NAV redemptions to be enabled

### Vesting Amount Updates

- When divesting before vesting starts: `vestingAmount` is reduced
- When divesting during/after vesting: `vestingAmount` is NOT reduced (uses rate calculation)
- This ensures vesting calculations remain accurate

## Performance Fee Mechanism

### Calculation

The performance fee is calculated when `updateInvestedAssets()` is called:

1. Calculate current price per share: `_convertToAssets(10 ** decimals(), Math.Rounding.Ceil)`
2. If price > high water mark:
   - Calculate profit per share: `pricePerShare - highWaterMark`
   - Calculate total profit: `profitPerShare * totalSupply / 10 ** decimals`
   - Calculate fee: `profit * performanceRate / BPS`
   - Transfer fee to treasury
   - Update high water mark to current price

### Vulnerabilities

The performance fee calculation is vulnerable to manipulation because:
- Owner controls `investedAssets` which directly affects `totalAssets()`
- `totalAssets()` is used in price per share calculation
- No validation on `investedAssets` value
- No bounds checking on fee amount

## Position Management

### Position Lifecycle

1. **Creation**: Via `deposit()` or `mint()` (before NAV enabled)
   - Creates new position with unique ID
   - Mints shares to contract address
   - Records backing balance
   - Sets vestingAmount = shareAmount

2. **Divestment**: Via `divest()`
   - Burns shares from contract
   - Returns proportional asset amount
   - Reduces position shareAmount and assetAmount
   - Reduces backing balance
   - Updates vestingAmount if before vesting starts

3. **Unlock**: Via `unlock()`
   - Transfers shares from contract to user
   - Returns proportional asset amount
   - Reduces position shareAmount and assetAmount
   - Reduces backing balance
   - Updates vestingAmount if before vesting starts
   - Released backing becomes available for owner

4. **NAV Redemptions**: Via `redeem()` or `withdraw()` (after NAV enabled)
   - Uses standard ERC4626 conversion
   - No position tracking
   - Shares are burned from user's balance

## Test Coverage Status

**Current Status**:
- Lines: 98.45%
- Statements: 98.63%
- Branches: 92.00%
- Functions: 100.00%
- All 74 tests are passing (before recent changes)

**Recommended Test Additions**:
- Owner manipulation attack scenarios
- NAV switch edge cases
- Delegated redemption tests
- Performance fee manipulation tests
- Zero value and boundary condition tests

## Recommendations for Production

### Before Mainnet Deployment

1. **CRITICAL PRIORITY**: 
   - Add validation to `updateInvestedAssets()` to prevent manipulation
   - Add bounds checking on `investedAssets` values
   - Implement maximum fee cap per transaction
   - Consider multi-sig or timelock for owner functions
   - Add checks that vault balance supports reported `investedAssets`

2. **HIGH PRIORITY**:
   - Add sanity checks to `previewWithdraw()` to prevent manipulation
   - Consider using only ledger-based conversion when not in NAV mode
   - Add maximum withdrawal limits per period

3. **MEDIUM PRIORITY**:
   - Resolve ledger inconsistency after NAV switch
   - Verify and test delegated redemption mechanism
   - Add comprehensive event logging

4. **LOW PRIORITY**:
   - Document vesting update behavior
   - Add more edge case tests
   - Consider gas optimizations

## Summary

### Security Status: ⚠️ REQUIRES FIXES BEFORE PRODUCTION

**Critical vulnerabilities exist that allow owner to:**
- Manipulate performance fees
- Drain assets and hide losses
- Manipulate withdrawal calculations

**All critical vulnerabilities must be fixed before production deployment.**

**Recommendation**: Implement all CRITICAL and HIGH priority recommendations before mainnet deployment.

