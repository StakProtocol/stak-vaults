// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/token/ERC20/extensions/ERC4626.sol";
import {Ownable} from "@openzeppelin/access/Ownable.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
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
    uint256 public backingBalance; // Backing assets held as backing for open PUTs
    uint256 public investedAssets; // Total assets managed by the vault

    uint256 public nextPositionId;
    mapping(uint256 => Position) public positions; // positionId -> position
    mapping(address => uint256[]) public positionsOf; // user -> positionsIds

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
        uint256 performanceRate,
        uint256 vestingStart,
        uint256 vestingEnd
    );
    event StakVault__AssetsTaken(uint256 assets);
    event StakVault__InvestedAssetsUpdated(uint256 newInvestedAssets, uint256 performanceFee);
    event StakVault__RedeemsAtNavEnabled();
    event StakVault__Invested(address indexed user, uint256 positionId, uint256 assetAmount, uint256 shareAmount);
    event StakVault__Divested(
        address indexed user, uint256 positionId, uint256 sharesBurned, uint256 assetReturnedAmount
    );
    event StakVault__Unlocked(
        address indexed user, uint256 positionId, uint256 sharesUnlocked, uint256 assetReleasedAmount
    );

    /* ========================================================================
    * =============================== Errors ================================
    * =========================================================================
    */

    error StakVault__ZeroValue();
    error StakVault__ZeroShareAmount();
    error StakVault__Unauthorized();
    error StakVault__NotEnoughLockedShares();
    error StakVault__InvalidPerformanceRate(uint256 performanceRate);
    error StakVault__InvalidTreasury(address treasury);
    error StakVault__InvalidVestingSchedule(uint256 currentTime, uint256 vestingStart, uint256 vestingEnd);
    error StakVault__InvalidDecimals(uint8 sharesDecimals, uint8 assetsDecimals);
    error StakVault__InsufficientAssetAmount();
    error StakVault__InsufficientBacking();
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
        uint256 performanceRate_,
        uint256 vestingStart_,
        uint256 vestingEnd_
    ) ERC20(name_, symbol_) ERC4626(asset_) Ownable(owner_) {
        if (performanceRate_ > MAX_PERFORMANCE_RATE) {
            revert StakVault__InvalidPerformanceRate(performanceRate_);
        }

        if (treasury_ == address(0)) {
            revert StakVault__InvalidTreasury(treasury_);
        }

        uint8 assetsDecimals = IERC20Metadata(address(asset_)).decimals();
        if (assetsDecimals != decimals()) {
            revert StakVault__InvalidDecimals(decimals(), assetsDecimals);
        }

        if (vestingStart_ < block.timestamp || vestingEnd_ < vestingStart_) {
            revert StakVault__InvalidVestingSchedule(block.timestamp, vestingStart_, vestingEnd_);
        }

        highWaterMark = 10 ** decimals();

        _TREASURY = treasury_;
        _PERFORMANCE_RATE = performanceRate_;
        _VESTING_START = vestingStart_;
        _VESTING_END = vestingEnd_;

        emit StakVault__Initialized(
            address(asset_), name_, symbol_, owner_, treasury_, performanceRate_, vestingStart_, vestingEnd_
        );
    }

    // ========================================================================
    // ============================= Owner Functions ==========================
    // ========================================================================

    function takeAssets(uint256 assets) external onlyOwner {
        investedAssets += assets;
        IERC20(asset()).safeTransfer(owner(), assets);
        emit StakVault__AssetsTaken(assets);
    }

    /**
     * @dev Sets the total assets managed by the vault.
     * Can only be called by the owner.
     * @param newInvestedAssets The new invested assets value
     */
    function updateInvestedAssets(uint256 newInvestedAssets) external onlyOwner {
        investedAssets = newInvestedAssets;

        uint256 performanceFee = _calculatePerformanceFee();

        if (performanceFee > 0) {
            IERC20(asset()).safeTransfer(_TREASURY, performanceFee);
        }

        emit StakVault__InvestedAssetsUpdated(newInvestedAssets, performanceFee);
    }

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
        return super.totalAssets() + investedAssets;
    }

    /**
     * @dev Returns the utilization rate of the vault.
     * @return The utilization rate as a percentage in BPS (10000 = 100%)
     */
    function utilizationRate() public view returns (uint256) {
        uint256 _totalAssets = totalAssets();
        if (_totalAssets == 0) return 0;
        return BPS.mulDiv(investedAssets, _totalAssets, Math.Rounding.Floor);
    }

    /// @notice Get the positions of a user
    /// @param user the user to get the positions of
    /// @return positionsIds the ids of the positions of the user
    function positionsOfUser(address user) external view returns (uint256[] memory) {
        return positionsOf[user];
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
        return vestingRate().mulDiv(positions[positionId].vestingAmount, BPS, Math.Rounding.Floor);
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
        } else {
            shares = super.deposit(assets, address(this));
            _invest(assets, shares);
        }
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
        } else {
            assets = super.mint(shares, address(this));
            _invest(assets, shares);
        }
    }

    /**
     * @dev Override redeem to check if redemptions are enabled.
     * @param shares The shares to redeem
     * @param receiver The receiver of the assets
     * @param user The user of the shares
     * @return The assets
     */
    function redeem(uint256 shares, address receiver, address user) public virtual override returns (uint256) {
        if (!redeemsAtNav) {
            revert StakVault__RedeemsAtNavNotEnabled();
        }

        return super.redeem(shares, receiver, user);
    }

    /**
     * @dev Override withdraw to check if redemptions are enabled.
     * @param assets The assets to withdraw
     * @param receiver The receiver of the shares
     * @param user The user of the assets
     * @return shares The shares to withdraw
     */
    function withdraw(uint256 assets, address receiver, address user) public virtual override returns (uint256) {
        if (!redeemsAtNav) {
            revert StakVault__RedeemsAtNavNotEnabled();
        }

        return super.withdraw(assets, receiver, user);
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

        // Transfer asset back to user
        IERC20(asset()).safeTransfer(msg.sender, assetAmount);

        emit StakVault__Divested(msg.sender, positionId, sharesToBurn, assetAmount);
    }

    /// @notice Unlock / Withdraw (unlock) some or all Shares from your Perpetual PUT. This invalidates the PUT on that portion forever,
    /// and transfers Tokens to the user. The backing previously reserved becomes available for protocol operations.
    /// @param positionId Id of the position created at invest
    /// @param sharesToUnlock amount of Shares (in Shares units) to unlock from that position
    /// @dev This function is used to claim some or all of your Perpetual PUT (unlock Shares from the position and receive asset at par)
    function unlock(uint256 positionId, uint256 sharesToUnlock) external nonReentrant returns (uint256 assetAmount) {
        assetAmount = _divest(positionId, sharesToUnlock);

        // Transfer Shares from contract to user (these Shares lose the Perpetual PUT)
        // The Shares are already minted and sitting in this contract
        _transfer(address(this), msg.sender, sharesToUnlock);

        // Released backing becomes available for protocol operations:
        // Backing has been reduced above, so the released assets are now available
        // to the treasury for protocol operations
        emit StakVault__Unlocked(msg.sender, positionId, sharesToUnlock, assetAmount);
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

        backingBalance += assetAmount;

        positionId = nextPositionId++;
        positions[positionId] = Position({
            user: msg.sender, assetAmount: assetAmount, shareAmount: shareAmount, vestingAmount: shareAmount
        });

        positionsOf[msg.sender].push(positionId);

        emit StakVault__Invested(msg.sender, positionId, assetAmount, shareAmount);
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

        // if(!redeemsAtNav) // TODO: rethink this check
        if (block.timestamp < _VESTING_START) {
            position.vestingAmount -= shareAmount;
        }

        // reduce backing
        backingBalance -= assetAmount; // TODO: backing necessary?
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
            revert StakVault__InsufficientAssetAmount();
        }

        if (backingBalance < assetAmount) {
            // this happens if the owner takes more assets than the backing balance
            revert StakVault__InsufficientBacking();
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
