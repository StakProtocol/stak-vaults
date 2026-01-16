// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/token/ERC20/extensions/ERC4626.sol";
import {Ownable} from "@openzeppelin/access/Ownable.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/utils/math/Math.sol";
import {IERC20Metadata} from "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import {ReentrancyGuard} from "@openzeppelin/utils/ReentrancyGuard.sol";

/**
 * @title StakVault (Semi Redeemable 4626)
 * @dev A simple ERC4626 vault implementation with perpetual put option, vesting mechanics and performance fees
 */

contract StakVault is ERC4626, Ownable, ReentrancyGuard {
    using Math for uint256;
    using SafeERC20 for IERC20;

    // ========================================================================
    // Constants ==============================================================
    // ========================================================================

    uint256 private constant BPS = 10_000; // 100%
    uint256 private constant MAX_PERFORMANCE_RATE = 5000; // 50 %
    uint256 private constant WAD = 1e18;

    address private immutable _TREASURY;
    uint256 private immutable _PERFORMANCE_RATE;
    uint256 private immutable _VESTING_START;
    uint256 private immutable _VESTING_END;
    uint256 private immutable _DIVEST_FEE;
    address private immutable _REDEEMABLE_VAULT;
    address private immutable _VESTING_VAULT;

    // ========================================================================
    // Structs ===============================================================
    // ========================================================================

    struct Position {
        address user;
        uint256 assetAmount;
        uint256 shareAmount;
        uint256 vestingAmount;
    }

    // ========================================================================
    // State Variables ========================================================
    // ========================================================================

    bool public redeemsAtNav; // Whether redemptions are enabled
    uint256 public highWaterMark; // High water mark of the vault for performance fees

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
        uint256 divestFee
    );
    event StakVault__RedeemsAtNavEnabled();
    event StakVault__Invested(address indexed user, uint256 positionId, uint256 assets, uint256 shares);
    event StakVault__Divested(address indexed user, uint256 positionId, uint256 assets, uint256 shares, uint256 fee);
    event StakVault__Unlocked(address indexed user, uint256 positionId, uint256 assets, uint256 shares);
    event StakVault__Deposited(address indexed user, uint256 assets, uint256 shares);
    event StakVault__Minted(address indexed user, uint256 assets, uint256 shares);
    event StakVault__Redeemed(address indexed user, uint256 assets, uint256 shares);
    event StakVault__Withdrawn(address indexed user, uint256 assets, uint256 shares);

    /* ========================================================================
    * =============================== Errors ================================
    * =========================================================================
    */

    error StakVault__ZeroValue();
    error StakVault__ZeroAddress();
    error StakVault__ZeroShareAmount();
    error StakVault__Unauthorized();
    error StakVault__NotEnoughLockedShares();
    error StakVault__InvalidPerformanceRate(uint256 performanceRate);
    error StakVault__InvalidVestingSchedule(uint256 currentTime, uint256 vestingStart, uint256 vestingEnd);
    error StakVault__InvalidDecimals(uint8 sharesDecimals, uint8 assetsDecimals);
    error StakVault__InsufficientAssetsInPosition();
    error StakVault__InsufficientAssetsInVault();
    error StakVault__RedeemsAtNavNotEnabled();
    error StakVault__RedeemsAtNavAlreadyEnabled();
    error StakVault__VestingAmountNotRedeemable(address user, uint256 shares, uint256 availableShares);
    error StakVault__NotEnoughDivestibleShares(uint256 positionId, uint256 sharesToBurn, uint256 availableShares);

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
        uint256 divestFee_
    ) ERC20(name_, symbol_) ERC4626(asset_) Ownable(owner_) {
        if (treasury_ == address(0) || redeemableVault_ == address(0) || vestingVault_ == address(0)) {
            revert StakVault__ZeroAddress();
        }

        if (performanceRate_ > MAX_PERFORMANCE_RATE) {
            revert StakVault__InvalidPerformanceRate(performanceRate_);
        }

        if (vestingStart_ < block.timestamp || vestingEnd_ < vestingStart_) {
            revert StakVault__InvalidVestingSchedule(block.timestamp, vestingStart_, vestingEnd_);
        }

        // one
        highWaterMark = 10 ** decimals();

        _TREASURY = treasury_;
        _REDEEMABLE_VAULT = redeemableVault_;
        _VESTING_VAULT = vestingVault_;
        _PERFORMANCE_RATE = performanceRate_;
        _VESTING_START = vestingStart_;
        _VESTING_END = vestingEnd_;
        _DIVEST_FEE = divestFee_;

        emit StakVault__Initialized(
            address(asset_), name_, symbol_, owner_, treasury_, redeemableVault_, vestingVault_, performanceRate_, vestingStart_, vestingEnd_, divestFee_
        );
    }

    // ========================================================================
    // ============================= Owner Functions ==========================
    // ========================================================================

    

    /**
     * @dev Enables redemptions at NAV (Net Asset Value).
     *
     * IMPORTANT: This function should be called by the owner when:
     * 1. The vesting period has ended and users need access to their locked shares
     * 2. The owner wants to switch from fair price to current NAV pricing
     *
     * Once enabled, users can redeem shares at current NAV regardless of vesting status.
     * This is the primary mechanism to unlock shares after the vesting period ends.
     *
     * Can only be called by the owner and cannot be reversed.
     */
    function enableRedeemsAtNav() external onlyOwner {
        redeemsAtNav = true;
        emit StakVault__RedeemsAtNavEnabled();
    }

    // ========================================================================
    // =============================== Getters ================================
    // ========================================================================

    /**
     * @dev Returns the total amount of assets managed by the vault.
     * This can be set externally by the owner and may differ from the contract's balance.
     */
    function totalAssets() public view virtual override returns (uint256) {
        uint256 redeemableVaultShares = IERC4626(_REDEEMABLE_VAULT).balanceOf(address(this));
        uint256 redeemableVaultAssets = IERC4626(_REDEEMABLE_VAULT).previewRedeem(redeemableVaultShares);

        uint256 vestedVaultShares = IERC4626(_VESTING_VAULT).balanceOf(address(this));
        uint256 vestedVaultAssets = IERC4626(_VESTING_VAULT).previewRedeem(vestedVaultShares);

        // TODO: include balance of assets of the current contract?
        // return super.totalAssets() + redeemableAssets + vestedAssets;
        return redeemableVaultAssets + vestedVaultAssets;
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
    function divestibleShares(uint256 positionId) public view returns (uint256) {
        uint256 divestible = vestingRate().mulDiv(positions[positionId].vestingAmount, BPS, Math.Rounding.Floor);
        uint256 takenShares = positions[positionId].vestingAmount - positions[positionId].shareAmount;

        return divestible > takenShares ? (divestible - takenShares) : 0;
    }

    /**
     * @dev Returns the current vesting rate of the vault.
     *
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
    function deposit(uint256 assets, address receiver) public virtual override returns (uint256 shares) {
        if (redeemsAtNav) {
            shares = super.deposit(assets, receiver);
            emit StakVault__Deposited(receiver, assets, shares);
        } else {
            shares = super.deposit(assets, address(this));
            uint256 positionId = _invest(assets, shares);
            emit StakVault__Invested(msg.sender, positionId, assets, shares);
        }

        IERC4626(_REDEEMABLE_VAULT).deposit(assets, address(this));
        // TODO: safety checks for the deposit
    }

    /**
     * @dev Override mint to track deposits per user.
     * @param shares The shares to mint
     * @param receiver The receiver of the assets
     * @return assets The assets
     */
    function mint(uint256 shares, address receiver) public virtual override returns (uint256 assets) {
        if (redeemsAtNav) {
            assets = super.mint(shares, receiver);
            emit StakVault__Minted(receiver, assets, shares);
        } else {
            assets = super.mint(shares, address(this));
            uint256 positionId = _invest(assets, shares);
            emit StakVault__Invested(msg.sender, positionId, assets, shares);
        }

        IERC4626(_REDEEMABLE_VAULT).mint(shares, address(this));
        // TODO: safety checks for the mint
    }

    /**
     * @dev Override redeem to check if redemptions are enabled.
     * @param shares The shares to redeem
     * @param receiver The receiver of the assets
     * @param user The user of the shares
     * @return assets The assets to redeem
     */
    function redeem(uint256 shares, address receiver, address user) public virtual override returns (uint256 assets) {
        if (!redeemsAtNav) {
            revert StakVault__RedeemsAtNavNotEnabled();
        }

        assets = super.previewRedeem(shares);
        IERC4626(_REDEEMABLE_VAULT).withdraw(assets, address(this), address(this));
        // TODO: safety checks for the withdraw

        assets = super.redeem(shares, receiver, user);

        emit StakVault__Redeemed(receiver, assets, shares);
    }

    /**
     * @dev Override withdraw to check if redemptions are enabled.
     * @param assets The assets to withdraw
     * @param receiver The receiver of the shares
     * @param user The user of the assets
     * @return shares The shares to withdraw
     */
    function withdraw(uint256 assets, address receiver, address user) public virtual override returns (uint256 shares) {
        if (!redeemsAtNav) {
            revert StakVault__RedeemsAtNavNotEnabled();
        }

        IERC4626(_REDEEMABLE_VAULT).withdraw(assets, address(this), address(this));
        // TODO: safety checks for the withdraw

        shares = super.withdraw(assets, receiver, user);

        emit StakVault__Withdrawn(receiver, assets, shares);
    }

    /* ========================================================================
    * =========================== External Functions ==========================
    * =========================================================================
    */

    /// @notice Divest some or all of your Perpetual PUT (burn Shares in the position and receive asset at par)
    /// @param positionId Id of the position created at invest
    /// @param sharesToBurn amount of Shares (in Shares units) to divest from that position
    /// @dev This function is used to divest some or all of your Perpetual PUT (burn Tokens in the position and receive asset at par)
    /// @param positionId Id of the position created at invest
    function divest(uint256 positionId, uint256 sharesToBurn) external nonReentrant returns (uint256 assetAmount) {
        if (redeemsAtNav) {
            revert StakVault__RedeemsAtNavAlreadyEnabled();
        }

        uint256 availableShares = divestibleShares(positionId);

        if (sharesToBurn > availableShares) {
            revert StakVault__NotEnoughDivestibleShares(positionId, sharesToBurn, availableShares);
        }

        assetAmount = _divest(positionId, sharesToBurn);

        _burn(address(this), sharesToBurn);

        IERC4626(_VESTING_VAULT).withdraw(assetAmount, address(this), address(this));
        // TODO: safety checks for the withdraw

        // Transfer divest fee to treasury
        uint256 divestFee = assetAmount.mulDiv(_DIVEST_FEE, BPS, Math.Rounding.Ceil);
        IERC20(asset()).safeTransfer(_TREASURY, divestFee);

        // Transfer asset back to user
        uint256 assetsAfterFee = assetAmount - divestFee;
        IERC20(asset()).safeTransfer(msg.sender, assetsAfterFee);

        emit StakVault__Divested(msg.sender, positionId, assetAmount, sharesToBurn, divestFee);
    }

    /// @notice Unlock / Withdraw (unlock) some or all Shares from your PUT. This invalidates the PUT on that portion forever,
    /// and transfers Tokens to the user.
    /// @param positionId Id of the position created at invest
    /// @param sharesToUnlock amount of Shares (in Shares units) to unlock from that position
    /// @dev This function is used to claim some or all of your PUT (unlock Shares from the position and receive asset at par)
    function unlock(uint256 positionId, uint256 sharesToUnlock) external nonReentrant returns (uint256 assetAmount) {
        assetAmount = _divest(positionId, sharesToUnlock);

        // Transfer Shares from contract to user (these Shares lose the PUT)
        // The Shares are already minted and sitting in this contract
        _transfer(address(this), msg.sender, sharesToUnlock);

        // to the treasury for protocol operations
        emit StakVault__Unlocked(msg.sender, positionId, assetAmount, sharesToUnlock);
    }

    /* ========================================================================
    * =========================== Internal Functions ==========================
    * =========================================================================
    */

    /// @notice Internal function to invest assets into a position
    /// @param assetAmount amount of assets (in assets units) to invest
    /// @param shareAmount amount of shares (in shares units) to mint
    /// @return positionId the id of the position created
    function _invest(uint256 assetAmount, uint256 shareAmount) internal returns (uint256 positionId) {
        if (assetAmount == 0) {
            revert StakVault__ZeroValue();
        }

        positionId = nextPositionId++;
        positions[positionId] = Position({
            user: msg.sender, assetAmount: assetAmount, shareAmount: shareAmount, vestingAmount: shareAmount
        });

        _positionsOf[msg.sender].push(positionId);
    }

    /// @notice Internal function to divest shares from a position
    /// @param positionId Id of the position created at invest
    /// @param shareAmount amount of Shares (in Shares units) to divest from that position
    /// @return assetAmount the amount of asset to return
    function _divest(uint256 positionId, uint256 shareAmount) internal returns (uint256 assetAmount) {
        if (shareAmount == 0) {
            revert StakVault__ZeroValue();
        }

        if (positions[positionId].user != msg.sender) {
            revert StakVault__Unauthorized();
        }

        if (positions[positionId].shareAmount < shareAmount) {
            revert StakVault__NotEnoughLockedShares();
        }

        // compute proportional asset return
        assetAmount = _computeAssetAmount(positionId, shareAmount);

        // Update position
        Position storage position = positions[positionId];
        position.shareAmount -= shareAmount;
        position.assetAmount -= assetAmount;

        // Reduce vesting amount if before vesting starts
        if (block.timestamp < _VESTING_START) {
            position.vestingAmount -= shareAmount;
        }
    }

    /// @notice Internal function to compute the asset amount for a divestment
    /// @param positionId Id of the position created at invest
    /// @param shareAmount amount of Shares (in Shares units) to divest from that position
    /// @return assetAmount the amount of asset to return
    function _computeAssetAmount(uint256 positionId, uint256 shareAmount) internal view returns (uint256 assetAmount) {
        Position memory position = positions[positionId];

        if (position.shareAmount == 0) {
            revert StakVault__ZeroShareAmount();
        }

        assetAmount = shareAmount.mulDiv(position.assetAmount, position.shareAmount, Math.Rounding.Floor);

        if (assetAmount == 0) {
            revert StakVault__ZeroValue();
        }

        if (position.assetAmount < assetAmount) {
            revert StakVault__InsufficientAssetsInPosition();
        }

        if (IERC20(asset()).balanceOf(address(this)) < assetAmount) {
            revert StakVault__InsufficientAssetsInVault();
        }
    }

    /* ========================================================================
    * =========================== Performance Fees ============================
    * =========================================================================
    */

    /// @dev Calculate the performance fee
    /// @dev The performance is calculated as the difference between the current price per share and the high water mark
    /// @dev The performance fee is calculated as the product of the performance and the performance rate
    function _calculatePerformanceFee() internal returns (uint256 performanceFee) {
        uint256 pricePerShare = _convertToAssets(10 ** decimals(), Math.Rounding.Ceil);

        if (pricePerShare > highWaterMark) {
            uint256 profitPerShare = pricePerShare - highWaterMark;

            uint256 profit = profitPerShare.mulDiv(totalSupply(), 10 ** decimals(), Math.Rounding.Ceil);
            performanceFee = profit.mulDiv(_PERFORMANCE_RATE, BPS, Math.Rounding.Ceil);

            highWaterMark = pricePerShare;
        }
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
