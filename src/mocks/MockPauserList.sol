// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 fundmera.com

// https://github.com/merafund
pragma solidity ^0.8.29;

import {IPauserList} from "../interfaces/IPauserList.sol";

contract MockPauserList is IPauserList {
    bytes32 public constant override PAUSER_ROLE = keccak256("PAUSER_ROLE");
    mapping(address => bool) public pausers;

    constructor() {
        pausers[msg.sender] = true;
    }

    function hasRole(bytes32 role, address account) external view override returns (bool) {
        if (role == PAUSER_ROLE) {
            return pausers[account];
        }
        return false;
    }

    function getRoleAdmin(bytes32) external pure override returns (bytes32) {
        return PAUSER_ROLE;
    }

    function grantRole(bytes32 role, address account) external override {
        require(role == PAUSER_ROLE, "Invalid role");
        pausers[account] = true;
    }

    function revokeRole(bytes32 role, address account) external override {
        require(role == PAUSER_ROLE, "Invalid role");
        pausers[account] = false;
    }

    function renounceRole(bytes32 role, address callerConfirmation) external override {
        require(role == PAUSER_ROLE, "Invalid role");
        require(msg.sender == callerConfirmation, "Invalid caller");
        pausers[callerConfirmation] = false;
    }

    // Additional helper functions
    function addPauser(address pauser) external {
        pausers[pauser] = true;
    }

    function removePauser(address pauser) external {
        pausers[pauser] = false;
    }
}
