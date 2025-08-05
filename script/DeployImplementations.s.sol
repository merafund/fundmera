// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 fundmera.com

// https://github.com/merafund
pragma solidity ^0.8.29;

import {Script, console} from "forge-std/Script.sol";
import {MainVault} from "../src/MainVault.sol";
import {InvestmentVault} from "../src/InvestmentVault.sol";
import {AgentDistributionProfit} from "../src/AgentDistributionProfit.sol";

/**
 * @title DeployImplementationsScript
 * @dev Script for deploying new implementations without updating them in the Factory
 */
contract DeployImplementationsScript is Script {
    // New implementations that will be deployed
    MainVault public newMainVaultImpl;
    InvestmentVault public newInvestmentVaultImpl;
    AgentDistributionProfit public newAgentDistributionImpl;

    // Flags to control which implementations to deploy
    bool public deployMainVault;
    bool public deployInvestmentVault;
    bool public deployAgentDistribution;

    function setUp() public {
        // Get deployment flags from environment (default to true if not set)
        deployMainVault = vm.envOr("DEPLOY_MAIN_VAULT", true);
        deployInvestmentVault = vm.envOr("DEPLOY_INVESTMENT_VAULT", true);
        deployAgentDistribution = vm.envOr("DEPLOY_AGENT_DISTRIBUTION", true);
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console.log("=== Deploying New Implementations ===");

        // Deploy new implementations based on flags
        address newMainVaultAddr = address(0);
        address newInvestmentVaultAddr = address(0);
        address newAgentDistributionAddr = address(0);

        if (deployMainVault) {
            console.log("Deploying new MainVault implementation...");
            newMainVaultImpl = new MainVault();
            newMainVaultAddr = address(newMainVaultImpl);
            console.log("New MainVault implementation deployed at:", newMainVaultAddr);
        } else {
            console.log("Skipping MainVault deployment");
        }

        if (deployInvestmentVault) {
            console.log("Deploying new InvestmentVault implementation...");
            newInvestmentVaultImpl = new InvestmentVault();
            newInvestmentVaultAddr = address(newInvestmentVaultImpl);
            console.log("New InvestmentVault implementation deployed at:", newInvestmentVaultAddr);
        } else {
            console.log("Skipping InvestmentVault deployment");
        }

        if (deployAgentDistribution) {
            console.log("Deploying new AgentDistribution implementation...");
            newAgentDistributionImpl = new AgentDistributionProfit();
            newAgentDistributionAddr = address(newAgentDistributionImpl);
            console.log("New AgentDistribution implementation deployed at:", newAgentDistributionAddr);
        } else {
            console.log("Skipping AgentDistribution deployment");
        }

        // Wait for 5 seconds before ending
        vm.sleep(5000);
        vm.stopBroadcast();

        console.log("\n=== Summary ===");
        if (deployMainVault) {
            console.log("[ DEPLOYED ] MainVault implementation at:", newMainVaultAddr);
        }
        if (deployInvestmentVault) {
            console.log("[ DEPLOYED ] InvestmentVault implementation at:", newInvestmentVaultAddr);
        }
        if (deployAgentDistribution) {
            console.log("[ DEPLOYED ] AgentDistribution implementation at:", newAgentDistributionAddr);
        }
        console.log("All implementations successfully deployed!");
        console.log("\nNote: These implementations are NOT automatically updated in any Factory.");
        console.log("To update them in a Factory, use the UpdateImplementations script.");
    }
}
