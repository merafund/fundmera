// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 fundmera.com

// https://github.com/merafund
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {PauserList} from "../src/PauserList.sol";

contract PauserListTest is Test {
    PauserList public pauserList;
    address public admin;
    address public user;

    function setUp() public {
        admin = makeAddr("admin");
        user = makeAddr("user");
        vm.startPrank(admin);
        pauserList = new PauserList(admin);
        vm.stopPrank();
    }

    function test_Constructor_SetsAdmin() public {
        assertTrue(pauserList.hasRole(pauserList.DEFAULT_ADMIN_ROLE(), admin));
    }

    function test_Constructor_RevertWhenZeroAddress() public {
        vm.expectRevert(PauserList.ZeroAddress.selector);
        new PauserList(address(0));
    }

    function test_Constructor_SetsRoleAdmin() public {
        assertEq(pauserList.getRoleAdmin(pauserList.PAUSER_ROLE()), pauserList.DEFAULT_ADMIN_ROLE());
        assertEq(pauserList.getRoleAdmin(pauserList.DEFAULT_ADMIN_ROLE()), pauserList.DEFAULT_ADMIN_ROLE());
    }
}
