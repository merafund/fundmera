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
import {Factory, IFactory} from "../src/Factory.sol";
import {AgentDistributionProfit} from "../src/AgentDistributionProfit.sol";
import {PauserList} from "../src/PauserList.sol";
import {MeraPriceOracle} from "../src/MeraPriceOracle.sol";
import {NetworkConfig} from "../src/utils/NetworkConfig.sol";

/**
 * @title FactoryScript
 * @dev Script for deploying Factory with all required parameters
 */
contract FactoryScript is Script {
    address manager;
    address admin;
    address backupAdmin;
    address emergencyAdmin;
    uint256 feePercentage;
    address fundWallet;
    address defaultAgentWallet;
    address meraCapitalWallet;
    address newFactoryOwner;
    address factoryAgentDeployer;

    function setUp() public {
        manager = vm.envOr("MANAGER", address(0x4));
        admin = vm.envOr("ADMIN", address(0x5));
        backupAdmin = vm.envOr("BACKUP_ADMIN", address(0x6));
        emergencyAdmin = vm.envOr("EMERGENCY_ADMIN", address(0x7));
        feePercentage = vm.envOr("FEE_PERCENTAGE", uint256(1000)); // 10% by default
        fundWallet = vm.envOr("FUND_WALLET", address(0x8));
        defaultAgentWallet = vm.envOr("DEFAULT_AGENT_WALLET", address(0x9));
        meraCapitalWallet = vm.envOr("MERA_CAPITAL_WALLET", address(0x10));
        newFactoryOwner = vm.envOr("NEW_FACTORY_OWNER", address(0x11));
        factoryAgentDeployer = vm.envOr("FACTORY_AGENT_DEPLOYER", address(0x12));
    }

    function run() public {
        // Get environment variables with default values if not set

        vm.startBroadcast();

        // Deploy MainVault implementation
        MainVault mainVaultImpl = new MainVault();
        console.log("MainVault implementation deployed at:", address(mainVaultImpl));

        // Deploy InvestmentVault implementation
        InvestmentVault investmentVaultImpl = new InvestmentVault();
        console.log("InvestmentVault implementation deployed at:", address(investmentVaultImpl));

        // Deploy AgentDistributionProfit implementation
        AgentDistributionProfit agentDistributionImpl = new AgentDistributionProfit();
        console.log("AgentDistributionProfit implementation deployed at:", address(agentDistributionImpl));

        // Deploy PauserList separately
        PauserList pauserList = new PauserList(admin);
        console.log("PauserList deployed at:", address(pauserList));

        // Get network configuration for current chain
        NetworkConfig.NetworkAssets memory config = NetworkConfig.getNetworkConfig(block.chainid);
        require(config.assets.length > 0, "No configuration found for current network");

        console.log("Using network configuration for chain ID:", block.chainid);
        console.log("Number of configured assets:", config.assets.length);

        address fallbackOracle = address(0x0);

        // Deploy MeraPriceOracle
        MeraPriceOracle meraPriceOracle =
            new MeraPriceOracle(config.assets, config.sources, config.decimals, fallbackOracle);
        console.log("MeraPriceOracle deployed at:", address(meraPriceOracle));

        // Prepare constructor parameters
        IFactory.ConstructorParams memory params = IFactory.ConstructorParams({
            mainVaultImplementation: address(mainVaultImpl),
            investmentVaultImplementation: address(investmentVaultImpl),
            manager: manager,
            admin: admin,
            backupAdmin: backupAdmin,
            emergencyAdmin: emergencyAdmin,
            feePercentage: feePercentage,
            pauserList: address(pauserList),
            agentDistributionImplementation: address(agentDistributionImpl),
            fundWallet: fundWallet,
            defaultAgentWallet: defaultAgentWallet,
            meraCapitalWallet: meraCapitalWallet,
            meraPriceOracle: address(meraPriceOracle)
        });

        // Deploy Factory
        Factory factory = new Factory(params);
        factory.setDeployer(factoryAgentDeployer);
        //factory.transferOwnership(newFactoryOwner);
        //meraPriceOracle.transferOwnership(newFactoryOwner);

        console.log("Factory deployed at:", address(factory));

        // Wait for 5 seconds before ending
        vm.sleep(5000);
        vm.stopBroadcast();

        console.log("Factory configuration:");
        console.log("- Manager:          ", manager);
        console.log("- Admin:            ", admin);
        console.log("- Backup Admin:     ", backupAdmin);
        console.log("- Emergency Admin:  ", emergencyAdmin);
        console.log("- Fee Percentage:   ", feePercentage);
        console.log("- Fund Wallet:      ", fundWallet);
        console.log("- Default Agent:    ", defaultAgentWallet);
        console.log("- MainVault Impl:   ", address(mainVaultImpl));
        console.log("- InvestmentVault Impl:", address(investmentVaultImpl));
        console.log("- AgentDistribution Impl:", address(agentDistributionImpl));
        console.log("- PauserList:       ", address(pauserList));
    }
}
