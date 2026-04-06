// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 fundmera.com

// https://github.com/merafund
pragma solidity 0.8.29;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IAgentDistributionProfit {
    // Errors
    error ZeroAddress();
    error AccessDenied();
    error AgentPercentageCanOnlyIncrease();
    error AgentPercentageOutOfRange();

    // Events
    event FundWalletSet(address sender, address newFundWallet);

    // Distributes profit among the specified tokens.
    // Requirements:
    // - Caller must have the appropriate role.
    function distributeProfit(address[] calldata tokens) external;

    // Increases the agent's profit percentage.
    // Requirements:
    // - `_agentPercentage` must be within the allowed range.
    // - `_agentPercentage` must be greater than the current percentage.
    function increaseAgentPercentage(uint256 _agentPercentage) external;

    // Sets the fund wallet address.
    // Requirements:
    // - `_fundWallet` cannot be the zero address.
    function setFundWallet(address _fundWallet) external;
}
