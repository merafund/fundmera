// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 fundmera.com

// https://github.com/merafund
pragma solidity ^0.8.29;

import {Script, console} from "forge-std/Script.sol";
import {MeraPriceOracle} from "../src/MeraPriceOracle.sol";
import {Factory} from "../src/Factory.sol";
import {NetworkConfig} from "../src/utils/NetworkConfig.sol";

/**
 * @title DeployPriceOracleScript
 * @dev Script for deploying MeraPriceOracle and optionally updating it in an existing Factory
 */
contract DeployPriceOracleScript is Script {
    address factoryAddress;
    address newFactoryOwner;

    function setUp() public {
        factoryAddress = vm.envOr("FACTORY_ADDRESS", address(0));
        newFactoryOwner = vm.envOr("NEW_FACTORY_OWNER", address(0x11));
    }

    function run() public {
        vm.startBroadcast();

        // Get network configuration for current chain
        NetworkConfig.NetworkAssets memory config = NetworkConfig.getNetworkConfig(block.chainid);

        require(config.assets.length > 0, "No configuration found for current network");

        console.log("Deploying MeraPriceOracle for chain ID:", block.chainid);
        console.log("Number of assets:", config.assets.length);

        address fallbackOracle = address(0);

        // Deploy MeraPriceOracle
        MeraPriceOracle meraPriceOracle =
            new MeraPriceOracle(config.assets, config.sources, config.decimals, fallbackOracle);

        console.log("MeraPriceOracle deployed at:", address(meraPriceOracle));

        // If factory address is provided, update the price oracle in the factory
        if (factoryAddress != address(0)) {
            console.log("Updating price oracle in factory:", factoryAddress);

            Factory factory = Factory(factoryAddress);

            // Update the price oracle in the factory
            factory.setMeraPriceOracle(address(meraPriceOracle));

            console.log("Price oracle updated in factory successfully");

            // Transfer ownership if new owner is specified
            if (newFactoryOwner != address(0)) {
                meraPriceOracle.transferOwnership(newFactoryOwner);
                console.log("Price oracle ownership transferred to:", newFactoryOwner);
            }
        } else {
            console.log("No factory address provided. Price oracle deployed without updating factory.");
        }

        // Wait for 5 seconds before ending
        vm.sleep(5000);
        vm.stopBroadcast();

        console.log("Price Oracle deployment completed:");
        console.log("- Price Oracle Address:", address(meraPriceOracle));
        console.log("- Factory Address:", factoryAddress);
        console.log("- Chain ID:", block.chainid);
        console.log("- Number of configured assets:", config.assets.length);
    }
}
