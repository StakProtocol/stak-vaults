// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/token/ERC20/extensions/ERC4626.sol";
import {Ownable} from "@openzeppelin/access/Ownable.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/utils/math/Math.sol";
import {ReentrancyGuard} from "@openzeppelin/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/utils/Pausable.sol";

/**
 * @title StakVault (Semi Redeemable 4626)
 * @dev A simple ERC4626 vault implementation with par PUT option, vesting mechanics and performance fees
 */

contract StakVault is ERC4626, Ownable, ReentrancyGuard, Pausable {
    using Math for uint256;
    using SafeERC20 for IERC20;

    // ========================================================================
    // Constants ==============================================================
    // ========================================================================

    uint256 private constant BPS = 1e4; // 100%
    uint256 private constant MAX_PERFORMANCE_RATE = 5000; // 50 %

    address private immutable _TREASURY;
    uint256 private immutable _PERFORMANCE_RATE;
    uint256 private immutable _VESTING_START;
    uint256 private immutable _VESTING_END;
    uint256 private immutable _REDEMPTION_FEE;
    IERC4626 private immutable _REDEEMABLE_VAULT;
    IERC4626 private immutable _VESTING_VAULT;

    // ========================================================================
    // Structs ===============================================================
    // ========================================================================

    struct Position {
        address user;
        uint256 assets;
        uint256 shares;
        uint256 totalShares;
    }

    enum RedemptionState {
        SemiRedeemable,
        FullyRedeemable
    }

    // ========================================================================
    // State Variables ========================================================
    // ========================================================================

    RedemptionState public redemptionState; // Default: SemiRedeemable (0)
    bool public takesDeposits = true;
    uint256 public maxSlippage;
    uint256 public highWaterMark; // High water mark of the vault for performance fees
    /// @notice Total outstanding redemption liability (in asset units) that must remain covered in the redeemable vault.
    /// @dev This tracks the remaining "par" obligation from pre-NAV positions (updated on deposit/redeem/claim).
    uint256 public totalRedemptionLiability;

    uint256 public nextPositionId; // starts at 0
    mapping(uint256 => Position) public positions; // positionId -> position
    mapping(address => uint256[]) private _positionsOf; // user -> positionsIds

    /* ========================================================================
    * =============================== Events ================================
    * =========================================================================
    */

    event StakVault__Initialized(
        address indexed asset,
        string name,
        string symbol,
        address indexed owner,
        address indexed treasury,
        address redeemableVault,
        address vestingVault,
        uint256 performanceRate,
        uint256 vestingStart,
        uint256 vestingEnd,
        uint256 redemptionFee,
        uint256 maxSlippage
    );

    // management events
    event StakVault__PerformanceFeesTaken(uint256 feeInAssets, uint256 feeInRedeemableVaultShares);
    event StakVault__Vested(uint256 assetsMoved, uint256 redeemableAssetsBefore, uint256 redemptionLiability);
    // owner events
    event StakVault__RedemptionStateUpdated(RedemptionState newState);
    event StakVault__DepositsToggled(bool takesDeposits);
    event StakVault__MaxSlippageUpdated(uint256 maxSlippage);
    event StakVault__Liquidated(uint256 assetsMoved);
    event StakVault__RewardsTaken(address indexed token, uint256 amount);
    // semi-redeemable workflow
    event StakVault__Deposited(address indexed user, address indexed receiver, uint256 assets, uint256 shares, uint256 positionId);
    event StakVault__Minted(address indexed user, address indexed receiver, uint256 assets, uint256 shares, uint256 positionId);
    event StakVault__Redeemed(address indexed user, address indexed receiver, uint256 assets, uint256 shares, uint256 positionId, uint256 fee);
    event StakVault__Claimed(address indexed user, address indexed receiver, uint256 assets, uint256 shares, uint256 positionId);
    // fully-redeemable workflow
    event StakVault__Deposited(address indexed user, address indexed receiver, uint256 assets, uint256 shares);
    event StakVault__Minted(address indexed user, address indexed receiver, uint256 assets, uint256 shares);
    event StakVault__Redeemed(address indexed user, address indexed receiver, uint256 assets, uint256 shares);
    event StakVault__Withdrawn(address indexed user, address indexed receiver, uint256 assets, uint256 shares);

    /* ========================================================================
    * =============================== Errors ================================
    * =========================================================================
    */

    error StakVault__ZeroValue();
    error StakVault__ZeroAddress();
    error StakVault__Unauthorized();
    error StakVault__NotEnoughLockedShares();
    error StakVault__InvalidPerformanceRate();
    error StakVault__InvalidMaxSlippage();
    error StakVault__InvalidVestingSchedule();
    error StakVault__InsufficientAssetsInPosition();
    error StakVault__SemiRedeemableModeOnly();
    error StakVault__FullyRedeemableModeOnly();
    error StakVault__DepositsDisabled();
    error StakVault__NotEnoughRedeemableShares(uint256 positionId, uint256 sharesToBurn, uint256 availableShares);
    error StakVault__DepositPreviewMismatch(uint256 expectedShares, uint256 obtainedShares, uint256 actualShares);
    error StakVault__UnderlyingDepositShortfall(uint256 requestedAssets, uint256 receivedAssets);
    error StakVault__UnderlyingWithdrawShortfall(uint256 requestedAssets, uint256 receivedAssets);
    

    /* ========================================================================
    * =============================== Modifiers ===============================
    * =========================================================================
    */

    modifier onlySemiRedeemableMode() {
        if (redemptionState != RedemptionState.SemiRedeemable) revert StakVault__SemiRedeemableModeOnly();
        _;
    }

    modifier onlyFullyRedeemableMode() {
        if (redemptionState != RedemptionState.FullyRedeemable) revert StakVault__FullyRedeemableModeOnly();
        _;
    }

    modifier nonZeroNumber(uint256 value) {
        if (value == 0) revert StakVault__ZeroValue();
        _;
    }

    modifier nonZeroAddress(address value) {
        if (value == address(0)) revert StakVault__ZeroAddress();
        _;
    }

    // ========================================================================
    // =============================== Constructor ============================
    // ========================================================================

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
        ERC20(name_, symbol_)
        ERC4626(asset_)
        Ownable(owner_) 
        nonZeroAddress(treasury_)
        nonZeroAddress(redeemableVault_)
        nonZeroAddress(vestingVault_)
    {
        if (performanceRate_ > MAX_PERFORMANCE_RATE) {
            revert StakVault__InvalidPerformanceRate();
        }

        if (vestingStart_ < block.timestamp || vestingEnd_ < vestingStart_) {
            revert StakVault__InvalidVestingSchedule();
        }

        if (maxSlippage_ > BPS) {
            revert StakVault__InvalidMaxSlippage();
        }

        highWaterMark = 10 ** decimals();
        maxSlippage = maxSlippage_;

        _TREASURY = treasury_;
        _REDEEMABLE_VAULT = IERC4626(redeemableVault_);
        _VESTING_VAULT = IERC4626(vestingVault_);
        _PERFORMANCE_RATE = performanceRate_;
        _VESTING_START = vestingStart_;
        _VESTING_END = vestingEnd_;
        _REDEMPTION_FEE = redemptionFee_;

        // Allow underlying vaults to pull the asset from this contract for deposits.
        // Using forceApprove to support ERC20s that require allowance reset.
        IERC20(asset()).forceApprove(redeemableVault_, type(uint256).max);
        IERC20(asset()).forceApprove(vestingVault_, type(uint256).max);

        emit StakVault__Initialized(
            address(asset_),
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
        );
    }

    // ========================================================================
    // ============================= Owner Functions ==========================
    // ========================================================================

    /// @notice Move as many assets as possible from the vested vault into the redeemable vault.
    /// @dev Intended to be called before/around enabling NAV redemptions, especially if the vested vault is illiquid.
    /// @dev Can be called multiple times; each call will move up to `_VESTING_VAULT.maxWithdraw(address(this))`.
    /// @return assetsMoved the amount of assets moved back to the redeemable vault
    function liquidate() external onlyOwner returns (uint256 assetsMoved) {
        uint256 assetsRequested = _VESTING_VAULT.maxWithdraw(address(this));
        if (assetsRequested == 0) {
            return 0;
        }

        // Use balance-delta accounting to tolerate fee-on-transfer assets or non-standard vaults.
        assetsMoved = _safeWithdrawFromExternalVault(_VESTING_VAULT, assetsRequested);
        if (assetsMoved > 0) _safeDepositToExternalVault(_REDEEMABLE_VAULT, assetsMoved);

        emit StakVault__Liquidated(assetsMoved);
    }

    /**
     * @dev Enables redemptions at NAV (Net Asset Value).
     *
     * IMPORTANT: This function should be called by the owner when:
     * 1. The vesting period has ended
     * 2. The owner wants to switch from fair price to current NAV pricing
     *
     * Once enabled, users can redeem shares at current NAV regardless of vesting status.
     * This is the primary mechanism to unlock shares after the vesting period ends.
     *
     * Can only be called by the owner and cannot be reversed.
     */
    function enableFullyRedeemableMode() external onlyOwner {
        redemptionState = RedemptionState.FullyRedeemable;
        emit StakVault__RedemptionStateUpdated(RedemptionState.FullyRedeemable);
    }

    function setMaxSlippage(uint256 maxSlippage_) external onlyOwner {
        if (maxSlippage_ > BPS) {
            revert StakVault__InvalidMaxSlippage();
        }
        maxSlippage = maxSlippage_;
        emit StakVault__MaxSlippageUpdated(maxSlippage_);
    }

    /// @notice Toggle whether this vault accepts new deposits/mints.
    function setTakesDeposits(bool takesDeposits_) external onlyOwner {
        takesDeposits = takesDeposits_;
        emit StakVault__DepositsToggled(takesDeposits_);
    }

    function takeRewards(address token) external onlyOwner {
        uint256 amount = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(_TREASURY, amount);
        emit StakVault__RewardsTaken(token, amount);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ========================================================================
    // =========================== Rebalancing  ===============================
    // ========================================================================

    /// @notice Move excess assets from the redeemable vault into the vested vault, while keeping redemption liability covered.
    /// @dev Permissionless. Reverts in fully-redeemable mode to avoid starving redemptions.
    function vest() external whenNotPaused returns (uint256 assetsMoved) {
        if (redemptionState == RedemptionState.FullyRedeemable) revert StakVault__SemiRedeemableModeOnly();

        uint256 redeemableAssets = _redeemableVaultAssets();
        uint256 liability = totalRedemptionLiability;

        if (redeemableAssets <= liability) {
            return 0;
        }

        uint256 requested = redeemableAssets - liability;

        // Pull surplus from redeemable vault into this contract, then deposit into the vesting vault.
        // Use balance-delta accounting to tolerate external vaults that return fewer assets than requested (fees/slippage).
        assetsMoved = _safeWithdrawFromExternalVault(_REDEEMABLE_VAULT, requested);
        if (assetsMoved > 0) {
            _safeDepositToExternalVault(_VESTING_VAULT, assetsMoved);
        }

        emit StakVault__Vested(assetsMoved, redeemableAssets, liability);
    }

    /* ========================================================================
    * =========================== Performance Fees ============================
    * =========================================================================
    */

    /// @dev Calculate the performance fee
    /// @dev The performance is calculated as the difference between the current price per share and the high water mark
    /// @dev The performance fee is calculated as the product of the performance and the performance rate
    /// @notice Take the performance fees from the vault if the price per share is higher than the high water mark
    /// @return performanceFeeInAssets the amount of performance fees taken
    function takePerformanceFees() external returns (uint256 performanceFeeInAssets) {
        performanceFeeInAssets = _calculatePerformanceFee();

        if (performanceFeeInAssets > 0) {
            uint256 performanceFeeInRedeemableVaultShares =_REDEEMABLE_VAULT.previewWithdraw(performanceFeeInAssets);
            IERC20(_REDEEMABLE_VAULT).safeTransfer(_TREASURY, performanceFeeInRedeemableVaultShares);

            emit StakVault__PerformanceFeesTaken(performanceFeeInAssets, performanceFeeInRedeemableVaultShares);
        }
    }

    /// @dev Internal helper used for test harness coverage and to keep fee math in one place.
    ///      Updates `highWaterMark` when a new high is reached.
    function _calculatePerformanceFee() internal returns (uint256 performanceFee) {
        uint256 pricePerShare = _convertToAssets(10 ** decimals(), Math.Rounding.Ceil);

        if (pricePerShare > highWaterMark) {
            uint256 profitPerShare = pricePerShare - highWaterMark;
            uint256 profit = profitPerShare.mulDiv(totalSupply(), 10 ** decimals(), Math.Rounding.Ceil);
            performanceFee = profit.mulDiv(_PERFORMANCE_RATE, BPS, Math.Rounding.Ceil);
            highWaterMark = pricePerShare;
        }
    }

    // ========================================================================
    // =============================== Getters ================================
    // ========================================================================

    /**
     * @dev Returns the total amount of assets managed by the vault.
     * This can be set externally by the owner and may differ from the contract's balance.
     */
    function totalAssets() public view virtual override returns (uint256) {
        return _redeemableVaultAssets() + _vestingVaultAssets();
    }

    /// @notice Get the positions of a user
    /// @param user the user to get the positions of
    /// @return positionsIds the ids of the positions of the user
    function positionsOf(address user) external view returns (uint256[] memory) {
        return _positionsOf[user];
    }

    /**
     * @dev Returns the divestible shares of the position based on the current vesting schedule.
     *
     * IMPORTANT: This function returns 0 after the vesting period ends, effectively
     * locking all shares until NAV redemptions are enabled by the owner.
     *
     * Vesting phases:
     * - Before vesting starts: Returns 100% of user's vesting shares
     * - During vesting: Returns linearly decreasing amount based on time remaining
     * - After vesting ends: Returns 0 (shares are locked until NAV mode is enabled)
     *
     * @param positionId The id of the position to query the divestible shares for
     * @return The divestible shares (0 if vesting period has ended)
     */
    function redeemableShares(uint256 positionId) public view returns (uint256) {
        uint256 redeemable = vestingRate().mulDiv(positions[positionId].totalShares, BPS, Math.Rounding.Floor);
        uint256 claimedShares = positions[positionId].totalShares - positions[positionId].shares;

        return redeemable > claimedShares ? (redeemable - claimedShares) : 0;
    }

    /**
     * @dev Returns the current vesting rate of the vault.
     *
     * Vesting schedule is a “reverse unlock”
     * vestingRate() starts at 100% before start and decreases to 0 by vesting end, making redeemableShares() shrink over time.
     * The vesting rate determines what percentage of vested shares are currently redeemable:
     * - Before vesting starts: 10000 (100% - all shares redeemable)
     * - During vesting: Decreases linearly from 10000 to 0
     * - After vesting ends: 0 (0% - no shares redeemable via vesting)
     *
     * @return The vesting rate as a percentage in BPS (10000 = 100%, 0 = 0%)
     */
    function vestingRate() public view returns (uint256) {
        return _calculateVestingRate();
    }

    // ========================================================================
    // =============================== Overrides ==============================
    // ========================================================================

    /**
     * @dev Override deposit to track deposits per user.
     * @param assets The assets to deposit
     * @param receiver The receiver of the shares
     * @return shares The shares
     */
    function deposit(uint256 assets, address receiver)
        public virtual override
        whenNotPaused
        nonReentrant
        nonZeroNumber(assets)
        nonZeroAddress(receiver)
        returns (uint256 shares)
    {
        if (!takesDeposits) revert StakVault__DepositsDisabled();

        if(redemptionState == RedemptionState.FullyRedeemable) {
            shares = super.deposit(assets, receiver);
            emit StakVault__Deposited(_msgSender(), receiver, assets, shares);
        } else {
            shares = super.deposit(assets, address(this));
            uint256 positionId = _depositPosition(receiver, assets, shares);
            emit StakVault__Deposited(_msgSender(), receiver, assets, shares, positionId);
        }

        _safeDepositToExternalVault(_REDEEMABLE_VAULT, assets);
    }

    /**
     * @dev Override mint to track deposits per user.
     * @param shares The shares to mint
     * @param receiver The receiver of the assets
     * @return assets The assets
     */
    function mint(uint256 shares, address receiver)
        public virtual override
        whenNotPaused
        nonReentrant
        nonZeroNumber(shares)
        nonZeroAddress(receiver)
        returns (uint256 assets)
    {
        if (!takesDeposits) revert StakVault__DepositsDisabled();

        if(redemptionState == RedemptionState.FullyRedeemable) {
            assets = super.mint(shares, receiver);
            emit StakVault__Minted(_msgSender(), receiver, assets, shares);
        } else {
            assets = super.mint(shares, address(this));
            uint256 positionId = _depositPosition(receiver, assets, shares);
            emit StakVault__Minted(_msgSender(), receiver, assets, shares, positionId);
        }

        _safeDepositToExternalVault(_REDEEMABLE_VAULT, assets);
    }

    /**
     * @notice can be called only in Fully Redeemable Mode
     * @dev Override redeem to check if redemptions are enabled.
     * @param shares The shares to redeem
     * @param receiver The receiver of the assets
     * @param user The user of the shares
     * @return assets The assets to redeem
     */
    function redeem(uint256 shares, address receiver, address user)
        public virtual override
        whenNotPaused
        nonReentrant
        onlyFullyRedeemableMode
        nonZeroNumber(shares)
        nonZeroAddress(receiver)
        nonZeroAddress(user)
        returns (uint256 assets)
    {
        assets = super.previewRedeem(shares);
        _safeWithdrawFromExternalVault(_REDEEMABLE_VAULT, assets);
        assets = super.redeem(shares, receiver, user);
        
        emit StakVault__Redeemed(user, receiver, assets, shares);
    }

    /**
     * @dev Override withdraw to check if redemptions are enabled.
     * @notice can be called only in Fully Redeemable Mode
     * @param assets The assets to withdraw
     * @param receiver The receiver of the shares
     * @param user The user of the assets
     * @return shares The shares to withdraw
     */
    function withdraw(uint256 assets, address receiver, address user)
        public virtual override
        nonReentrant
        whenNotPaused
        onlyFullyRedeemableMode
        nonZeroNumber(assets)
        nonZeroAddress(receiver)
        nonZeroAddress(user)
        returns (uint256 shares)
    {
        _safeWithdrawFromExternalVault(_REDEEMABLE_VAULT, assets);
        shares = super.withdraw(assets, receiver, user);

        emit StakVault__Withdrawn(user, receiver, assets, shares);
    }

    /* ========================================================================
    * =========================== External Functions ==========================
    * =========================================================================
    */

    /// @notice can be called only in Semi Redeemable Mode
    /// @notice Redeem some or all of your Par PUT (burn Shares in the position and receive asset at par)
    /// @param positionId Id of the position created at invest
    /// @param shares amount of Shares (in Shares units) to burn from that position
    /// @dev This function is used to redeem some or all of your Par PUT (burn Tokens in the position and receive asset at par)
    /// @param positionId Id of the position created at invest
    function redeem(uint256 positionId, uint256 shares, address receiver)
        external
        nonReentrant
        whenNotPaused
        onlySemiRedeemableMode
        nonZeroNumber(shares)
        nonZeroAddress(receiver)
        returns (uint256 assets)
    {
        uint256 _redeemableShares = redeemableShares(positionId);
        
        if (shares > _redeemableShares) {
            revert StakVault__NotEnoughRedeemableShares(positionId, shares, _redeemableShares);
        }

        uint256 assetsRequested = _redeemPosition(positionId, shares);

        assets = _safeWithdrawFromExternalVault(_REDEEMABLE_VAULT, assetsRequested);
        uint256 redemptionFee = assets.mulDiv(_REDEMPTION_FEE, BPS, Math.Rounding.Floor);
        uint256 assetsAfterFee = assets - redemptionFee;

        _burn(address(this), shares);

        IERC20(asset()).safeTransfer(receiver, assetsAfterFee);

        if (redemptionFee > 0) {
            IERC20(asset()).safeTransfer(_TREASURY, redemptionFee);
        }

        emit StakVault__Redeemed(_msgSender(), receiver, assets, shares, positionId, redemptionFee);
    }

    /// @notice Claim some or all Shares from your PUT. This invalidates the PUT on that portion forever,
    /// and transfers shares to the user.
    /// @param positionId Id of the position created at invest
    /// @param shares amount of Shares (in Shares units) to claim from that position

    /// @dev This function is used to claim some or all of your PUT (claim Shares from the position and receive asset at par)
    function claim(uint256 positionId, uint256 shares, address receiver)
        external
        nonReentrant
        whenNotPaused
        nonZeroNumber(shares)
        nonZeroAddress(receiver)
        returns (uint256 assets)
    {
        assets = _redeemPosition(positionId, shares);
        _transfer(address(this), receiver, shares);

        emit StakVault__Claimed(_msgSender(), receiver, assets, shares, positionId);
    }

    /* ========================================================================
    * =========================== Internal Functions ==========================
    * =========================================================================
    */

    /// @notice Internal function to deposit assets into the redeemable vault
    /// @param assets amount of assets (in assets units) to deposit
    /// @return receivedAssets the amount of assets received from the redeemable vault
    function _safeDepositToExternalVault(IERC4626 vault, uint256 assets) internal returns (uint256 receivedAssets) {
        uint256 receivedShares = vault.previewDeposit(assets);
        receivedAssets = vault.previewRedeem(receivedShares);
        uint256 minAssetsReceived = assets.mulDiv(BPS - maxSlippage, BPS, Math.Rounding.Ceil);

        if (receivedAssets < minAssetsReceived) {
            revert StakVault__UnderlyingDepositShortfall(assets, receivedAssets);
        }

        uint256 sharesBefore = vault.balanceOf(address(this));
        uint256 obtainedShares = vault.deposit(assets, address(this));
        uint256 sharesAfter = vault.balanceOf(address(this));
        uint256 actualShares = sharesAfter - sharesBefore;

        if (obtainedShares != receivedShares || actualShares != receivedShares) {
            revert StakVault__DepositPreviewMismatch(receivedShares, obtainedShares, actualShares);
        }
    }

    /// @dev Withdraw `requestedAssets` from an underlying ERC4626 into this contract, returning the actual amount received.
    /// @notice Reverts when the amount received is less than the minimum amount allowed by the slippage protection (maxSlippage).
    function _safeWithdrawFromExternalVault(
        IERC4626 vault,
        uint256 assetsRequested
    ) internal returns (uint256 assetsReceived) {
        if (assetsRequested == 0) return 0;

        uint256 assetsBefore = IERC20(asset()).balanceOf(address(this));
        vault.withdraw(assetsRequested, address(this), address(this));
        uint256 assetsAfter = IERC20(asset()).balanceOf(address(this));
        assetsReceived = assetsAfter - assetsBefore;

        uint256 minAssetsReceived = assetsRequested.mulDiv(BPS - maxSlippage, BPS, Math.Rounding.Ceil);

        if (assetsReceived < minAssetsReceived) {
            revert StakVault__UnderlyingWithdrawShortfall(assetsRequested, assetsReceived);
        }
    }

    /// @notice Internal function to deposit assets into a position
    /// @param assets amount of assets (in assets units) to deposit
    /// @param shares amount of shares (in shares units) to mint
    /// @return positionId the id of the position created
    function _depositPosition(address receiver, uint256 assets, uint256 shares) internal returns (uint256 positionId) {
        positionId = nextPositionId++;
        positions[positionId] = Position({
            user: receiver,
            assets: assets,
            shares: shares,
            totalShares: shares
        });

        totalRedemptionLiability += assets;
        _positionsOf[receiver].push(positionId);
    }

    /// @notice Internal function to redeem shares from a position
    /// @param positionId Id of the position created at invest
    /// @param shares amount of Shares (in Shares units) to redeem from that position
    /// @return assets the amount of assets to return
    function _redeemPosition(uint256 positionId, uint256 shares) internal returns (uint256 assets) {        
        Position storage position = positions[positionId];
    
        if (position.user != _msgSender()) revert StakVault__Unauthorized();
        if (position.shares < shares) revert StakVault__NotEnoughLockedShares();
        if (position.shares == 0) revert StakVault__ZeroValue();

        assets = shares.mulDiv(position.assets, position.shares, Math.Rounding.Floor);
        
        if (assets == 0) revert StakVault__ZeroValue();
        if (position.assets < assets) revert StakVault__InsufficientAssetsInPosition(); // never happens in theory

        // Update position
        position.shares -= shares;
        position.assets -= assets;

        // Reduce global redemption liability (par obligation).
        totalRedemptionLiability -= assets;

        // Reduce vesting amount if before vesting starts
        if (block.timestamp < _VESTING_START) {
            position.totalShares -= shares;
        }
    }

    // =========================================================================
    // =========================== Underlying Vault Helpers ====================
    // =========================================================================

    function _redeemableVaultAssets() internal view returns (uint256) {
        return _REDEEMABLE_VAULT.previewRedeem(_REDEEMABLE_VAULT.balanceOf(address(this)));
    }

    function _vestingVaultAssets() internal view returns (uint256) {
        return _VESTING_VAULT.previewRedeem(_VESTING_VAULT.balanceOf(address(this)));
    }

    /* ========================================================================
    * =========================== Vesting Schedule ============================
    * =========================================================================
    */

    /**
     * @dev Calculates the current vesting rate based on the vesting schedule.
     *
     * This function implements the core vesting logic:
     * 1. Pre-vesting: Returns 100% (BPS = 10000)
     * 2. During vesting: Returns linearly decreasing rate
     * 3. Post-vesting: Returns 0% - THIS LOCKS ALL SHARES
     *
     * The post-vesting behavior (returning 0) is intentional and prevents
     * redemptions at potentially stale fair prices after the vesting period.
     * Users must wait for NAV redemptions to be enabled to access their funds.
     *
     * @return The vesting rate in basis points (0-10000)
     */
    function _calculateVestingRate() internal view returns (uint256) {
        if (block.timestamp < _VESTING_START) {
            return BPS;
        }

        if (block.timestamp > _VESTING_END) {
            return 0;
        }

        //                vesting end - current time
        // vesting rate = ---------------------------- x BPS
        //                vesting end - vesting start

        return BPS.mulDiv(_VESTING_END - block.timestamp, _VESTING_END - _VESTING_START, Math.Rounding.Floor);
    }
}
