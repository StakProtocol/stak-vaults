# StakVault Security Review (2026-01)

## Scope

- **In scope**: `src/StakVault.sol` (primary), `src/VaultFactory.sol` (constructor wiring only), `src/utils/Chainlink.sol` (standalone library review).
- **Out of scope**: OpenZeppelin dependencies (assumed audited), deployment / operational security, off-chain systems.

## Executive summary

`StakVault` is an ERC4626 share token that **wraps two external ERC4626 vaults**:

- **`_REDEEMABLE_VAULT`**: should remain liquid enough to cover “par PUT” liabilities (`totalRedemptionLiability`).
- **`_VESTING_VAULT`**: holds surplus moved out of the redeemable vault via `vest()`.

User-facing flows:

- **Semi-redeemable mode (default)**:
  - Deposits create on-chain `Position`s.
  - Users can **redeem at par** via `redeem(positionId, shares, receiver)` (pays assets to `receiver` minus fee), capped by `redeemableShares(positionId)`.
  - Users can **claim shares** via `claim(positionId, shares, receiver)` (transfers shares to `receiver`, permanently giving up the “par” claim on that portion).
- **Fully-redeemable mode**: owner calls `enableFullyRedeemableMode()`. Users can use standard ERC4626 `withdraw/redeem` **if they hold shares**.

The largest risks are:

- **External vault trust/compatibility**: strict assumptions about ERC4626 preview correctness and fee-less behavior.
- **Slippage vs accounting**: allowing `maxSlippage > 0` can create drift between `totalRedemptionLiability` (ledger) and actual deliverable assets.

## Threat model & assumptions

- **Owner trust**: owner can pause, toggle deposits, change `maxSlippage`, sweep `takeRewards`, and flip to fully redeemable.
- **External vault trust**: `_REDEEMABLE_VAULT` and `_VESTING_VAULT` are assumed:
  - non-malicious,
  - reasonably ERC4626-compliant,
  - not fee-charging in ways that violate preview assumptions,
  - solvent / not manipulable via share price games.

## Walkthrough (top-to-bottom) + notes

### Core state

- **`totalRedemptionLiability`** represents total outstanding “par” obligations in asset units.
- **Invariant intent**: keep enough value in `_REDEEMABLE_VAULT` so `redeem(positionId, shares, receiver)` can be honored, while `vest()` moves excess to `_VESTING_VAULT`.

### Owner / management functions

- **`liquidate()`**: pulls as much as possible from vesting vault into redeemable vault.
- **`setMaxSlippage()`**: updates slippage tolerance (BPS).
- **`takeRewards(token)`**: transfers full balance of `token` held by this contract to treasury.
- **`pause/unpause`**: pauses `whenNotPaused` paths.
- **`takePerformanceFees()` is **not** paused (no `whenNotPaused`).

### Performance fees

- Fee is computed from **total vault NAV** (`totalAssets()`), but extracted as **shares of the redeemable vault**.
- Implementation detail: it transfers redeemable-vault shares via `IERC20(_REDEEMABLE_VAULT).safeTransfer(...)`.
- If profits are mostly in vesting vault, fee collection may revert due to insufficient redeemable-vault shares.

## Findings

### Critical

- **C1 — Slippage breaks liability accounting (drift between “par owed” and deliverable assets)**
  - **Where**: `_redeemPosition()` reduces `totalRedemptionLiability` by the *ledger* amount; `redeem(positionId, shares, receiver)` pays based on the *actual received* amount from `_safeWithdrawFromExternalVault`.
  - **Impact**: with `maxSlippage > 0` and/or fee/rounding in external vaults, liabilities can be reduced by more than what is actually delivered, allowing `vest()` to move too much out of `_REDEEMABLE_VAULT` over time.
  - **Mitigation**: enforce strictly compatible external vaults and consider requiring `maxSlippage = 0`, or redesign accounting to reconcile liability using actual delivery.

### High

- **H1 — External vault compatibility is extremely strict**
  - `_safeDepositToExternalVault` requires `deposit()` results and balance deltas to match `previewDeposit()` *exactly*.
  - Many ERC4626 vaults (fees, rounding, virtual shares) will fail this.

- **H2 — Performance fee extraction source mismatch**
  - Profit measured on `totalAssets()` (both vaults), but fees are extracted only from redeemable-vault shares → fee can become uncollectable / revert.


