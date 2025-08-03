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
            assets[5] = address(0x60a3E35Cc302bFA44Cb288Bc5a4F316Fdb1adb42); // EURC

            sources = new address[](5);
            sources[0] = address(0x7e860098F58bBFC8648a4311b374B1D669a2bc6B); // USDC/USD
            sources[1] = address(0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70); // ETH/USD
            sources[2] = address(0xf19d560eB8d2ADf07BD6D13ed03e1D11215721F9); // USDT/USD
            sources[3] = address(0x64c911996D3c6aC71f9b455B1E8E7266BcbD848F); // BTC/USD
            sources[4] = address(0xEaf310161c9eF7c813A14f8FEF6Fb271434019F7); // VIRTUAL/USD
            sources[5] = address(0xDAe398520e2B67cd3f27aeF9Cf14D93D927f8250); // EURC/USD

            decimals = new uint8[](5);
            decimals[0] = 8; // USDC/USD
            decimals[1] = 8; // ETH/USD
            decimals[2] = 8; // USDT/USD
            decimals[3] = 8; // BTC/USD
            decimals[4] = 8; // VIRTUAL/USD
            decimals[5] = 8; // EURC/USD
        }
        // Arbitrum mainnet
        else if (block.chainid == 42161) {
            assets = new address[](7);
            assets[0] = address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831); // USDC
            assets[1] = address(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f); // WBTC
            assets[2] = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1); // WETH
            assets[3] = address(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9); // USDT
            assets[4] = address(0x912CE59144191C1204E64559FE8253a0e49E6548); // ARB
            assets[5] = address(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1); // DAI
            assets[6] = address(0xba5DdD1f9d7F570dc94a51479a000E3BCE967196); // AAVE

            sources = new address[](7);
            sources[0] = address(0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3); // USDC/USD
            sources[1] = address(0x6ce185860a4963106506C203335A2910413708e9); // BTC/USD (for WBTC)
            sources[2] = address(0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612); // ETH/USD
            sources[3] = address(0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7); // USDT/USD
            sources[4] = address(0xb2A824043730FE05F3DA2efaFa1CBbe83fa548D6); // ARB/USD
            sources[5] = address(0xc5C8E77B397E531B8EC06BFb0048328B30E9eCfB); // DAI/USD
            sources[6] = address(0xaD1d5344AaDE45F43E596773Bcc4c423EAbdD034); // AAVE/USD

            decimals = new uint8[](7);
            decimals[0] = 8; // USDC/USD
            decimals[1] = 8; // BTC/USD
            decimals[2] = 8; // ETH/USD
            decimals[3] = 8; // USDT/USD
            decimals[4] = 8; // ARB/USD
            decimals[5] = 8; // DAI/USD
            decimals[6] = 8; // AAVE/USD
        }
        // BSC mainnet
        else if (block.chainid == 56) {
            assets = new address[](11);
            assets[0] = address(0x8d0D000Ee44948FC98c9B98A4FA4921476f08B0d); // USD1
            assets[1] = address(0x55d398326f99059fF775485246999027B3197955); // USDT
            assets[2] = address(0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d); // USDC
            assets[3] = address(0x1AF3F329e8BE154074D8769D1FFa4eE058B1DBc3); // DAI
            assets[4] = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c); // WBNB
            assets[5] = address(0x2170Ed0880ac9A755fd29B2688956BD959F933F8); // WETH
            assets[6] = address(0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c); // BTCB
            assets[7] = address(0x1D2F0da169ceB9fC7B3144628dB156f3F6c60dBE); // XRP
            assets[8] = address(0x570A5D26f7765Ecb712C0924E4De545B89fD43dF); // SOL
            assets[9] = address(0xbA2aE424d960c26247Dd6c32edC70B295c744C43); // DOGE
            assets[10] = address(0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82); // CAKE

            sources = new address[](11);
            sources[0] = address(0xaD8b4e59A7f25B68945fAf0f3a3EAF027832FFB0); // USD1/USD
            sources[1] = address(0xB97Ad0E74fa7d920791E90258A6E2085088b4320); // USDT/USD
            sources[2] = address(0x51597f405303C4377E36123cBc172b13269EA163); // USDC/USD
            sources[3] = address(0x132d3C0B1D2cEa0BC552588063bdBb210FDeecfA); // DAI/USD
            sources[4] = address(0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE); // BNB/USD
            sources[5] = address(0x9ef1B8c0E4F7dc8bF5719Ea496883DC6401d5b2e); // ETH/USD
            sources[6] = address(0x264990fbd0A4796A3E3d8E37C4d5F87a3aCa5Ebf); // BTC/USD
            sources[7] = address(0x93A67d414896a280Bf8Ffb6e7f51645503c1d358); // XRP/USD
            sources[8] = address(0x0E8a53DD9c13589df6382F13dA6B3Ec8F919B323); // SOL/USD
            sources[9] = address(0x3AB0A0d137D4F946fBB19eecc6e92E64660231C8); // DOGE/USD
            sources[10] = address(0xB6064eD41d4f67e353768aA239cA86f4F73665a1); // CAKE/USD

            decimals = new uint8[](11);
            decimals[0] = 8; // USD1/USD
            decimals[1] = 8; // USDT/USD
            decimals[2] = 8; // USDC/USD
            decimals[3] = 8; // DAI/USD
            decimals[4] = 8; // BNB/USD
            decimals[5] = 8; // ETH/USD
            decimals[6] = 8; // BTC/USD
            decimals[7] = 8; // XRP/USD
            decimals[8] = 8; // SOL/USD
            decimals[9] = 8; // DOGE/USD
            decimals[10] = 8; // CAKE/USD
        }
        // Ethereum mainnet
        else if (block.chainid == 1) {
            assets = new address[](13);
            assets[0] = address(0xdAC17F958D2ee523a2206206994597C13D831ec7); // USDT
            assets[1] = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); // USDC
            assets[2] = address(0x4c9EDD5852cd905f086C759E8383e09bff1E68B3); // USDe
            assets[3] = address(0x1aBaEA1f7C830bD89Acc67eC4af516284b1bC33c); // EURC
            assets[4] = address(0x6B175474E89094C44Da98b954EedeAC495271d0F); // DAI
            assets[5] = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // WETH
            // assets[6] = address(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0); // wstETH
            assets[6] = address(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599); // WBTC
            assets[7] = address(0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf); // cbBTC
            assets[8] = address(0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984); // UNI
            assets[9] = address(0x514910771AF9Ca656af840dff83E8264EcF986CA); // LINK
            assets[10] = address(0xD31a59c85aE9D8edEFeC411D448f90841571b89c); // SOL
            assets[11] = address(0x8d0D000Ee44948FC98c9B98A4FA4921476f08B0d); // USD1

            sources = new address[](13);
            sources[0] = address(0x3E7d1eAB13ad0104d2750B8863b489D65364e32D); // USDT/USD
            sources[1] = address(0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6); // USDC/USD
            sources[2] = address(0xa569d910839Ae8865Da8F8e70FfFb0cBA869F961); // USDe/USD
            sources[3] = address(0x04F84020Fdf10d9ee64D1dcC2986EDF2F556DA11); // EURC/USD
            sources[4] = address(0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9); // DAI/USD
            sources[5] = address(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419); // ETH/USD
            // sources[6] = address(0x164C5B1682E4e4b52B08a03ADd5F7Cae6A625E5a); // wstETH/USD
            sources[6] = address(0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c); // BTC/USD (for WBTC)
            sources[7] = address(0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c); // BTC/USD (for cbBTC)
            sources[8] = address(0x553303d460EE0afB37EdFf9bE42922D8FF63220e); // UNI/USD
            sources[9] = address(0x2c1d072e956AFFC0D435Cb7AC38EF18d24d9127c); // LINK/USD
            sources[10] = address(0x4ffC43a60e009B551865A93d232E33Fce9f01507); // SOL/USD
            sources[11] = address(0xF0d9bb015Cd7BfAb877B7156146dc09Bf461370d); // USD1/USD

            decimals = new uint8[](13);
            decimals[0] = 8; // USDT/USD
            decimals[1] = 8; // USDC/USD
            decimals[2] = 8; // USDe/USD
            decimals[3] = 8; // EURC/USD
            decimals[4] = 8; // DAI/USD
            decimals[5] = 8; // ETH/USD
            // decimals[6] = 8; // wstETH/USD
            decimals[6] = 8; // BTC/USD
            decimals[7] = 8; // BTC/USD
            decimals[8] = 8; // UNI/USD
            decimals[9] = 8; // LINK/USD
            decimals[10] = 8; // SOL/USD
            decimals[11] = 8; // USD1/USD
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
