// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 fundmera.com

// https://github.com/merafund
pragma solidity ^0.8.29;

import {Script} from "forge-std/Script.sol";
import {IInvestmentVault} from "../src/interfaces/IInvestmentVault.sol";

contract SwapTokensScript is Script {
    // Address of the deployed InvestmentVault contract
    address public constant MAIN_VAULT = 0x9f3C9D0B97e37F5E4859B4c6F20e04Bc5366237c; // Replace with actual address

    // Router address (e.g. Uniswap)

    function run() external {
        // Load private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MANAGER");

        // Start broadcasting
        vm.startBroadcast(deployerPrivateKey);

        // Get InvestmentVault instance
        IMainVault vault = IMainVault(MAIN_VAULT);



        vault.grantRole(vault.BACKUP_ADMIN_ROLE(), address(0x1234567890123456789012345678901234567890));

        vm.stopBroadcast();
    }
}
