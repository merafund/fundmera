// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 fundmera.com

// https://github.com/merafund
pragma solidity ^0.8.29;

import {Test, console} from "forge-std/Test.sol";
import {AgentDistributionProfit} from "../src/AgentDistributionProfit.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAgentDistributionProfit} from "../src/interfaces/IAgentDistributionProfit.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {AgentDistributionProfitMockRevokeRole} from "../src/mocks/AgentDistributionProfitMockRevokeRole.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract AgentDistributionProfitTest is Test {
    AgentDistributionProfit public implementation;
    ERC1967Proxy public proxy;
    AgentDistributionProfit public profitDistributor;
    MockERC20 public token;
    MockERC20 public secondToken;

    address public owner = address(1);
    address public user1 = address(2);
    address public user2 = address(3);

    address public mainAgent = vm.addr(123456);
    address public backupAgent = address(5);
    address public emergencyAgent = address(6);
    address public admin = address(7);
    address public backupAdmin = address(8);
    address public emergencyAdmin = address(9);
    address public fundWallet = address(10);
    address public meraCapitalWallet = address(11);

    uint256 public constant INITIAL_BALANCE = 10000 * 10 ** 18;
    uint256 public constant DISTRIBUTION_AMOUNT = 1000 * 10 ** 18;

    event UpgradeApproved(address indexed implementation, address indexed approver);
    event FundWalletSet(address sender, address newFundWallet);
    event MeraCapitalWalletSet(address sender, address newMeraCapitalWallet);
    event Upgraded(address indexed newImplementation);

    function setUp() public {
        vm.startPrank(owner);

        // Deploy mock tokens
        token = new MockERC20();
        secondToken = new MockERC20();

        // Deploy implementation
        implementation = new AgentDistributionProfit();

        // Initialize implementation
        bytes memory initData = abi.encodeWithSelector(
            AgentDistributionProfit.initialize.selector,
            fundWallet,
            mainAgent,
            admin,
            emergencyAdmin,
            backupAdmin,
            emergencyAgent,
            backupAgent,
            meraCapitalWallet
        );

        // Deploy proxy
        proxy = new ERC1967Proxy(address(implementation), initData);
        profitDistributor = AgentDistributionProfit(address(proxy));

        // Transfer tokens
        token.transfer(address(profitDistributor), INITIAL_BALANCE);
        secondToken.transfer(address(profitDistributor), INITIAL_BALANCE);

        vm.stopPrank();
    }

    function testInitialization() public {
        assertEq(profitDistributor.fundWallet(), fundWallet, "Fund wallet should be set correctly");
        assertEq(
            profitDistributor.meraCapitalWallet(), meraCapitalWallet, "Mera Capital wallet should be set correctly"
        );
        assertEq(
            profitDistributor.agentPercentage(),
            profitDistributor.MIN_AGENT_PERCENTAGE(),
            "Agent percentage should be set to minimum"
        );

        assertTrue(
            profitDistributor.hasRole(profitDistributor.MAIN_AGENT_ROLE(), mainAgent), "Main agent role should be set"
        );
        assertTrue(
            profitDistributor.hasRole(profitDistributor.BACKUP_AGENT_ROLE(), backupAgent),
            "Backup agent role should be set"
        );
        assertTrue(
            profitDistributor.hasRole(profitDistributor.EMERGENCY_AGENT_ROLE(), emergencyAgent),
            "Emergency agent role should be set"
        );
        assertTrue(profitDistributor.hasRole(profitDistributor.ADMIN_ROLE(), admin), "Admin role should be set");
        assertTrue(
            profitDistributor.hasRole(profitDistributor.BACKUP_ADMIN_ROLE(), backupAdmin),
            "Backup admin role should be set"
        );
        assertTrue(
            profitDistributor.hasRole(profitDistributor.EMERGENCY_ADMIN_ROLE(), emergencyAdmin),
            "Emergency admin role should be set"
        );
    }

    function testDistributeProfitByAdmin() public {
        vm.startPrank(admin);

        uint256 initialFundBalance = token.balanceOf(fundWallet);
        uint256 initialMeraBalance = token.balanceOf(meraCapitalWallet);
        uint256 initialAgentBalance = token.balanceOf(mainAgent);

        address[] memory tokens = new address[](1);
        tokens[0] = address(token);

        profitDistributor.distributeProfit(tokens);

        uint256 agentAmount = INITIAL_BALANCE * profitDistributor.agentPercentage() / profitDistributor.MAX_PERCENTAGE();
        uint256 meraAmount =
            INITIAL_BALANCE * profitDistributor.MERA_CAPITAL_PERCENTAGE() / profitDistributor.MAX_PERCENTAGE();
        uint256 fundAmount = INITIAL_BALANCE - agentAmount - meraAmount;

        assertEq(
            token.balanceOf(fundWallet) - initialFundBalance, fundAmount, "Fund wallet should receive correct amount"
        );
        assertEq(
            token.balanceOf(meraCapitalWallet) - initialMeraBalance,
            meraAmount,
            "Mera Capital wallet should receive correct amount"
        );
        assertEq(token.balanceOf(mainAgent) - initialAgentBalance, agentAmount, "Agent should receive correct amount");

        vm.stopPrank();
    }

    function testDistributeProfitByAgent() public {
        vm.startPrank(mainAgent);

        // Get initial balances of all wallets
        uint256 initialFundBalance = token.balanceOf(profitDistributor.fundWallet());
        uint256 initialMeraBalance = token.balanceOf(profitDistributor.meraCapitalWallet());
        uint256 initialAgentBalance = token.balanceOf(mainAgent);

        address[] memory tokens = new address[](1);
        tokens[0] = address(token);

        profitDistributor.distributeProfit(tokens);

        // Calculate expected amounts
        uint256 agentAmount = INITIAL_BALANCE * profitDistributor.agentPercentage() / profitDistributor.MAX_PERCENTAGE();
        uint256 meraAmount =
            INITIAL_BALANCE * profitDistributor.MERA_CAPITAL_PERCENTAGE() / profitDistributor.MAX_PERCENTAGE();
        uint256 fundAmount = INITIAL_BALANCE - agentAmount - meraAmount;

        // Check that fund wallet received correct amount
        assertEq(
            token.balanceOf(profitDistributor.fundWallet()) - initialFundBalance, 
            fundAmount, 
            "Fund wallet should receive correct amount"
        );
        
        // Check that mera capital wallet received correct amount
        assertEq(
            token.balanceOf(profitDistributor.meraCapitalWallet()) - initialMeraBalance,
            meraAmount,
            "Mera Capital wallet should receive correct amount"
        );
        
        // Check that agent received correct amount
        assertEq(token.balanceOf(mainAgent) - initialAgentBalance, agentAmount, "Agent should receive correct amount");

        vm.stopPrank();
    }

    function testIncreaseAgentPercentage() public {
        vm.startPrank(admin);

        uint256 newPercentage = 2500; // 25%
        profitDistributor.increaseAgentPercentage(newPercentage);

        assertEq(profitDistributor.agentPercentage(), newPercentage, "Agent percentage should be increased");

        vm.stopPrank();
    }

    function testIncreaseAgentPercentage_OnlyAdmin() public {
        vm.startPrank(mainAgent);

        uint256 newPercentage = 2500;
        vm.expectRevert();
        profitDistributor.increaseAgentPercentage(newPercentage);

        vm.stopPrank();
    }

    function testIncreaseAgentPercentage_MustBeIncreased() public {
        vm.startPrank(admin);

        // First set a higher percentage
        uint256 currentPercentage = 2500; // 25%
        profitDistributor.increaseAgentPercentage(currentPercentage);

        // Try to set a lower percentage
        uint256 newPercentage = 2200; // 22%
        vm.expectRevert(IAgentDistributionProfit.AgentPercentageCanOnlyIncrease.selector);
        profitDistributor.increaseAgentPercentage(newPercentage);

        vm.stopPrank();
    }

    function testIncreaseAgentPercentage_InvalidPercentage() public {
        vm.startPrank(admin);

        uint256 newPercentage = profitDistributor.MAX_AGENT_PERCENTAGE() + 100;
        vm.expectRevert(IAgentDistributionProfit.AgentPercentageOutOfRange.selector);
        profitDistributor.increaseAgentPercentage(newPercentage);

        vm.stopPrank();
    }

    function testApproveUpgrade() public {
        address newImplementation = address(new AgentDistributionProfit());

        vm.startPrank(admin);
        profitDistributor.approveUpgrade(newImplementation);

        assertEq(profitDistributor.adminApproved(), newImplementation, "Admin approved implementation should be set");
        assertEq(profitDistributor.adminApprovedTimestamp(), block.timestamp, "Admin approved timestamp should be set");

        vm.stopPrank();

        vm.startPrank(mainAgent);
        profitDistributor.approveUpgrade(newImplementation);

        assertEq(profitDistributor.agentApproved(), newImplementation, "Agent approved implementation should be set");
        assertEq(profitDistributor.agentApprovedTimestamp(), block.timestamp, "Agent approved timestamp should be set");

        vm.stopPrank();
    }

    function testApproveUpgrade_InvalidImplementation() public {
        vm.startPrank(admin);

        vm.expectRevert(IAgentDistributionProfit.InvalidUpgradeAddress.selector);
        profitDistributor.approveUpgrade(address(0));

        vm.stopPrank();
    }

    function testApproveUpgrade_OnlyAdminOrAgent() public {
        address newImplementation = address(new AgentDistributionProfit());

        vm.startPrank(user1);
        vm.expectRevert(IAgentDistributionProfit.AccessDenied.selector);
        profitDistributor.approveUpgrade(newImplementation);

        vm.stopPrank();
    }

    function testDistributeProfitMultipleTokens() public {
        vm.startPrank(admin);

        address[] memory tokens = new address[](2);
        tokens[0] = address(token);
        tokens[1] = address(secondToken);

        uint256 initialFundBalance1 = token.balanceOf(fundWallet);
        uint256 initialMeraBalance1 = token.balanceOf(meraCapitalWallet);
        uint256 initialAgentBalance1 = token.balanceOf(mainAgent);

        uint256 initialFundBalance2 = secondToken.balanceOf(fundWallet);
        uint256 initialMeraBalance2 = secondToken.balanceOf(meraCapitalWallet);
        uint256 initialAgentBalance2 = secondToken.balanceOf(mainAgent);

        profitDistributor.distributeProfit(tokens);

        uint256 agentAmount = INITIAL_BALANCE * profitDistributor.agentPercentage() / profitDistributor.MAX_PERCENTAGE();
        uint256 meraAmount =
            INITIAL_BALANCE * profitDistributor.MERA_CAPITAL_PERCENTAGE() / profitDistributor.MAX_PERCENTAGE();
        uint256 fundAmount = INITIAL_BALANCE - agentAmount - meraAmount;

        // Check first token distribution
        assertEq(
            token.balanceOf(fundWallet) - initialFundBalance1,
            fundAmount,
            "Fund wallet should receive correct amount of first token"
        );
        assertEq(
            token.balanceOf(meraCapitalWallet) - initialMeraBalance1,
            meraAmount,
            "Mera Capital wallet should receive correct amount of first token"
        );
        assertEq(
            token.balanceOf(mainAgent) - initialAgentBalance1,
            agentAmount,
            "Agent should receive correct amount of first token"
        );

        // Check second token distribution
        assertEq(
            secondToken.balanceOf(fundWallet) - initialFundBalance2,
            fundAmount,
            "Fund wallet should receive correct amount of second token"
        );
        assertEq(
            secondToken.balanceOf(meraCapitalWallet) - initialMeraBalance2,
            meraAmount,
            "Mera Capital wallet should receive correct amount of second token"
        );
        assertEq(
            secondToken.balanceOf(mainAgent) - initialAgentBalance2,
            agentAmount,
            "Agent should receive correct amount of second token"
        );

        vm.stopPrank();
    }

    function testSetFundWallet() public {
        address newFundWallet = address(123);

        vm.startPrank(admin);

        vm.expectEmit(true, true, false, true);
        emit FundWalletSet(admin, newFundWallet);
        profitDistributor.setFundWallet(newFundWallet);

        assertEq(profitDistributor.fundWallet(), newFundWallet, "Fund wallet should be updated");

        vm.stopPrank();
    }

    function testSetFundWallet_ZeroAddress() public {
        vm.startPrank(admin);

        vm.expectRevert(IAgentDistributionProfit.ZeroAddress.selector);
        profitDistributor.setFundWallet(address(0));

        vm.stopPrank();
    }

    function testSetFundWallet_OnlyAdmin() public {
        address newFundWallet = address(123);

        // Try with non-admin addresses
        vm.startPrank(user1);
        vm.expectRevert();
        profitDistributor.setFundWallet(newFundWallet);
        vm.stopPrank();

        vm.startPrank(mainAgent);
        vm.expectRevert();
        profitDistributor.setFundWallet(newFundWallet);
        vm.stopPrank();

        // Should work with admin
        vm.startPrank(admin);
        profitDistributor.setFundWallet(newFundWallet);
        assertEq(profitDistributor.fundWallet(), newFundWallet, "Admin should be able to set fund wallet");
        vm.stopPrank();
    }

    function testSetMeraCapitalWallet() public {
        address newMeraWallet = address(123);

        vm.startPrank(admin);

        vm.expectEmit(true, true, false, true);
        emit MeraCapitalWalletSet(admin, newMeraWallet);
        profitDistributor.setMeraCapitalWallet(newMeraWallet);

        assertEq(profitDistributor.meraCapitalWallet(), newMeraWallet, "Mera Capital wallet should be updated");

        vm.stopPrank();
    }

    function testSetMeraCapitalWallet_ZeroAddress() public {
        vm.startPrank(admin);

        vm.expectRevert(IAgentDistributionProfit.ZeroAddress.selector);
        profitDistributor.setMeraCapitalWallet(address(0));

        vm.stopPrank();
    }

    function testSetMeraCapitalWallet_OnlyAdmin() public {
        address newMeraWallet = address(123);

        // Try with non-admin addresses
        vm.startPrank(user1);
        vm.expectRevert();
        profitDistributor.setMeraCapitalWallet(newMeraWallet);
        vm.stopPrank();

        vm.startPrank(mainAgent);
        vm.expectRevert();
        profitDistributor.setMeraCapitalWallet(newMeraWallet);
        vm.stopPrank();

        // Should work with admin
        vm.startPrank(admin);
        profitDistributor.setMeraCapitalWallet(newMeraWallet);
        assertEq(
            profitDistributor.meraCapitalWallet(), newMeraWallet, "Admin should be able to set Mera Capital wallet"
        );
        vm.stopPrank();
    }

    function testSetFundWallet_UpdateExisting() public {
        address firstWallet = address(123);
        address secondWallet = address(456);

        vm.startPrank(admin);

        // Set first wallet
        profitDistributor.setFundWallet(firstWallet);
        assertEq(profitDistributor.fundWallet(), firstWallet, "First wallet should be set");

        // Set second wallet
        profitDistributor.setFundWallet(secondWallet);
        assertEq(profitDistributor.fundWallet(), secondWallet, "Second wallet should be set");

        vm.stopPrank();
    }

    function testSetMeraCapitalWallet_UpdateExisting() public {
        address firstWallet = address(123);
        address secondWallet = address(456);

        vm.startPrank(admin);

        // Set first wallet
        profitDistributor.setMeraCapitalWallet(firstWallet);
        assertEq(profitDistributor.meraCapitalWallet(), firstWallet, "First wallet should be set");

        // Set second wallet
        profitDistributor.setMeraCapitalWallet(secondWallet);
        assertEq(profitDistributor.meraCapitalWallet(), secondWallet, "Second wallet should be set");

        vm.stopPrank();
    }

    function testUpgradeImplementation() public {
        address newImplementation = address(new AgentDistributionProfit());

        // Approve by admin
        vm.startPrank(admin);
        profitDistributor.approveUpgrade(newImplementation);
        vm.stopPrank();

        // Approve by agent
        vm.startPrank(mainAgent);
        profitDistributor.approveUpgrade(newImplementation);
        vm.stopPrank();

        // Upgrade
        vm.startPrank(admin);
        vm.expectEmit(true, true, false, true);
        emit Upgraded(newImplementation);
        UUPSUpgradeable(address(profitDistributor)).upgradeToAndCall(newImplementation, "");
        vm.stopPrank();
    }

    function testUpgradeImplementation_ZeroAddress() public {
        // First approve some valid implementation to avoid time expiration error
        address validImplementation = address(new AgentDistributionProfit());

        vm.startPrank(admin);
        profitDistributor.approveUpgrade(validImplementation);
        vm.stopPrank();

        vm.startPrank(mainAgent);
        profitDistributor.approveUpgrade(validImplementation);
        vm.stopPrank();

        // Try to upgrade to zero address
        vm.startPrank(admin);
        vm.expectRevert(IAgentDistributionProfit.InvalidUpgradeAddress.selector);
        UUPSUpgradeable(address(profitDistributor)).upgradeToAndCall(address(0), "");
        vm.stopPrank();
    }

    function testUpgradeImplementation_TimeExpired() public {
        address newImplementation = address(new AgentDistributionProfit());

        // Approve by admin
        vm.startPrank(admin);
        profitDistributor.approveUpgrade(newImplementation);
        vm.stopPrank();

        // Approve by agent
        vm.startPrank(mainAgent);
        profitDistributor.approveUpgrade(newImplementation);
        vm.stopPrank();

        // Move time forward past the time limit
        vm.warp(block.timestamp + profitDistributor.UPGRADE_TIME_LIMIT() + 1);

        // Try to upgrade after time expired
        vm.startPrank(admin);
        vm.expectRevert(IAgentDistributionProfit.UpgradeDeadlineExpired.selector);
        UUPSUpgradeable(address(profitDistributor)).upgradeToAndCall(newImplementation, "");
        vm.stopPrank();
    }

    function testUpgradeImplementation_RequiresBothApprovals() public {
        address newImplementation = address(new AgentDistributionProfit());

        // Only agent approves (new implementation)
        vm.startPrank(mainAgent);
        profitDistributor.approveUpgrade(newImplementation);
        vm.warp(block.timestamp + profitDistributor.UPGRADE_TIME_LIMIT() + 1);

        // Only admin approves
        vm.startPrank(admin);
        profitDistributor.approveUpgrade(newImplementation);
        vm.warp(block.timestamp + profitDistributor.UPGRADE_TIME_LIMIT() + 1);

        // Try to upgrade with only agent approval
        vm.expectRevert(IAgentDistributionProfit.UpgradeDeadlineExpired.selector);
        UUPSUpgradeable(address(profitDistributor)).upgradeToAndCall(newImplementation, "");
        vm.stopPrank();
    }

    function testUpgradeImplementation_OnlyAdminOrAgentCanUpgrade() public {
        address newImplementation = address(new AgentDistributionProfit());

        // Approve by both roles
        vm.startPrank(admin);
        profitDistributor.approveUpgrade(newImplementation);
        vm.stopPrank();

        vm.startPrank(mainAgent);
        profitDistributor.approveUpgrade(newImplementation);
        vm.stopPrank();

        // Try to upgrade from unauthorized address
        vm.startPrank(user1);
        vm.expectRevert(IAgentDistributionProfit.AccessDenied.selector);
        UUPSUpgradeable(address(profitDistributor)).upgradeToAndCall(newImplementation, "");
        vm.stopPrank();
    }

    function testUpgradeImplementation_SameImplementationAsAgentApproved() public {
        address newImplementation = address(new AgentDistributionProfit());

        // Then approve by admin
        vm.startPrank(admin);
        profitDistributor.approveUpgrade(newImplementation);

        // Try to upgrade with the same implementation
        vm.expectRevert(IAgentDistributionProfit.ImplementationNotApprovedByAgent.selector);
        UUPSUpgradeable(address(profitDistributor)).upgradeToAndCall(newImplementation, "");
        vm.stopPrank();
    }

    function testUpgradeImplementation_SameImplementationAsAdminApproved() public {
        address newImplementation = address(new AgentDistributionProfit());
        vm.startPrank(mainAgent);
        profitDistributor.approveUpgrade(newImplementation);
        vm.stopPrank();

        // Then approve by admin
        vm.startPrank(admin);

        // Try to upgrade with the same implementation
        vm.expectRevert(IAgentDistributionProfit.ImplementationNotApprovedByAdmin.selector);
        UUPSUpgradeable(address(profitDistributor)).upgradeToAndCall(newImplementation, "");
        vm.stopPrank();
    }

    function testGrantRole_RevokeRoleFails() public {
        // Deploy mock contract that always returns false for _revokeRole
        AgentDistributionProfitMockRevokeRole mockImpl = new AgentDistributionProfitMockRevokeRole();

        // Initialize with same params as main contract
        bytes memory initData = abi.encodeWithSelector(
            AgentDistributionProfit.initialize.selector,
            fundWallet,
            mainAgent,
            admin,
            emergencyAdmin,
            backupAdmin,
            emergencyAgent,
            backupAgent,
            meraCapitalWallet
        );

        ERC1967Proxy mockProxy = new ERC1967Proxy(address(mockImpl), initData);
        AgentDistributionProfitMockRevokeRole mockDistributor =
            AgentDistributionProfitMockRevokeRole(address(mockProxy));

        // Get role from mock instance
        bytes32 mainAgentRole = mockDistributor.MAIN_AGENT_ROLE();

        // Try to grant role to new user
        vm.prank(emergencyAgent);
        mockDistributor.grantRole(mainAgentRole, user1);

        // Check that original role holder still has role and new user does not
        assertFalse(mockDistributor.hasRole(mainAgentRole, mainAgent), "Original role holder should not have role");
        assertTrue(mockDistributor.hasRole(mainAgentRole, user1), "New user should have role");
    }

    function testInitialize_ZeroAddresses() public {
        // Test each zero address parameter
        address[] memory zeroAddresses = new address[](8);
        zeroAddresses[0] = address(0); // fundWallet
        zeroAddresses[1] = mainAgent; // agentWallet
        zeroAddresses[2] = admin; // adminWallet
        zeroAddresses[3] = emergencyAdmin; // emergencyAdminWallet
        zeroAddresses[4] = backupAdmin; // reserveAdminWallet
        zeroAddresses[5] = emergencyAgent; // emergencyAgentWallet
        zeroAddresses[6] = backupAgent; // reserveAgentWallet
        zeroAddresses[7] = meraCapitalWallet; // meraCapitalWallet

        for (uint256 i = 0; i < 8; i++) {
            address[] memory addresses = new address[](8);
            for (uint256 j = 0; j < 8; j++) {
                addresses[j] = j == i
                    ? address(0)
                    : (
                        j == 0
                            ? fundWallet
                            : j == 1
                                ? mainAgent
                                : j == 2
                                    ? admin
                                    : j == 3
                                        ? emergencyAdmin
                                        : j == 4 ? backupAdmin : j == 5 ? emergencyAgent : j == 6 ? backupAgent : meraCapitalWallet
                    );
            }

            bytes memory initData = abi.encodeWithSelector(
                AgentDistributionProfit.initialize.selector,
                addresses[0], // fundWallet
                addresses[1], // agentWallet
                addresses[2], // adminWallet
                addresses[3], // emergencyAdminWallet
                addresses[4], // reserveAdminWallet
                addresses[5], // emergencyAgentWallet
                addresses[6], // reserveAgentWallet
                addresses[7] // meraCapitalWallet
            );

            vm.expectRevert(IAgentDistributionProfit.ZeroAddress.selector);
            new ERC1967Proxy(address(implementation), initData);
        }
    }

    function testDistributeProfit_EmptyTokensArray() public {
        vm.startPrank(admin);

        address[] memory emptyTokens = new address[](0);
        // Empty array should not revert, just do nothing
        profitDistributor.distributeProfit(emptyTokens);

        vm.stopPrank();
    }

    function testDistributeProfit_InvalidToken() public {
        vm.startPrank(admin);

        address[] memory tokens = new address[](1);
        tokens[0] = address(0); // Invalid token address

        vm.expectRevert();
        profitDistributor.distributeProfit(tokens);

        vm.stopPrank();
    }

    function testDistributeProfit_NoBalance() public {
        vm.startPrank(admin);

        // Create new token with no balance in distributor
        MockERC20 newToken = new MockERC20();

        address[] memory tokens = new address[](1);
        tokens[0] = address(newToken);

        // Should not revert but also not transfer any tokens
        uint256 initialFundBalance = newToken.balanceOf(fundWallet);
        uint256 initialMeraBalance = newToken.balanceOf(meraCapitalWallet);
        uint256 initialAgentBalance = newToken.balanceOf(mainAgent);

        profitDistributor.distributeProfit(tokens);

        assertEq(newToken.balanceOf(fundWallet), initialFundBalance, "Fund wallet balance should not change");
        assertEq(
            newToken.balanceOf(meraCapitalWallet), initialMeraBalance, "Mera Capital wallet balance should not change"
        );
        assertEq(newToken.balanceOf(mainAgent), initialAgentBalance, "Agent balance should not change");

        vm.stopPrank();
    }

    function testDistributeProfit_Unauthorized() public {
        vm.startPrank(user1); // Non-admin, non-agent user

        address[] memory tokens = new address[](1);
        tokens[0] = address(token);

        vm.expectRevert(IAgentDistributionProfit.AccessDenied.selector);
        profitDistributor.distributeProfit(tokens);

        vm.stopPrank();
    }

    function testIncreaseAgentPercentage_Unauthorized() public {
        vm.startPrank(user1); // Non-agent user

        uint256 newPercentage = 2500; // 25%
        vm.expectRevert();
        profitDistributor.increaseAgentPercentage(newPercentage);

        vm.stopPrank();
    }

    function testIncreaseAgentPercentage_BelowMinimum() public {
        vm.startPrank(admin);

        uint256 belowMinimum = profitDistributor.MIN_AGENT_PERCENTAGE() - 100;
        vm.expectRevert(IAgentDistributionProfit.AgentPercentageOutOfRange.selector);
        profitDistributor.increaseAgentPercentage(belowMinimum);

        vm.stopPrank();
    }

    function testIncreaseAgentPercentage_AboveMaximum() public {
        vm.startPrank(admin);

        uint256 aboveMaximum = profitDistributor.MAX_AGENT_PERCENTAGE() + 100;
        vm.expectRevert(IAgentDistributionProfit.AgentPercentageOutOfRange.selector);
        profitDistributor.increaseAgentPercentage(aboveMaximum);

        vm.stopPrank();
    }

    function testSetFundWallet_Unauthorized() public {
        vm.startPrank(user1); // Non-admin user

        address newFundWallet = address(123);
        vm.expectRevert();
        profitDistributor.setFundWallet(newFundWallet);

        vm.stopPrank();
    }

    function testSetMeraCapitalWallet_Unauthorized() public {
        vm.startPrank(user1); // Non-admin user

        address newMeraWallet = address(123);
        vm.expectRevert();
        profitDistributor.setMeraCapitalWallet(newMeraWallet);

        vm.stopPrank();
    }

    function testApproveUpgrade_Unauthorized() public {
        vm.startPrank(user1); // Non-admin, non-agent user

        address newImplementation = address(new AgentDistributionProfit());
        vm.expectRevert(IAgentDistributionProfit.AccessDenied.selector);
        profitDistributor.approveUpgrade(newImplementation);

        vm.stopPrank();
    }

    function testApproveUpgrade_ZeroAddress() public {
        vm.startPrank(admin);

        vm.expectRevert(IAgentDistributionProfit.InvalidUpgradeAddress.selector);
        profitDistributor.approveUpgrade(address(0));

        vm.stopPrank();
    }

    function testUpgradeImplementation_NoApprovals() public {
        address newImplementation = address(new AgentDistributionProfit());

        vm.startPrank(admin);
        vm.expectRevert(IAgentDistributionProfit.ImplementationNotApprovedByAdmin.selector);
        UUPSUpgradeable(address(profitDistributor)).upgradeToAndCall(newImplementation, "");

        vm.stopPrank();
    }

    function testUpgradeImplementation_OnlyAdminApproval() public {
        address newImplementation = address(new AgentDistributionProfit());

        // Only admin approves
        vm.startPrank(admin);
        profitDistributor.approveUpgrade(newImplementation);

        vm.expectRevert(IAgentDistributionProfit.ImplementationNotApprovedByAgent.selector);
        UUPSUpgradeable(address(profitDistributor)).upgradeToAndCall(newImplementation, "");

        vm.stopPrank();
    }

    function testUpgradeImplementation_OnlyAgentApproval() public {
        address newImplementation = address(new AgentDistributionProfit());

        // Only agent approves
        vm.startPrank(mainAgent);
        profitDistributor.approveUpgrade(newImplementation);

        vm.startPrank(admin);
        vm.expectRevert(IAgentDistributionProfit.ImplementationNotApprovedByAdmin.selector);
        UUPSUpgradeable(address(profitDistributor)).upgradeToAndCall(newImplementation, "");

        vm.stopPrank();
    }

    function testUpgradeImplementation_DifferentImplementations() public {
        address adminImpl = address(new AgentDistributionProfit());
        address agentImpl = address(new AgentDistributionProfit());

        // Admin and agent approve different implementations
        vm.startPrank(admin);
        profitDistributor.approveUpgrade(adminImpl);
        vm.stopPrank();

        vm.startPrank(mainAgent);
        profitDistributor.approveUpgrade(agentImpl);
        vm.stopPrank();

        vm.startPrank(admin);
        vm.expectRevert(IAgentDistributionProfit.ImplementationNotApprovedByAgent.selector);
        UUPSUpgradeable(address(profitDistributor)).upgradeToAndCall(adminImpl, "");

        vm.stopPrank();
    }

    function testUpgradeImplementation_ExpiredApprovals() public {
        address newImplementation = address(new AgentDistributionProfit());

        // Both approve
        vm.startPrank(admin);
        profitDistributor.approveUpgrade(newImplementation);
        vm.stopPrank();

        vm.startPrank(mainAgent);
        profitDistributor.approveUpgrade(newImplementation);
        vm.stopPrank();

        // Move time forward past the time limit
        vm.warp(block.timestamp + profitDistributor.UPGRADE_TIME_LIMIT() + 1);

        vm.startPrank(admin);
        vm.expectRevert(IAgentDistributionProfit.UpgradeDeadlineExpired.selector);
        UUPSUpgradeable(address(profitDistributor)).upgradeToAndCall(newImplementation, "");

        vm.stopPrank();
    }

    function testUpgradeImplementation_AgentApprovalExpired() public {
        address newImplementation = address(new AgentDistributionProfit());

        // Only agent approves
        vm.startPrank(mainAgent);
        profitDistributor.approveUpgrade(newImplementation);

        // Move time forward past the time limit
        vm.warp(block.timestamp + profitDistributor.UPGRADE_TIME_LIMIT() + 1);

        // Admin approves after agent approval expired
        vm.startPrank(admin);
        profitDistributor.approveUpgrade(newImplementation);

        // Try to upgrade
        vm.expectRevert(IAgentDistributionProfit.UpgradeDeadlineExpired.selector);
        UUPSUpgradeable(address(profitDistributor)).upgradeToAndCall(newImplementation, "");

        vm.stopPrank();
    }
}
