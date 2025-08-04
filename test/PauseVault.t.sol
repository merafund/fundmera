// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 fundmera.com

// https://github.com/merafund
pragma solidity ^0.8.29;

import {Test, console} from "forge-std/Test.sol";
import {MainVault} from "../src/MainVault.sol";
import {IMainVault} from "../src/interfaces/IMainVault.sol";
import {PauserList} from "../src/PauserList.sol";
import {IPauserList} from "../src/interfaces/IPauserList.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock ERC20 token for testing
contract MockToken is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }
}

contract PauseVaultTest is Test {
    // Contract to test
    MainVault public vault;
    PauserList public pauserList;
    MockToken public token;

    // Test addresses
    address mainInvestor;
    address backupInvestor;
    address emergencyInvestor;
    address manager;
    address admin;
    address backupAdmin;
    address emergencyAdmin;
    address feeWallet;
    address profitWallet;
    address pauser;
    address nonPauser;

    event Paused(address account);
    event Unpaused(address account);

    function setUp() public {
        mainInvestor = address(0x1);
        backupInvestor = address(0x2);
        emergencyInvestor = address(0x3);
        manager = address(0x4);
        admin = address(0x5);
        backupAdmin = address(0x6);
        emergencyAdmin = address(0x7);
        feeWallet = address(0x8);
        profitWallet = address(0x9);
        pauser = address(0x10);
        nonPauser = address(0x11);

        console.log("Deploying token");
        // Deploy token
        token = new MockToken();

        console.log("Deploying pauser list");
        // Deploy pauser list with admin as the initial admin
        pauserList = new PauserList(admin);

        console.log("Admin address:", admin);
        console.log("Checking if admin has DEFAULT_ADMIN_ROLE");
        bool hasAdminRole = pauserList.hasRole(pauserList.DEFAULT_ADMIN_ROLE(), admin);
        console.log("Admin has DEFAULT_ADMIN_ROLE:", hasAdminRole);

        try pauserList.hasRole(pauserList.DEFAULT_ADMIN_ROLE(), admin) returns (bool result) {
            console.log("hasRole check passed with result:", result);
        } catch Error(string memory reason) {
            console.log("hasRole check failed with reason:", reason);
        } catch (bytes memory) {
            console.log("hasRole check failed with unknown reason");
        }

        console.log("Adding pauser to the pauser list");
        // Add pauser to the pauser list
        vm.startPrank(admin);
        console.log("Using admin to grant role. Admin address:", admin);
        console.logBytes32(pauserList.PAUSER_ROLE());
        console.log("Pauser address:", pauser);
        try pauserList.grantRole(pauserList.PAUSER_ROLE(), pauser) {
            console.log("grantRole call succeeded");
        } catch Error(string memory reason) {
            console.log("grantRole call failed with reason:", reason);
        } catch (bytes memory lowLevelData) {
            bytes4 errorSelector = bytes4(lowLevelData);
            console.log("grantRole call failed with error selector:", vm.toString(errorSelector));
        }
        vm.stopPrank();

        console.log("Deploying implementation contract");
        // Deploy the implementation contract
        MainVault implementation = new MainVault();

        console.log("Creating initialization parameters");
        // Create initialization parameters
        IMainVault.InitParams memory params = IMainVault.InitParams({
            mainInvestor: mainInvestor,
            backupInvestor: backupInvestor,
            emergencyInvestor: emergencyInvestor,
            manager: manager,
            admin: admin,
            backupAdmin: backupAdmin,
            emergencyAdmin: emergencyAdmin,
            feeWallet: feeWallet,
            profitWallet: profitWallet,
            feePercentage: 1000, // 10%
            currentImplementationOfInvestmentVault: address(0),
            pauserList: address(pauserList),
            meraPriceOracle: address(0),
            lockPeriod: 0
        });

        console.log("Encoding initialization call");
        // Encode initialization call
        bytes memory initData = abi.encodeWithSelector(MainVault.initialize.selector, params);

        console.log("Deploying proxy with implementation");
        // Deploy proxy with implementation
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);

        console.log("Getting vault interface");
        // Get the vault interface for testing
        vault = MainVault(address(proxy));

        console.log("Making token available for deposits by investor");
        // Make token available for deposits
        vm.startPrank(mainInvestor);
        IMainVault.TokenAvailability[] memory tokenConfigs = new IMainVault.TokenAvailability[](1);
        tokenConfigs[0] = IMainVault.TokenAvailability({token: address(token), isAvailable: true});
        vault.setTokenAvailabilityByInvestor(tokenConfigs);
        vm.stopPrank();

        console.log("Making token available for deposits by admin");
        vm.startPrank(admin);
        IMainVault.TokenAvailability[] memory tokenConfigsAdmin = new IMainVault.TokenAvailability[](1);
        tokenConfigsAdmin[0] = IMainVault.TokenAvailability({token: address(token), isAvailable: true});
        vault.setTokenAvailabilityByAdmin(tokenConfigsAdmin);
        vm.stopPrank();

        console.log("Transferring tokens to users");
        // Transfer some tokens to users for testing
        token.transfer(mainInvestor, 1000 * 10 ** 18);
        token.transfer(nonPauser, 1000 * 10 ** 18);

        console.log("Setup completed");
    }

    function test_OnlyPauserCanPause() public {
        // Non-pauser should not be able to pause
        vm.startPrank(nonPauser);
        vm.expectRevert(MainVault.NotPauser.selector);
        vault.pause();
        vm.stopPrank();

        // Pauser should be able to pause
        vm.startPrank(pauser);
        vm.expectEmit(true, false, false, false);
        emit Paused(pauser);
        vault.pause();
        vm.stopPrank();

        // Verify that the contract is paused
        assertTrue(vault.paused(), "Contract should be paused");
    }

    function test_OnlyPauserCanUnpause() public {
        // First pause the contract
        vm.prank(pauser);
        vault.pause();

        // Non-pauser should not be able to unpause
        vm.startPrank(nonPauser);
        vm.expectRevert(MainVault.NotPauser.selector);
        vault.unpause();
        vm.stopPrank();

        // Pauser should be able to unpause
        vm.startPrank(pauser);
        vm.expectEmit(true, false, false, false);
        emit Unpaused(pauser);
        vault.unpause();
        vm.stopPrank();

        // Verify that the contract is not paused
        assertFalse(vault.paused(), "Contract should not be paused");
    }

    function test_CannotDepositWhenPaused() public {
        // First pause the contract
        vm.prank(pauser);
        vault.pause();

        // Prepare for deposit
        vm.startPrank(mainInvestor);
        token.approve(address(vault), 100 * 10 ** 18);

        // Try to deposit - should revert with EnforcedPause
        vm.expectRevert(bytes4(0xd93c0665)); // EnforcedPause() error selector
        vault.deposit(IERC20(address(token)), 100 * 10 ** 18);
        vm.stopPrank();

        // Unpause and try again - should work
        vm.prank(pauser);
        vault.unpause();

        vm.startPrank(mainInvestor);
        token.approve(address(vault), 100 * 10 ** 18);
        vault.deposit(IERC20(address(token)), 100 * 10 ** 18);
        vm.stopPrank();

        // Check that the deposit worked
        assertEq(token.balanceOf(address(vault)), 100 * 10 ** 18, "Vault should have received tokens");
    }
}
