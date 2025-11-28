// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {IERC4626} from "@openzeppelin-contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";

/// @custom:storage-definition erc7201:hopper.storage.vault
/// @param underlying The address of the underlying asset.
/// @param name The name of the vault and by extension the ERC20 token.
/// @param symbol The symbol of the vault and by extension the ERC20 token.
/// @param safe The address of the safe smart contract.
/// @param whitelistManager The address of the whitelist manager.
/// @param valuationManager The address of the valuation manager.
/// @param admin The address of the owner of the vault.
/// @param feeReceiver The address of the fee receiver.
/// @param feeRegistry The address of the fee registry.
/// @param wrappedNativeToken The address of the wrapped native token.
/// @param managementRate The management fee rate.
/// @param performanceRate The performance fee rate.
/// @param rateUpdateCooldown The cooldown period for updating the fee rates.
/// @param enableWhitelist A boolean indicating whether the whitelist is enabled.
struct InitStruct {
    IERC20 underlying;
    string name;
    string symbol;
    address safe;
    address whitelistManager;
    address valuationManager;
    address admin;
    address feeReceiver;
    uint16 managementRate;
    uint16 performanceRate;
    bool enableWhitelist;
    uint256 rateUpdateCooldown;
}

/// @custom:contact team@hopperlabs.xyz
interface ILagoonVault is IERC4626 {
    /////////////////////////////////////////////
    // ## DEPOSIT AND REDEEM FLOW FUNCTIONS ## //
    /////////////////////////////////////////////

    /// @param assets The amount of assets to deposit.
    /// @param controller The address of the controller involved in the deposit request.
    /// @param owner The address of the owner for whom the deposit is requested.
    function requestDeposit(uint256 assets, address controller, address owner) external payable returns (uint256 requestId);

    /// @notice Requests a deposit of assets, subject to whitelist validation.
    /// @param assets The amount of assets to deposit.
    /// @param controller The address of the controller involved in the deposit request.
    /// @param owner The address of the owner for whom the deposit is requested.
    /// @param referral The address who referred the deposit.
    function requestDeposit(uint256 assets, address controller, address owner, address referral) external payable returns (uint256 requestId);

    /// @notice Deposit in a sychronous fashion into the vault.
    /// @param assets The assets to deposit.
    /// @param receiver The receiver of the shares.
    /// @param referral The address who referred the deposit.
    /// @return shares The resulting shares.
    function syncDeposit(uint256 assets, address receiver, address referral) external payable returns (uint256 shares);

    /// @notice Requests the redemption of tokens, subject to whitelist validation.
    /// @param shares The number of tokens to redeem.
    /// @param controller The address of the controller involved in the redemption request.
    /// @param owner The address of the token owner requesting redemption.
    /// @return requestId The id of the redeem request.
    function requestRedeem(uint256 shares, address controller, address owner) external returns (uint256 requestId);

    /// @notice Function to bundle a claim of shares and a request redeem. It can be convenient for UX.
    /// @dev if claimable == 0, it has the same behavior as requestRedeem function.
    /// @dev if claimable > 0, user shares follow this path: vault --> user ; user --> pendingSilo
    function claimSharesAndRequestRedeem(uint256 sharesToRedeem) external returns (uint40 requestId);

    /// @dev Unusable when paused.
    /// @dev First _withdraw path: whenNotPaused via ERC20Pausable._update.
    /// @dev Second _withdraw path: whenNotPaused in ERC7540.
    function withdraw(uint256 assets, address receiver, address controller) external returns (uint256 shares);

    /// @dev Unusable when paused.
    /// @dev First _withdraw path: whenNotPaused via ERC20Pausable._update.
    /// @dev Second _withdraw path: whenNotPaused in ERC7540.
    /// @notice Claim assets from the vault. After a request is made and settled.
    /// @param shares The amount shares to convert into assets.
    /// @param receiver The receiver of the assets.
    /// @param controller The controller, who owns the redeem request.
    /// @return assets The corresponding assets.
    function redeem(uint256 shares, address receiver, address controller) external returns (uint256 assets);

    /// @notice Claims all available shares for a list of controller addresses.
    /// @dev Iterates over each controller address, checks for claimable deposits, and deposits them on their behalf.
    /// @param controllers The list of controller addresses for which to claim shares.
    function claimSharesOnBehalf(address[] memory controllers) external;

    ///////////////////////////////////////////////////////
    // ## VALUATION UPDATING AND SETTLEMENT FUNCTIONS ## //
    ///////////////////////////////////////////////////////

    function updateTotalAssetsLifespan(uint128 lifespan) external;

