// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 fundmera.com

// https://github.com/merafund
pragma solidity ^0.8.29;

import {Script, console} from "forge-std/Script.sol";
import {ReturnTemporaryWallet} from "../src/ReturnTemporaryWallet.sol";

/**
 * @title DeployReturnTemporaryWalletScript
 * @dev Script for deploying ReturnTemporaryWallet contract
 */
contract DeployReturnTemporaryWalletScript is Script {
    address newOwner;

    function setUp() public {
        // Optional: set new owner address from environment variable
        // If not set, deployer will be the owner
        newOwner = vm.envOr("NEW_OWNER", address(0));
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console.log("=== Deploying ReturnTemporaryWallet ===");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", msg.sender);

        // Deploy ReturnTemporaryWallet
        ReturnTemporaryWallet wallet = new ReturnTemporaryWallet();
        address walletAddress = address(wallet);

        console.log("ReturnTemporaryWallet deployed at:", walletAddress);
        console.log("Initial owner:", wallet.owner());

        // Transfer ownership if new owner is specified
        if (newOwner != address(0)) {
            console.log("Transferring ownership to:", newOwner);
            wallet.transferOwnership(newOwner);
            console.log("New owner:", wallet.owner());
        }

        // Wait for 5 seconds before ending
        vm.sleep(5000);
        vm.stopBroadcast();

        console.log("\n=== Deployment Summary ===");
        console.log("ReturnTemporaryWallet Address:", walletAddress);
        console.log("Owner:", wallet.owner());
        console.log("Recipient:", wallet.recipient());
        console.log("Recipient Locked:", wallet.recipientLocked());
        console.log("Chain ID:", block.chainid);
        console.log("\nDeployment completed successfully!");
    }
}

