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

        address[] memory assets;
        address[] memory sources;
        uint8[] memory decimals;

        // Polygon mainnet
        if (block.chainid == 137) {
            assets = new address[](10);
            assets[0] = address(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174); // USDC.e
            assets[1] = address(0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6); // WBTC
            assets[2] = address(0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619); // WETH
            assets[3] = address(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270); // WPOL
            assets[4] = address(0xc2132D05D31c914a87C6611C10748AEb04B58e8F); // USDT
            assets[5] = address(0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063); // DAI
            assets[6] = address(0xD6DF932A45C0f255f85145f286eA0b292B21C90B); // AAVE
            assets[7] = address(0x53E0bca35eC356BD5ddDFebbD1Fc0fD03FaBad39); // LINK
            assets[8] = address(0xd93f7E271cB87c23AaA73edC008A79646d1F9912); // SOL
            assets[9] = address(0xb33EaAd8d922B1083446DC23f610c2567fB5180f); // UNI

            sources = new address[](10);
            sources[0] = address(0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7); // USDC/USD
            sources[1] = address(0xDE31F8bFBD8c84b5360CFACCa3539B938dd78ae6); // WBTC/USD
            sources[2] = address(0xF9680D99D6C9589e2a93a78A04A279e509205945); // ETH/USD
            sources[3] = address(0xAB594600376Ec9fD91F8e885dADF0CE036862dE0); // MATIC/USD
            sources[4] = address(0x0A6513e40db6EB1b165753AD52E80663aeA50545); // USDT/USD
            sources[5] = address(0x4746DeC9e833A82EC7C2C1356372CcF2cfcD2F3D); // DAI/USD
            sources[6] = address(0x72484B12719E23115761D5DA1646945632979bB6); // AAVE/USD
            sources[7] = address(0xd9FFdb71EbE7496cC440152d43986Aae0AB76665); // LINK/USD
            sources[8] = address(0x10C8264C0935b3B9870013e057f330Ff3e9C56dC); // SOL/USD
            sources[9] = address(0xdf0Fb4e4F928d2dCB76f438575fDD8682386e13C); // UNI/USD

            decimals = new uint8[](10);
            decimals[0] = 8; // USDC/USD
            decimals[1] = 8; // WBTC/USD
            decimals[2] = 8; // ETH/USD
            decimals[3] = 8; // MATIC/USD
            decimals[4] = 8; // USDT/USD
            decimals[5] = 8; // DAI/USD
            decimals[6] = 8; // AAVE/USD
            decimals[7] = 8; // LINK/USD
            decimals[8] = 8; // SOL/USD
            decimals[9] = 8; // UNI/USD
        }
        // Base mainnet
        else if (block.chainid == 8453) {
            assets = new address[](5);
            assets[0] = address(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913); // USDC
            assets[1] = address(0x4200000000000000000000000000000000000006); // WETH
            assets[2] = address(0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2); // USDT
            assets[3] = address(0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf); // cbBTC
            assets[4] = address(0x0b3e328455c4059EEb9e3f84b5543F74E24e7E1b); // VIRTUAL

            sources = new address[](5);
            sources[0] = address(0x7e860098F58bBFC8648a4311b374B1D669a2bc6B); // USDC/USD
            sources[1] = address(0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70); // ETH/USD
            sources[2] = address(0xf19d560eB8d2ADf07BD6D13ed03e1D11215721F9); // USDT/USD
            sources[3] = address(0x64c911996D3c6aC71f9b455B1E8E7266BcbD848F); // BTC/USD
            sources[4] = address(0xEaf310161c9eF7c813A14f8FEF6Fb271434019F7); // VIRTUAL/USD

            decimals = new uint8[](5);
            decimals[0] = 8; // USDC/USD
            decimals[1] = 8; // ETH/USD
            decimals[2] = 8; // USDT/USD
            decimals[3] = 8; // BTC/USD
            decimals[4] = 8; // VIRTUAL/USD
        }

        address fallbackOracle = address(0x0);

        // Deploy MeraPriceOracle
        MeraPriceOracle meraPriceOracle = new MeraPriceOracle(assets, sources, decimals, fallbackOracle);
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
