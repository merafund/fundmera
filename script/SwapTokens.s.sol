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
    address public constant INVESTMENT_VAULT = 0x9f3C9D0B97e37F5E4859B4c6F20e04Bc5366237c; // Replace with actual address

    // Router address (e.g. Uniswap)
    address public constant ROUTER = 0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff; // Replace with actual router address

    function run() external {
        // Load private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MANAGER");

        // Start broadcasting
        vm.startBroadcast(deployerPrivateKey);

        // Get InvestmentVault instance
        IInvestmentVault vault = IInvestmentVault(INVESTMENT_VAULT);

        // Define swap parameters
        uint256 amountIn = 1000; // Replace with actual amount
        uint256 amountOutMin = 0; // Replace with minimum amount you want to receive
        address[] memory path = new address[](2);
        path[1] = address(0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619); // Replace with token IN address
        path[0] = address(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174); // Replace with token OUT address
        uint256 deadline = block.timestamp + 15 minutes;

        // Execute swap
        vault.swapExactTokensForTokens(ROUTER, amountIn, amountOutMin, path, deadline);

        vm.stopBroadcast();
    }
}
