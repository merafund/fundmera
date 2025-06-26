// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 fundmera.com

// https://github.com/merafund
pragma solidity 0.8.29;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {MultiAdminSingleHolderAccessControlUppgradable} from
    "./utils/MultiAdminSingleHolderAccessControlUppgradable.sol";
import {IAgentDistributionProfit} from "./interfaces/IAgentDistributionProfit.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract AgentDistributionProfit is
    IAgentDistributionProfit,
    Initializable,
    UUPSUpgradeable,
    MultiAdminSingleHolderAccessControlUppgradable
{
    using SafeERC20 for IERC20;

    // Constants
    uint256 public constant UPGRADE_TIME_LIMIT = 1 days; // Time limit for upgrade approval
    uint256 public constant MIN_AGENT_PERCENTAGE = 2000; // 20%
    uint256 public constant MAX_AGENT_PERCENTAGE = 3000; // 30%
    uint256 public constant MAX_PERCENTAGE = 10000; // 100%
    uint256 public constant MERA_CAPITAL_PERCENTAGE = 5000; // 50%

    // Role definitions
    bytes32 public constant MAIN_AGENT_ROLE = keccak256("MAIN_AGENT_ROLE");
    bytes32 public constant BACKUP_AGENT_ROLE = keccak256("BACKUP_AGENT_ROLE");
    bytes32 public constant EMERGENCY_AGENT_ROLE = keccak256("EMERGENCY_AGENT_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant BACKUP_ADMIN_ROLE = keccak256("BACKUP_ADMIN_ROLE");
    bytes32 public constant EMERGENCY_ADMIN_ROLE = keccak256("EMERGENCY_ADMIN_ROLE");

    // State variables
    address public fundWallet;
    address public meraCapitalWallet;
    uint256 public agentPercentage;
    uint256 public fundProfit;
    uint256 public meraCapitalProfit;
    address public adminApproved;
    address public agentApproved;
    uint256 public adminApprovedTimestamp;
    uint256 public agentApprovedTimestamp;

    modifier onlyAdminOrAgent() {
        require(hasRole(ADMIN_ROLE, msg.sender) || hasRole(MAIN_AGENT_ROLE, msg.sender), AccessDenied());
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _fundWallet,
        address _agentWallet,
        address _adminWallet,
        address _emergencyAdminWallet,
        address _reserveAdminWallet,
        address _emergencyAgentWallet,
        address _reserveAgentWallet,
        address _meraCapitalWallet
    ) external virtual initializer {
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

    ///@inheritdoc IAgentDistributionProfit
    function approveUpgrade(address newImplementation) external onlyAdminOrAgent {
        require(newImplementation != address(0), InvalidUpgradeAddress());

        if (hasRole(ADMIN_ROLE, msg.sender)) {
            adminApproved = newImplementation;
            adminApprovedTimestamp = block.timestamp;
            emit UpgradeApproved(newImplementation, msg.sender);
        } else {
            agentApproved = newImplementation;
            agentApprovedTimestamp = block.timestamp;
            emit UpgradeApproved(newImplementation, msg.sender);
        }
    }

    ///@inheritdoc IAgentDistributionProfit
    function distributeProfit(address[] calldata tokens) external onlyAdminOrAgent {
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            uint256 balance = IERC20(token).balanceOf(address(this));
            uint256 agentAmount = balance * agentPercentage / MAX_PERCENTAGE;
            uint256 meraCapitalAmount = balance * MERA_CAPITAL_PERCENTAGE / MAX_PERCENTAGE;
            uint256 fundAmount = balance - agentAmount - meraCapitalAmount;

            if (fundAmount > 0) {
                if (hasRole(ADMIN_ROLE, msg.sender)) {
                    IERC20(token).safeTransfer(fundWallet, fundAmount);
                } else {
                    fundProfit += fundAmount;
                }
            }

            if (meraCapitalAmount > 0) {
                if (hasRole(ADMIN_ROLE, msg.sender)) {
                    IERC20(token).safeTransfer(meraCapitalWallet, meraCapitalAmount);
                } else {
                    meraCapitalProfit += meraCapitalAmount;
                }
            }

            if (agentAmount > 0) {
                IERC20(token).safeTransfer(getRoleHolder(MAIN_AGENT_ROLE), agentAmount);
            }
        }
    }

    ///@inheritdoc IAgentDistributionProfit
    function increaseAgentPercentage(uint256 _agentPercentage) external onlyRole(MAIN_AGENT_ROLE) {
        require(
            _agentPercentage >= MIN_AGENT_PERCENTAGE && _agentPercentage <= MAX_AGENT_PERCENTAGE,
            AgentPercentageOutOfRange()
        );
        require(_agentPercentage > agentPercentage, AgentPercentageCanOnlyIncrease());
        agentPercentage = _agentPercentage;
    }

    ///@inheritdoc IAgentDistributionProfit
    function setFundWallet(address _fundWallet) external onlyRole(ADMIN_ROLE) {
        require(_fundWallet != address(0), ZeroAddress());
        fundWallet = _fundWallet;
        emit FundWalletSet(msg.sender, _fundWallet);
    }

    ///@inheritdoc IAgentDistributionProfit
    function setMeraCapitalWallet(address _meraCapitalWallet) external onlyRole(ADMIN_ROLE) {
        require(_meraCapitalWallet != address(0), ZeroAddress());
        meraCapitalWallet = _meraCapitalWallet;
        emit MeraCapitalWalletSet(msg.sender, _meraCapitalWallet);
    }

    function _authorizeUpgrade(address newImplementation) internal view override onlyAdminOrAgent {
        require(newImplementation != address(0), InvalidUpgradeAddress());
        require(newImplementation == adminApproved, ImplementationNotApprovedByAdmin());
        require(newImplementation == agentApproved, ImplementationNotApprovedByAgent());
        require(block.timestamp - adminApprovedTimestamp < UPGRADE_TIME_LIMIT, UpgradeDeadlineExpired());
        require(block.timestamp - agentApprovedTimestamp < UPGRADE_TIME_LIMIT, UpgradeDeadlineExpired());
    }
}
