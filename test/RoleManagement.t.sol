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
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessControlEnumerableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";

contract RoleManagementTest is Test {
    MainVault public vault;

    bytes32 public constant MAIN_INVESTOR_ROLE = keccak256("MAIN_INVESTOR_ROLE");
    bytes32 public constant BACKUP_INVESTOR_ROLE = keccak256("BACKUP_INVESTOR_ROLE");
    bytes32 public constant EMERGENCY_INVESTOR_ROLE = keccak256("EMERGENCY_INVESTOR_ROLE");
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant BACKUP_ADMIN_ROLE = keccak256("BACKUP_ADMIN_ROLE");
    bytes32 public constant EMERGENCY_ADMIN_ROLE = keccak256("EMERGENCY_ADMIN_ROLE");
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    address mainInvestor;
    address backupInvestor;
    address emergencyInvestor;
    address manager;
    address admin;
    address backupAdmin;
    address emergencyAdmin;
    address feeWallet;
    address profitWallet;
    address alice;
    address bob;
    address charlie;
    address dave;
    address eve;

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
        alice = address(0x10);
        bob = address(0x11);
        charlie = address(0x12);
        dave = address(0x13);
        eve = address(0x14);

        MainVault implementation = new MainVault();

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
            feePercentage: 1000,
            currentImplementationOfInvestmentVault: address(0),
            pauserList: address(0),
            meraPriceOracle: address(0)
        });

        bytes memory initData = abi.encodeWithSelector(MainVault.initialize.selector, params);

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);

        vault = MainVault(address(proxy));
    }

    function testInitialRoles() public view {
        assertTrue(vault.hasRole(MAIN_INVESTOR_ROLE, mainInvestor), "Main investor role not assigned");
        assertTrue(vault.hasRole(BACKUP_INVESTOR_ROLE, backupInvestor), "Backup investor role not assigned");
        assertTrue(vault.hasRole(EMERGENCY_INVESTOR_ROLE, emergencyInvestor), "Emergency investor role not assigned");
        assertTrue(vault.hasRole(MANAGER_ROLE, manager), "Manager role not assigned");
        assertTrue(vault.hasRole(ADMIN_ROLE, admin), "Admin role not assigned");
        assertTrue(vault.hasRole(BACKUP_ADMIN_ROLE, backupAdmin), "Backup admin role not assigned");
        assertTrue(vault.hasRole(EMERGENCY_ADMIN_ROLE, emergencyAdmin), "Emergency admin role not assigned");
    }

    function testMainInvestorPermissions() public {
        assertTrue(vault.hasRole(MAIN_INVESTOR_ROLE, mainInvestor), "Main investor should have the role");

        // Main investor can only change himself (reassign MAIN_INVESTOR_ROLE)
        vm.prank(mainInvestor);
        vault.grantRole(MAIN_INVESTOR_ROLE, alice);

        assertTrue(vault.hasRole(MAIN_INVESTOR_ROLE, alice), "Alice should have main investor role");
        assertFalse(vault.hasRole(MAIN_INVESTOR_ROLE, mainInvestor), "Original main investor should lose role");

        // Main investor cannot change backup investor role
        vm.prank(alice);
        vm.expectRevert();
        vault.grantRole(BACKUP_INVESTOR_ROLE, bob);

        // Main investor cannot change emergency investor role
        vm.prank(alice);
        vm.expectRevert();
        vault.grantRole(EMERGENCY_INVESTOR_ROLE, charlie);
    }

    function testBackupInvestorPermissions() public {
        assertTrue(vault.hasRole(BACKUP_INVESTOR_ROLE, backupInvestor), "Backup investor should have the role");

        // Backup investor can change himself
        vm.prank(backupInvestor);
        vault.grantRole(BACKUP_INVESTOR_ROLE, bob);

        assertTrue(vault.hasRole(BACKUP_INVESTOR_ROLE, bob), "Bob should have backup investor role");
        assertFalse(vault.hasRole(BACKUP_INVESTOR_ROLE, backupInvestor), "Original backup investor should lose role");

        // Backup investor can change main investor (admin)
        vm.prank(bob);
        vault.grantRole(MAIN_INVESTOR_ROLE, charlie);

        assertTrue(vault.hasRole(MAIN_INVESTOR_ROLE, charlie), "Charlie should have main investor role");
        assertFalse(vault.hasRole(MAIN_INVESTOR_ROLE, mainInvestor), "Original main investor should lose role");

        // Backup investor cannot change emergency investor role
        vm.prank(bob);
        vm.expectRevert();
        vault.grantRole(EMERGENCY_INVESTOR_ROLE, dave);
    }

    function testEmergencyInvestorPermissions() public {
        assertTrue(vault.hasRole(EMERGENCY_INVESTOR_ROLE, emergencyInvestor), "Emergency investor should have the role");

        vm.startPrank(emergencyInvestor);

        // Emergency investor can change main investor (admin)
        vault.grantRole(MAIN_INVESTOR_ROLE, alice);
        assertTrue(vault.hasRole(MAIN_INVESTOR_ROLE, alice), "Alice should have main investor role");
        assertFalse(vault.hasRole(MAIN_INVESTOR_ROLE, mainInvestor), "Original main investor should lose role");

        // Emergency investor can change backup investor
        vault.grantRole(BACKUP_INVESTOR_ROLE, bob);
        assertTrue(vault.hasRole(BACKUP_INVESTOR_ROLE, bob), "Bob should have backup investor role");
        assertFalse(vault.hasRole(BACKUP_INVESTOR_ROLE, backupInvestor), "Original backup investor should lose role");

        // Emergency investor can change himself
        vault.grantRole(EMERGENCY_INVESTOR_ROLE, charlie);
        assertTrue(vault.hasRole(EMERGENCY_INVESTOR_ROLE, charlie), "Charlie should have emergency investor role");
        assertFalse(
            vault.hasRole(EMERGENCY_INVESTOR_ROLE, emergencyInvestor), "Original emergency investor should lose role"
        );

        vm.stopPrank();

        // Emergency investor cannot change admin roles
        vm.prank(charlie);
        vm.expectRevert();
        vault.grantRole(ADMIN_ROLE, dave);
    }

    function testRoleSeparation() public {
        vm.startPrank(emergencyInvestor);

        vm.expectRevert();
        vault.grantRole(ADMIN_ROLE, alice);

        vm.expectRevert();
        vault.grantRole(BACKUP_ADMIN_ROLE, alice);

        vm.expectRevert();
        vault.grantRole(EMERGENCY_ADMIN_ROLE, alice);

        vm.stopPrank();

        vm.startPrank(emergencyAdmin);

        vm.expectRevert();
        vault.grantRole(MAIN_INVESTOR_ROLE, alice);

        vm.expectRevert();
        vault.grantRole(BACKUP_INVESTOR_ROLE, alice);

        vm.expectRevert();
        vault.grantRole(EMERGENCY_INVESTOR_ROLE, alice);

        vm.stopPrank();
    }

    function testWithdrawalLock() public {
        uint256 currentTime = block.timestamp;

        vm.prank(emergencyInvestor);
        vault.grantRole(MAIN_INVESTOR_ROLE, alice);

        uint64 withdrawalLockedUntil = vault.withdrawalLockedUntil();
        assertTrue(
            withdrawalLockedUntil >= uint64(currentTime + 7 days), "Withdrawal should be locked for at least 7 days"
        );
    }

    function testRoleExclusivity() public {
        vm.prank(emergencyInvestor);
        vault.grantRole(MAIN_INVESTOR_ROLE, alice);

        assertFalse(vault.hasRole(MAIN_INVESTOR_ROLE, mainInvestor), "Original main investor should lose the role");
        assertTrue(vault.hasRole(MAIN_INVESTOR_ROLE, alice), "Alice should have the role");

        vm.prank(emergencyAdmin);
        vault.grantRole(ADMIN_ROLE, bob);

        assertFalse(vault.hasRole(ADMIN_ROLE, admin), "Original admin should lose the role");
        assertTrue(vault.hasRole(ADMIN_ROLE, bob), "Bob should have the role");

        vm.prank(emergencyAdmin);
        vault.grantRole(EMERGENCY_ADMIN_ROLE, charlie);

        assertFalse(
            vault.hasRole(EMERGENCY_ADMIN_ROLE, emergencyAdmin), "Original emergency admin should lose the role"
        );
        assertTrue(vault.hasRole(EMERGENCY_ADMIN_ROLE, charlie), "Charlie should have the role");
    }

    function testAdminPermissions() public {
        assertTrue(vault.hasRole(ADMIN_ROLE, admin), "Admin should have the role");

        // Admin can only change himself (reassign ADMIN_ROLE)
        vm.prank(admin);
        vault.grantRole(ADMIN_ROLE, alice);

        assertTrue(vault.hasRole(ADMIN_ROLE, alice), "Alice should have admin role");
        assertFalse(vault.hasRole(ADMIN_ROLE, admin), "Original admin should lose role");

        // Admin cannot change backup admin role
        vm.prank(alice);
        vm.expectRevert();
        vault.grantRole(BACKUP_ADMIN_ROLE, bob);

        // Admin cannot change emergency admin role
        vm.prank(alice);
        vm.expectRevert();
        vault.grantRole(EMERGENCY_ADMIN_ROLE, charlie);
    }

    function testBackupAdminPermissions() public {
        assertTrue(vault.hasRole(BACKUP_ADMIN_ROLE, backupAdmin), "Backup admin should have the role");

        // Backup admin can change himself
        vm.prank(backupAdmin);
        // Backup admin can change MANAGER_ROLE
        vault.grantRole(MANAGER_ROLE, alice);
        assertTrue(vault.hasRole(MANAGER_ROLE, alice), "Alice should have manager role");
        assertFalse(vault.hasRole(MANAGER_ROLE, manager), "Original manager should lose role");

        vm.prank(backupAdmin);

        vault.grantRole(BACKUP_ADMIN_ROLE, bob);

        assertTrue(vault.hasRole(BACKUP_ADMIN_ROLE, bob), "Bob should have backup admin role");
        assertFalse(vault.hasRole(BACKUP_ADMIN_ROLE, backupAdmin), "Original backup admin should lose role");

        // Backup admin can change admin
        vm.prank(bob);
        vault.grantRole(ADMIN_ROLE, charlie);

        assertTrue(vault.hasRole(ADMIN_ROLE, charlie), "Charlie should have admin role");
        assertFalse(vault.hasRole(ADMIN_ROLE, admin), "Original admin should lose role");
        // Backup admin cannot change emergency admin role
        vm.prank(bob);
        vm.expectRevert();
        vault.grantRole(EMERGENCY_ADMIN_ROLE, dave);
    }

    function testEmergencyAdminPermissions() public {
        assertTrue(vault.hasRole(EMERGENCY_ADMIN_ROLE, emergencyAdmin), "Emergency admin should have the role");

        vm.startPrank(emergencyAdmin);
        // Emergency admin can change MANAGER_ROLE
        vault.grantRole(MANAGER_ROLE, alice);
        assertTrue(vault.hasRole(MANAGER_ROLE, alice), "Alice should have manager role");
        assertFalse(vault.hasRole(MANAGER_ROLE, manager), "Original manager should lose role");

        // Emergency admin can change admin
        vault.grantRole(ADMIN_ROLE, alice);
        assertTrue(vault.hasRole(ADMIN_ROLE, alice), "Alice should have admin role");
        assertFalse(vault.hasRole(ADMIN_ROLE, admin), "Original admin should lose role");

        // Emergency admin can change backup admin
        vault.grantRole(BACKUP_ADMIN_ROLE, bob);
        assertTrue(vault.hasRole(BACKUP_ADMIN_ROLE, bob), "Bob should have backup admin role");
        assertFalse(vault.hasRole(BACKUP_ADMIN_ROLE, backupAdmin), "Original backup admin should lose role");

        // Emergency admin can change himself
        vault.grantRole(EMERGENCY_ADMIN_ROLE, charlie);
        assertTrue(vault.hasRole(EMERGENCY_ADMIN_ROLE, charlie), "Charlie should have emergency admin role");
        assertFalse(vault.hasRole(EMERGENCY_ADMIN_ROLE, emergencyAdmin), "Original emergency admin should lose role");

        vm.stopPrank();

        // Emergency admin cannot change investor roles
        vm.prank(charlie);
        vm.expectRevert();
        vault.grantRole(MAIN_INVESTOR_ROLE, dave);
    }

    function testManagerPermissions() public {
        assertTrue(vault.hasRole(MANAGER_ROLE, manager), "Manager should have the role");

        vm.startPrank(manager);

        vm.expectRevert();
        vault.grantRole(BACKUP_ADMIN_ROLE, alice);

        vm.expectRevert();
        vault.grantRole(EMERGENCY_ADMIN_ROLE, bob);

        // Manager cannot change admin role
        vm.expectRevert();
        vault.grantRole(ADMIN_ROLE, charlie);

        // Manager cannot change investor roles
        vm.expectRevert();
        vault.grantRole(MAIN_INVESTOR_ROLE, dave);
    }
}
