// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 fundmera.com

// https://github.com/merafund
pragma solidity ^0.8.29;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IMainVault} from "../interfaces/IMainVault.sol";

/// @title DataTypes
/// @dev Library containing common data structures for InvestmentVault
library DataTypes {
    /// @dev Enum representing swap initialization states
    enum SwapInitState {
        NotInitialized, // Swaps not initialized yet
        MiToMvInitialized, // First swap (MI to MV) initialized
        FullyInitialized // All swaps initialized

    }

    enum SwapType {
        Default,
        ProfitMvToProfitMi
    }

    /// @dev Enum representing asset trading strategies
    enum Strategy {
        Zero, // Zero strategy - buy at lower price, sell at higher price
        First // First strategy - stepped buys and sells based on price changes

    }

    enum Router {
        UniswapV2, //0
        UniswapV3, // 1
        QuickswapV3 // 2

    }

    enum ProfitType {
        Dynamic,
        Fixed
    }

    /// @dev Structure for storing asset data
    struct AssetData {
        uint256 shareMV; // Share of MV tokens allocated to this asset
        uint256 step; // Step percentage for First strategy
        Strategy strategy; // Trading strategy for this asset
        int256 deposit; // Deposited amount
        uint256 capital; // Capital allocated to this asset
        uint256 tokenBought; // Amount of tokens bought
        uint8 decimals; // Asset's decimals
        uint256 lastBuyPrice; // Last price of the asset
        uint256 lastBuyTimestamp; // Last buy timestamp of the asset
    }

    /// @dev Structure for swap parameters to avoid stack too deep errors
    struct SwapParams {
        IERC20 fromToken; // Token being sold
        IERC20 toToken; // Token being bought
        uint256 firstBalanceBefore; // Balance of fromToken before swap
        uint256 secondBalanceBefore; // Balance of toToken before swap
        SwapType swapType; // Swap type
    }

    /// @dev Structure for storing main tokens and deposit data
    struct TokenData {
        IERC20 tokenMI; // Main investment token
        IERC20 tokenMV; // Main vault token
        uint256 capitalOfMi; // Initial deposit
        uint256 mvBought; // Amount of MV tokens bought
        uint256 shareMI; // Share of MI tokens for swap
        uint256 depositInMv; // Deposit in MV tokens
        uint256 timestampOfStartInvestment; // Timestamp of start of investment
        ProfitType profitType; // Profit type
        uint256 step;
        uint256 lastBuyPrice; // Last price of the asset
        uint256 lastBuyTimestamp; // Last buy timestamp of the asset
    }

    /// @dev Structure for storing profit data
    struct ProfitData {
        uint256 profitMV; // Profit in MV tokens
        uint256 earntProfitInvestor; // Earned investor profit in MI
        uint256 earntProfitFee; // Earned fee in MI
        uint256 earntProfitTotal; // Total earned profit in MI
        uint256 withdrawnProfitInvestor; // Withdrawn investor profit
        uint256 withdrawnProfitFee; // Withdrawn fee
    }

    /// @dev Structure for initializing the investment vault
    struct InvestmentVaultInitData {
        IMainVault mainVault;
        IERC20 tokenMI;
        IERC20 tokenMV;
        uint256 capitalOfMi;
        uint256 shareMI;
        uint256 step;
        AssetInitData[] assets;
    }

    /// @dev Structure for initializing an asset
    struct AssetInitData {
        IERC20 token; // Asset token
        uint256 shareMV; // Share of MV tokens for this asset
        uint256 step; // Step percentage for First strategy
        Strategy strategy; // Trading strategy
    }

    /// @dev Structure for initializing swaps
    struct InitSwapsData {
        address quouter;
        address router; // Router address
        address[] path; // Swap path
        bytes pathBytes; // Swap path bytes
        uint256 amountOutMin; // Minimum output amount
        uint256 capital; // Capital for this asset
        Router routerType;
    }

    /// @dev Parameters for exactInputSingle function (without recipient field)
    struct DelegateExactInputSingleParams {
        address router;
        address tokenIn;
        address tokenOut;
        uint24 fee;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
        SwapType swapType;
    }

    /// @dev Parameters for exactInput function (without recipient field)
    struct DelegateExactInputParams {
        address router;
        bytes path;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        SwapType swapType;
    }

    /// @dev Parameters for exactOutputSingle function (without recipient field)
    struct DelegateExactOutputSingleParams {
        address router;
        address tokenIn;
        address tokenOut;
        uint24 fee;
        uint256 deadline;
        uint256 amountOut;
        uint256 amountInMaximum;
        uint160 sqrtPriceLimitX96;
        SwapType swapType;
    }

    /// @dev Parameters for exactOutput function (without recipient field)
    struct DelegateExactOutputParams {
        address router;
        bytes path;
        uint256 deadline;
        uint256 amountOut;
        uint256 amountInMaximum;
        SwapType swapType;
    }

    struct DelegateQuickswapExactInputSingleParams {
        address router;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 limitSqrtPrice;
        uint256 deadline;
        SwapType swapType;
    }

    struct DelegateQuickswapExactInputParams {
        address router;
        bytes path;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint256 deadline;
        SwapType swapType;
    }

    struct DelegateQuickswapExactOutputSingleParams {
        address router;
        address tokenIn;
        address tokenOut;
        uint24 fee;
        uint256 amountOut;
        uint256 amountInMaximum;
        uint160 limitSqrtPrice;
        uint256 deadline;
        SwapType swapType;
    }

    struct DelegateQuickswapExactOutputParams {
        address router;
        bytes path;
        uint256 amountOut;
        uint256 amountInMaximum;
        uint256 deadline;
        SwapType swapType;
    }

    struct VaultState {
        bool closed; // Whether position is closed
        uint256 assetsDataLength; // Number of assets
        uint256 pauseToTimestamp; // Pause timestamp
        DataTypes.SwapInitState swapInitState; // Swap initialization state
    }

    /// @dev Structure for router-quoter pair
    struct RouterQuoterPair {
        address router; // Router address
        address quoter; // Quoter address
    }
}
