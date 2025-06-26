// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 fundmera.com

// https://github.com/merafund
pragma solidity ^0.8.29;

import {Script, console} from "forge-std/Script.sol";
import "../src/utils/MainVaultSwapLibrary.sol";
import "../src/utils/SwapLibrary.sol";
import "../src/utils/Constants.sol";

/**
 * @title DeployLibrariesScript
 * @dev Script for deploying libraries needed for MainVault
 */
contract DeployLibrariesScript is Script {
    // Output file where we'll save the deployed library addresses
    string constant LIBRARY_ADDRESSES_FILE = "./.library_addresses";
    string constant ENV_FILE = "./.library_addresses.env";

    function run() public {
        vm.startBroadcast();

        address mainVaultSwapLib = deployCode("src/utils/MainVaultSwapLibrary.sol:MainVaultSwapLibrary");
        address swapLib = deployCode("src/utils/SwapLibrary.sol:SwapLibrary");
        address constantsLib = deployCode("src/utils/Constants.sol:Constants");

        require(mainVaultSwapLib != address(0), "Failed to deploy MainVaultSwapLibrary");
        require(swapLib != address(0), "Failed to deploy SwapLibrary");
        require(constantsLib != address(0), "Failed to deploy Constants");

        console.log("MainVaultSwapLibrary deployed at:", mainVaultSwapLib);
        console.log("SwapLibrary deployed at:", swapLib);
        console.log("Constants deployed at:", constantsLib);

        vm.stopBroadcast();

        try this.writeLibraryAddresses(mainVaultSwapLib, swapLib, constantsLib) {
            console.log("Library addresses successfully saved");
        } catch Error(string memory reason) {
            console.log("Failed to write library addresses:", reason);
        }
    }

    function writeLibraryAddresses(address mainVaultSwapLib, address swapLib, address constantsLib) external {
        string memory addressesJson = string(
            abi.encodePacked(
                '{"mainVaultSwapLibrary":"',
                vm.toString(mainVaultSwapLib),
                '",',
                '"swapLibrary":"',
                vm.toString(swapLib),
                '",',
                '"constantsLibrary":"',
                vm.toString(constantsLib),
                '"}'
            )
        );

        vm.writeFile(LIBRARY_ADDRESSES_FILE, addressesJson);
        console.log("Library addresses saved to", LIBRARY_ADDRESSES_FILE);

        string memory envContent = string(
            abi.encodePacked(
                "mainVaultSwapLibrary=",
                vm.toString(mainVaultSwapLib),
                "\n",
                "swapLibrary=",
                vm.toString(swapLib),
                "\n",
                "constantsLibrary=",
                vm.toString(constantsLib),
                "\n"
            )
        );

        vm.writeFile(ENV_FILE, envContent);
        console.log("Environment variables saved to", ENV_FILE);

        console.log("========= ADD TO MAKEFILE =========");
        console.log("SWAP_LIBRARY :=", swapLib);
        console.log("SWAP_EXECUTION_LIBRARY :=", mainVaultSwapLib);
        console.log("CONSTANTS_LIBRARY :=", constantsLib);
        console.log("===================================");
    }
}
