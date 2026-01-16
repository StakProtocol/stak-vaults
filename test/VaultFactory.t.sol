// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/src/Test.sol";
import {VaultFactory} from "../src/VaultFactory.sol";
import {StakVault} from "../src/StakVault.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockERC4626Vault} from "./mocks/MockERC4626Vault.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";

contract VaultFactoryTest is Test {
    function test_CreateStakVault_EmitsAndInitializes() public {
        MockERC20 asset = new MockERC20("Test Asset", "TST", 18);
        MockERC4626Vault redeemableVault = new MockERC4626Vault(IERC20(address(asset)), "Redeemable Vault", "rTST");
        MockERC4626Vault vestingVault = new MockERC4626Vault(IERC20(address(asset)), "Vesting Vault", "vTST");
        VaultFactory factory = new VaultFactory();

        address owner = address(0xA11CE);
        address treasury = address(0xB0B);

        uint256 performanceRate = 2000;
        uint256 vestingStart = block.timestamp + 1 days;
        uint256 vestingEnd = block.timestamp + 30 days;
        uint256 redemptionFee = 123;
        uint256 maxSlippage = 456;

        address vaultAddr = factory.createStakVault(
            address(asset),
            "Vault Token",
            "VAULT",
            owner,
            treasury,
            address(redeemableVault),
            address(vestingVault),
            performanceRate,
            vestingStart,
            vestingEnd,
            redemptionFee,
            maxSlippage
        );

        assertTrue(vaultAddr != address(0));

        // Basic runtime checks on deployed vault
        StakVault vault = StakVault(vaultAddr);
        assertEq(vault.owner(), owner);
        assertEq(vault.name(), "Vault Token");
        assertEq(vault.symbol(), "VAULT");
        assertEq(address(vault.asset()), address(asset));
    }

    function test_CreateStakVault_RevertsOnInvalidVestingSchedule() public {
        MockERC20 asset = new MockERC20("Test Asset", "TST", 18);
        MockERC4626Vault redeemableVault = new MockERC4626Vault(IERC20(address(asset)), "Redeemable Vault", "rTST");
        MockERC4626Vault vestingVault = new MockERC4626Vault(IERC20(address(asset)), "Vesting Vault", "vTST");
        VaultFactory factory = new VaultFactory();

        // vestingStart in the past should revert in StakVault constructor
        uint256 vestingStart = block.timestamp - 1;
        uint256 vestingEnd = block.timestamp + 1 days;

        vm.expectRevert();
        factory.createStakVault(
            address(asset),
            "Vault Token",
            "VAULT",
            address(0xA11CE),
            address(0xB0B),
            address(redeemableVault),
            address(vestingVault),
            0,
            vestingStart,
            vestingEnd,
            0,
            0
        );
    }
}