    /// @notice Function to propose a new valuation for the vault.
    /// @notice It can only be called by the ValueManager.
    /// @param _newTotalAssets The new total assets of the vault.
    function updateNewTotalAssets(uint256 _newTotalAssets) external;

    /// @notice Settles deposit requests, integrates user funds into the vault strategy, and enables share claims.
    /// If possible, it also settles redeem requests.
    /// @dev Unusable when paused, protected by whenNotPaused in _updateTotalAssets.
    function settleDeposit(uint256 _newTotalAssets) external;

    /// @notice Settles redeem requests, only callable by the safe.
    /// @dev Unusable when paused, protected by whenNotPaused in _updateTotalAssets.
    /// @dev After updating totalAssets, it takes fees, updates highWaterMark and finally settles redeem requests.
    function settleRedeem(uint256 _newTotalAssets) external;

    /////////////////////////////
    // ## CLOSING FUNCTIONS ## //
    /////////////////////////////

    /// @notice Initiates the closing of the vault. Can only be called by the owner.
    /// @dev we make sure that initiate closing will make an epoch changement if the variable newTotalAssets is "defined"
    /// @dev (!= type(uint256).max). This guarantee that no userShares will be locked in a pending state.
    function initiateClosing() external;

    /// @notice Closes the vault, only redemption and withdrawal are allowed after this. Can only be called by the safe.
    /// @dev Users can still requestDeposit but it can't be settled.
    function close(uint256 _newTotalAssets) external;

    /////////////////////////////////
    // ## PAUSABILITY FUNCTIONS ## //
    /////////////////////////////////

    /// @notice Halts core operations of the vault. Can only be called by the owner.
    /// @notice Core operations include deposit, redeem, withdraw, any type of request, settles deposit and redeem and newTotalAssets update.
    function pause() external;

    /// @notice Resumes core operations of the vault. Can only be called by the owner.
    function unpause() external;

    function expireTotalAssets() external;

    // MAX FUNCTIONS OVERRIDE //

    /// @notice Returns the maximum redeemable shares for a controller.
    /// @param controller The controller.
    /// @return shares The maximum redeemable shares.
    /// @dev When the vault is closed, users may claim there assets (erc7540.redeem style) or redeem there assets in a sync manner.
    /// this is why when they have nothing to claim and the vault is closed, we return their shares balance
    function maxRedeem(address controller) external view returns (uint256);

    /// @notice Returns the amount of assets a controller will get if he redeem.
    /// @param controller The controller.
    /// @return The maximum amount of assets to get.
    /// @dev This is the same philosophy as maxRedeem, except that we take care to convertToAssets the value before returning it
    function maxWithdraw(address controller) external view returns (uint256);

    /// @notice Returns the amount of assets a controller will get if he redeem.
    /// @param controller address to check
    /// @dev If the contract is paused no deposit/claims are possible.
    function maxDeposit(address controller) external view returns (uint256);

    /// @notice Returns the amount of sharres a controller will get if he calls Deposit.
    /// @param controller The controller.
    /// @dev If the contract is paused no deposit/claims are possible.
    /// @dev We read the claimableDepositRequest of the controller then convert it to shares using the convertToShares of the related epochId
    /// @return The maximum amount of shares to get.
    function maxMint(address controller) external view returns (uint256);

    function isTotalAssetsValid() external view returns (bool);

    function safe() external view returns (address);

    function version() external pure returns (string memory);

    ///////////////////
    // ## ERC7540 ## //
    ///////////////////

    function isOperator(address controller, address operator) external view returns (bool);
    function setOperator(address operator, bool approved) external returns (bool success);
    function deposit(uint256 assets, address receiver, address controller) external returns (uint256);
    function mint(uint256 shares, address receiver, address controller) external returns (uint256);
    function cancelRequestDeposit() external;
    function convertToShares(uint256 assets, uint256 requestId) external view returns (uint256);
    function convertToAssets(uint256 shares, uint256 requestId) external view returns (uint256);
    function pendingRedeemRequest(uint256 requestId, address controller) external view returns (uint256 shares);
    function pendingDepositRequest(uint256 requestId, address controller) external view returns (uint256 assets);
    function claimableDepositRequest(uint256 requestId, address controller) external view returns (uint256);
    function claimableRedeemRequest(uint256 requestId, address controller) external view returns (uint256);

    ///////////////////
    // ## ERC7575 ## //
    ///////////////////

    function share() external view returns (address);

    ///////////////////
    // ## OTHER ## //
    ///////////////////

    function isWhitelisted(address account) external view returns (bool);
    function paused() external view returns (bool);
}
