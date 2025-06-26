// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 fundmera.com

// https://github.com/merafund
pragma solidity ^0.8.29;

import {MainVault} from "../../src/MainVault.sol";

contract MainVaultMockRevokeRole is MainVault {
    // Override initialize to avoid reinitialization errors
    function initialize(InitParams calldata params) public override initializer {
        super.initialize(params);
    }

    // Override _revokeRole to simulate failed revocation only for MAIN_INVESTOR_ROLE
    function _revokeRole(bytes32 role, address account) internal virtual override returns (bool) {
        if (role == MAIN_INVESTOR_ROLE) {
            // Do not actually revoke the role, but emit the event to simulate the attempt
            emit RoleRevoked(role, account, msg.sender);
            return false;
        }
        return super._revokeRole(role, account);
    }
}
