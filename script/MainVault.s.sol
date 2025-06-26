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
import {IMainVault} from "../src/interfaces/IMainVault.sol";
import {PauserList} from "../src/PauserList.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {MeraPriceOracle} from "../src/MeraPriceOracle.sol";

/**
 * @title MainVaultScript
 * @dev Script for deploying MainVault and InvestmentVault using OpenZeppelin Upgrades
 */
contract MainVaultScript is Script {
    MainVault public mainVaultImpl;
    InvestmentVault public investmentVaultImpl;
    PauserList public pauserList;
    MeraPriceOracle public meraPriceOracle;

    address public mainVaultProxy;
    address public mainVault;

    address public mainInvestor;
    address public backupInvestor;
    address public emergencyInvestor;
    address public manager;
    address public admin;
    address public backupAdmin;
    address public emergencyAdmin;
    address public feeWallet;
    address public profitWallet;
    uint256 public feePercentage;

    function setUp() public {
        mainInvestor = vm.envOr("MAIN_INVESTOR", address(0x1));
        backupInvestor = vm.envOr("BACKUP_INVESTOR", address(0x2));
        emergencyInvestor = vm.envOr("EMERGENCY_INVESTOR", address(0x3));
        manager = vm.envOr("MANAGER", address(0x4));
        admin = vm.envOr("ADMIN", address(0x5));
        backupAdmin = vm.envOr("BACKUP_ADMIN", address(0x6));
        emergencyAdmin = vm.envOr("EMERGENCY_ADMIN", address(0x7));
        feeWallet = vm.envOr("FEE_WALLET", address(0x8));
        profitWallet = vm.envOr("PROFIT_WALLET", address(0x9));
        feePercentage = vm.envOr("FEE_PERCENTAGE", uint256(1000)); // 10% по умолчанию
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy InvestmentVault implementation
        investmentVaultImpl = new InvestmentVault();
        console.log("InvestmentVault implementation deployed at:", address(investmentVaultImpl));

        // Deploy PauserList with admin as initial admin
        pauserList = new PauserList(admin);
        console.log("PauserList deployed at:", address(pauserList));

        address[] memory assets = new address[](2);
        assets[0] = address(0x1);
        assets[1] = address(0x2);

        address[] memory sources = new address[](2);
        sources[0] = address(0x3);
        sources[1] = address(0x4);

        uint8[] memory decimals = new uint8[](2);
        decimals[0] = 8;
        decimals[1] = 18;

        address fallbackOracle = address(0x5);

        // Deploy MeraPriceOracle
        meraPriceOracle = new MeraPriceOracle(assets, sources, decimals, fallbackOracle);
        console.log("MeraPriceOracle deployed at:", address(meraPriceOracle));

        // Prepare initialization parameters
        IMainVault.InitParams memory initParams = IMainVault.InitParams({
            mainInvestor: mainInvestor,
            backupInvestor: backupInvestor,
            emergencyInvestor: emergencyInvestor,
            manager: manager,
            admin: admin,
            backupAdmin: backupAdmin,
            emergencyAdmin: emergencyAdmin,
            feeWallet: feeWallet,
            profitWallet: profitWallet,
            feePercentage: feePercentage,
            currentImplementationOfInvestmentVault: address(investmentVaultImpl),
            pauserList: address(pauserList),
            meraPriceOracle: address(meraPriceOracle)
        });

        // Encode initialization call
        bytes memory initData = abi.encodeWithSelector(MainVault.initialize.selector, initParams);

        // Deploy proxy using OpenZeppelin UnsafeUpgrades
        // Set unsafeAllow to "external-library-linking" to bypass linked libraries check
        Options memory opts;
        opts.unsafeAllow = "external-library-linking";

        mainVaultProxy = Upgrades.deployUUPSProxy("MainVault.sol:MainVault", initData, opts);
        vm.stopBroadcast();

        console.log("MainVault proxy deployed at:", mainVaultProxy);

        console.log("Roles assigned:");
        console.log("- Main Investor:    ", mainInvestor);
        console.log("- Backup Investor:  ", backupInvestor);
        console.log("- Emergency Investor:", emergencyInvestor);
        console.log("- Manager:          ", manager);
        console.log("- Admin:            ", admin);
        console.log("- Backup Admin:     ", backupAdmin);
        console.log("- Emergency Admin:  ", emergencyAdmin);

        console.log("Configuration:");
        console.log("- Fee Wallet:       ", feeWallet);
        console.log("- Profit Wallet:    ", profitWallet);
        console.log("- Fee Percentage:   ", feePercentage);
        console.log("- InvestmentVault Impl:", address(investmentVaultImpl));
        console.log("- PauserList:       ", address(pauserList));
    }
}
