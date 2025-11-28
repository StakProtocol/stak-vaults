// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin-contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin-contracts/token/ERC20/extensions/ERC4626.sol";
import {Ownable} from "@openzeppelin-contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin-contracts/utils/math/Math.sol";
import {IERC20Metadata} from "@openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title SemiRedeemableVault
 * @dev A simple ERC4626 vault implementation with ownership control
 * The total assets can be set externally by the owner, allowing the owner
 * to withdraw assets while maintaining the vault's accounting.
 */
contract SemiRedeemableVault is ERC4626, Ownable {
    using Math for uint256;
    using SafeERC20 for IERC20;

    uint256 private _totalAssets;
    bool private _redeemsAtNav;
    address private _treasury;
    uint16 private _performanceRate;
    uint256 private _highWaterMark;

    uint256 private constant BPS = 10_000; // 100%
    uint16 public constant MAX_PERFORMANCE_RATE = 5000; // 50 %

    struct Ledger {
        uint256 assets;
        uint256 shares;
    }

    mapping(address => Ledger) private _ledger;

    /* ========================================================================
    * =============================== Events ================================
    * =========================================================================
    */

    event AssetsTaken(uint256 assets);
    event TotalAssetsUpdated(uint256 newTotalAssets);
    event RedeemsAtNavEnabled();

    /* ========================================================================
    * =============================== Errors ================================
    * =========================================================================
    */

    error InvalidPerformanceRate(uint16 performanceRate);
    error InvalidTreasury(address treasury);
    error InvalidOwner(address owner);
    error InvalidDecimals(uint8 sharesDecimals, uint8 assetsDecimals);

    // ========================================================================
    // =============================== Constructor ============================
    // ========================================================================

    constructor(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        address owner_,
        address treasury_,
        uint16 performanceRate_
    ) ERC20(name_, symbol_) ERC4626(asset_) Ownable(owner_) {
        
        if (performanceRate_ > MAX_PERFORMANCE_RATE) {
            revert InvalidPerformanceRate(performanceRate_);
        }

        if (treasury_ == address(0)) {
            revert InvalidTreasury(treasury_);
        }

        if (owner_ == address(0)) {
            revert InvalidOwner(owner_);
        }

        uint8 assetsDecimals = IERC20Metadata(address(asset_)).decimals();
        if (assetsDecimals != decimals()) {
            revert InvalidDecimals(decimals(), assetsDecimals);
        }

        _highWaterMark = 10 ** decimals();
        _treasury = treasury_;
        _performanceRate = performanceRate_;
    }

    // ========================================================================
    // ============================= Owner Functions ==========================
    // ========================================================================

    function takeAssets(uint256 assets) external onlyOwner {
        IERC20(asset()).safeTransfer(owner(), assets);

        emit AssetsTaken(assets);
    }

    /**
     * @dev Sets the total assets managed by the vault.
     * Can only be called by the owner.
     * @param newTotalAssets The new total assets value
     */
    function updateTotalAssets(uint256 newTotalAssets) external onlyOwner {
        _totalAssets = newTotalAssets;
        _applyPerformanceFee();

        emit TotalAssetsUpdated(newTotalAssets);
    }

    /**
     * @dev Enables redemptions at NAV.
     * Can only be called by the owner.
     */
    function enableRedeemsAtNav() external onlyOwner {
        _redeemsAtNav = true;

        emit RedeemsAtNavEnabled();
    }
    
    // ========================================================================
    // =============================== Getters ================================
    // ========================================================================

    /**
     * @dev Returns the total amount of assets managed by the vault.
     * This can be set externally by the owner and may differ from the contract's balance.
     */
    function totalAssets() public view virtual override returns (uint256) {
        return _totalAssets;
    }

    /**
     * @dev Returns the utilization rate of the vault.
     * @return The utilization rate as a percentage in BPS (10000 = 100%)
     */
    function utilizationRate() public view returns (uint256) {
        uint256 investedAssets = _totalAssets - IERC20(asset()).balanceOf(address(this));
        return BPS.mulDiv(investedAssets, _totalAssets, Math.Rounding.Floor);
    }

    /**
     * @dev Returns whether redemptions are at NAV.
     */
    function redeemsAtNav() public view returns (bool) {
        return _redeemsAtNav;
    }

    /**
     * @dev Returns the ledger of the vault.
     * @param user The address to query the ledger for
     * @return assets The assets in the ledger
     * @return shares The shares in the ledger
     */
    function getLedger(address user) public view returns (uint256 assets, uint256 shares) {
        return (_ledger[user].assets, _ledger[user].shares);
    }
    
    /**
     * @dev Converts assets to shares.
     * @param assets The assets to convert
     * @param owner The owner of the assets
     * @return The shares
     */
    function convertToShares(uint256 assets, address owner) public view returns (uint256) {
        return _convertToShares(assets, owner, Math.Rounding.Floor);
    }

    /**
     * @dev Converts shares to assets.
     * @param shares The shares to convert
     * @param owner The owner of the shares
     * @return The assets
     */
    function convertToAssets(uint256 shares, address owner) public view returns (uint256) {
        return _convertToAssets(shares, owner, Math.Rounding.Floor);
    }

    // ========================================================================
    // =============================== Overrides ==============================
    // ========================================================================

    /**
     * @dev Override deposit to track deposits per user.
     * @param assets The assets to deposit
     * @param receiver The receiver of the shares
     * @return The shares
     */
    function deposit(uint256 assets, address receiver) public virtual override returns (uint256) {
        // Call parent deposit function
        uint256 shares = super.deposit(assets, receiver);
        
        // Update the ledger
        _ledger[receiver].assets += assets;
        _ledger[receiver].shares += shares;

        return shares;
    }

    /**
     * @dev Override mint to track deposits per user.
     * @param shares The shares to mint
     * @param receiver The receiver of the assets
     * @return The assets
     */
    function mint(uint256 shares, address receiver) public virtual override returns (uint256) {
        // Call parent mint function
        uint256 assets = super.mint(shares, receiver);
        
        // Update the ledger
        _ledger[receiver].assets += assets;
        _ledger[receiver].shares += shares;
        
        return assets;
    }

    /**
     * @dev Override redeem to check if redemptions are enabled.
     * @param shares The shares to redeem
     * @param receiver The receiver of the assets
     * @param owner The owner of the shares
     * @return The assets
     */
    function redeem(uint256 shares, address receiver, address owner) public virtual override returns (uint256) {
        uint256 maxShares = maxRedeem(owner);
        if (shares > maxShares) {
            revert ERC4626ExceededMaxRedeem(owner, shares, maxShares);
        }

        uint256 assets = _previewRedeem(shares, owner);

        // Update the ledger
        _ledger[owner].assets -= assets;
        _ledger[owner].shares -= shares;
        
        _withdraw(_msgSender(), receiver, owner, assets, shares);

        return assets;
    }

    /**
     * @dev Override withdraw to update the ledger.
     * @param assets The assets to withdraw
     * @param receiver The receiver of the shares
     * @param owner The owner of the assets
     * @return The shares
     */
    function withdraw(uint256 assets, address receiver, address owner) public virtual override returns (uint256) {
        uint256 maxAssets = maxWithdraw(owner);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxWithdraw(owner, assets, maxAssets);
        }

        uint256 shares = _previewWithdraw(assets, owner);

        // Update the ledger
        _ledger[owner].assets -= assets;
        _ledger[owner].shares -= shares;
        
        _withdraw(_msgSender(), receiver, owner, assets, shares);

        return shares;
    }

    /**
     * @dev Preview the shares to withdraw per user
     * @param assets The assets to withdraw
     * @return The shares
     */
    function previewWithdraw(uint256 assets) public view override returns (uint256) {
        return _previewWithdraw(assets, _msgSender());
    }

    /**
     * @dev Preview the assets to redeem per user
     * @param shares The shares to redeem
     * @return The assets
     */
    function previewRedeem(uint256 shares) public view override returns (uint256) {
        return _previewRedeem(shares, _msgSender());
    }

    // ========================================================================
    // =============================== Non Overrides ==========================
    // ========================================================================

    /**
     * @dev Preview the shares to withdraw per user
     * If redemptions are at NAV, return the shares (same as 4626)
     * Otherwise, return the maximum between the shares and the shares of the owner (to prevent underflow)
     * @param assets The assets to withdraw
     * @param owner The owner of the assets
     * @return The shares
     */
    function _previewWithdraw(uint256 assets, address owner) private view returns (uint256) {
        uint256 shares = _convertToShares(assets, Math.Rounding.Ceil);
        if(_redeemsAtNav) return shares;
        return Math.max(shares, _convertToShares(assets, owner, Math.Rounding.Ceil));
    }

    /**
     * @dev Preview the assets to redeem per user
     * If redemptions are at NAV, return the assets (same as 4626)
     * Otherwise, return the minimum between the assets and the assets of the owner (to prevent underflow)
     * @param shares The shares to redeem
     * @param owner The owner of the shares
     * @return The assets
     */
    function _previewRedeem(uint256 shares, address owner) private view returns (uint256) {
        uint256 assets = _convertToAssets(shares, owner, Math.Rounding.Floor);
        if(_redeemsAtNav) return assets;
        return Math.min(assets, _convertToAssets(shares, owner, Math.Rounding.Floor));
    }

    /**
     * @dev Converts assets to shares per user using the ledger as a fair exchange rate
     * @param assets The assets to convert
     * @param owner The owner of the assets
     * @param rounding The rounding direction
     * @return The shares
     */ 
    // TODO VERIFY: shares = 0 || assets = 0
    function _convertToShares(uint256 assets, address owner, Math.Rounding rounding) private view returns (uint256) {
        return assets.mulDiv(_ledger[owner].shares, _ledger[owner].assets, rounding);
    }

    /**
     * @dev Converts shares to assets per user using the ledger as a fair exchange rate
     * @param shares The shares to convert
     * @param owner The owner of the shares
     * @param rounding The rounding direction
     * @return The assets
     */
     // TODO VERIFY: shares = 0 || assets = 0
    function _convertToAssets(uint256 shares, address owner, Math.Rounding rounding) private view returns (uint256) {
        return shares.mulDiv(_ledger[owner].assets, _ledger[owner].shares, rounding);
    }

    /* ========================================================================
    * =========================== Performance Fees ============================
    * =========================================================================
    */

     /// @dev Calculate the performance fee
    /// @dev The performance is calculated as the difference between the current price per share and the high water mark
    /// @dev The performance fee is calculated as the product of the performance and the performance rate
    function _applyPerformanceFee() internal {
        uint256 pricePerShare = _convertToAssets(10 ** decimals(), Math.Rounding.Ceil);
        
        if (pricePerShare > _highWaterMark) {
            uint256 profitPerShare = pricePerShare - _highWaterMark;
            
            uint256 profit = profitPerShare.mulDiv(totalSupply(), 10 ** decimals(), Math.Rounding.Ceil);
            uint256 performanceFee = profit.mulDiv(_performanceRate, BPS, Math.Rounding.Ceil);

            _highWaterMark = pricePerShare;

            if (performanceFee > 0) {
                IERC20(asset()).safeTransfer(_treasury, performanceFee);
            }
        }
    }
}
