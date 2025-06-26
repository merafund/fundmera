// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 fundmera.com

// https://github.com/merafund
pragma solidity ^0.8.29;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IPauserList} from "./interfaces/IPauserList.sol";

/**
 * @title PauserList
 * @dev Contract for storing a list of addresses with the ability to pause functions
 */
contract PauserList is AccessControl, IPauserList {
    bytes32 public constant override(IPauserList) PAUSER_ROLE = keccak256("PAUSER_ROLE");

    error ZeroAddress();

    constructor(address initialAdmin) {
        require(initialAdmin != address(0), ZeroAddress());
        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _setRoleAdmin(PAUSER_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(DEFAULT_ADMIN_ROLE, DEFAULT_ADMIN_ROLE);
    }
}
