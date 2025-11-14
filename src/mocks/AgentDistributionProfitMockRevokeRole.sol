// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 fundmera.com

// https://github.com/merafund
pragma solidity ^0.8.29;

import {AgentDistributionProfit} from "../AgentDistributionProfit.sol";

contract AgentDistributionProfitMockRevokeRole is AgentDistributionProfit {
    constructor(
        address _fundWallet,
        address _agentWallet,
        address _adminWallet,
        address _emergencyAdminWallet,
        address _reserveAdminWallet,
        address _emergencyAgentWallet,
        address _reserveAgentWallet,
        address _meraCapitalWallet
    ) AgentDistributionProfit(
        _fundWallet,
        _agentWallet,
        _adminWallet,
        _emergencyAdminWallet,
        _reserveAdminWallet,
        _emergencyAgentWallet,
        _reserveAgentWallet,
        _meraCapitalWallet
    ) {}

    // Override _revokeRole to simulate failed revocation only for MAIN_AGENT_ROLE
    function _revokeRole(bytes32 role, address account) internal virtual override returns (bool) {
        if (role == MAIN_AGENT_ROLE) {
            // Do not actually revoke the role, but emit the event to simulate the attempt
            emit RoleRevoked(role, account, msg.sender);
            return false;
        }
        return super._revokeRole(role, account);
    }
}
