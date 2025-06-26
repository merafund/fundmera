// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 fundmera.com

// https://github.com/merafund
pragma solidity ^0.8.29;

import {AgentDistributionProfit} from "../AgentDistributionProfit.sol";

contract AgentDistributionProfitMockRevokeRole is AgentDistributionProfit {
    function initialize(
        address _fundWallet,
        address _agentWallet,
        address _adminWallet,
        address _emergencyAdminWallet,
        address _reserveAdminWallet,
        address _emergencyAgentWallet,
        address _reserveAgentWallet,
        address _meraCapitalWallet
    ) external override initializer {
        require(_fundWallet != address(0), ZeroAddress());
        require(_agentWallet != address(0), ZeroAddress());
        require(_adminWallet != address(0), ZeroAddress());
        require(_emergencyAdminWallet != address(0), ZeroAddress());
        require(_reserveAdminWallet != address(0), ZeroAddress());
        require(_emergencyAgentWallet != address(0), ZeroAddress());
        require(_reserveAgentWallet != address(0), ZeroAddress());
        require(_meraCapitalWallet != address(0), ZeroAddress());

        __UUPSUpgradeable_init();
        __AccessControl_init();

        fundWallet = _fundWallet;
        meraCapitalWallet = _meraCapitalWallet;
        agentPercentage = MIN_AGENT_PERCENTAGE;

        // Setup roles
        _grantRole(MAIN_AGENT_ROLE, _agentWallet);
        _grantRole(BACKUP_AGENT_ROLE, _reserveAgentWallet);
        _grantRole(EMERGENCY_AGENT_ROLE, _emergencyAgentWallet);
        _grantRole(ADMIN_ROLE, _adminWallet);
        _grantRole(BACKUP_ADMIN_ROLE, _reserveAdminWallet);
        _grantRole(EMERGENCY_ADMIN_ROLE, _emergencyAdminWallet);

        // Setup role hierarchy
        _setRoleAdmin(MAIN_AGENT_ROLE, MAIN_AGENT_ROLE);
        _setRoleAdmin(BACKUP_AGENT_ROLE, BACKUP_AGENT_ROLE);
        _setRoleAdmin(EMERGENCY_AGENT_ROLE, EMERGENCY_AGENT_ROLE);
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(BACKUP_ADMIN_ROLE, BACKUP_ADMIN_ROLE);
        _setRoleAdmin(EMERGENCY_ADMIN_ROLE, EMERGENCY_ADMIN_ROLE);

        // Emergency agent can manage main and backup agents
        _setRoleAdmin(MAIN_AGENT_ROLE, EMERGENCY_AGENT_ROLE);
        _setRoleAdmin(BACKUP_AGENT_ROLE, EMERGENCY_AGENT_ROLE);

        // Emergency admin can manage all admin roles
        _setRoleAdmin(ADMIN_ROLE, EMERGENCY_ADMIN_ROLE);
        _setRoleAdmin(BACKUP_ADMIN_ROLE, EMERGENCY_ADMIN_ROLE);
    }

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
