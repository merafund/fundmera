/// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 fundmera.com

// https://github.com/merafund
pragma solidity ^0.8.29;

import {IMainVault} from "./IMainVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DataTypes} from "../utils/DataTypes.sol";

/// @title IInvestmentVault
/// @dev Interface for Investment Vault
interface IInvestmentVault {
    /// @dev Event emitted when an exact amount of tokens is swapped for another token
    event ExactTokensSwapped(
        address indexed router, address indexed fromToken, address indexed toToken, uint256 amountIn, uint256 amountOut
    );

    /// @dev Event emitted when tokens are swapped for an exact amount of output tokens
    event TokensSwappedForExact(
        address indexed router, address indexed fromToken, address indexed toToken, uint256 amountIn, uint256 amountOut
    );

    /// @dev Event emitted when token allowance is increased for a router
    event TokenAllowanceIncreased(address indexed token, address indexed router, uint256 amount);

    /// @dev Event emitted when token allowance is decreased for a router
    event TokenAllowanceDecreased(address indexed token, address indexed router, uint256 amount);

    /// @dev Event emitted when a position is closed
    event PositionClosed(
        uint256 initialDeposit, uint256 finalBalance, uint256 totalProfit, uint256 investorProfit, uint256 feeProfit
    );

    /// @dev Event emitted when profit is withdrawn
    event ProfitWithdrawn(
        bool investorProfitWithdrawn, uint256 investorProfitAmount, bool feeProfitWithdrawn, uint256 feeProfitAmount
    );

    /// @dev Event emitted when the initial MI to MV swap is completed
    ///
    /// @param router The address of the router used for the swap
    /// @param amountIn The amount of MI tokens swapped
    /// @param amountOut The amount of MV tokens received
    /// @param timestamp The timestamp when the swap was executed
    event MiToMvSwapInitialized(address router, uint256 amountIn, uint256 amountOut, uint256 timestamp);

    /// @dev Event emitted when all MV to token swaps are completed
    ///
    /// @param tokensCount The number of different tokens that were acquired
    /// @param timestamp The timestamp when the swaps were executed
    event MvToTokensSwapsInitialized(uint256 tokensCount, uint256 timestamp);

    /// @dev Event emitted when asset shares are updated
    ///
    /// @param token The token whose share is updated
    /// @param oldShareMV The previous MV share value
    /// @param newShareMV The new MV share value
    event AssetShareUpdated(address indexed token, uint256 oldShareMV, uint256 newShareMV);

    /// @dev Event emitted when asset capital is updated
    ///
    /// @param token The token whose capital is updated
    /// @param oldCapital The previous capital value
    /// @param newCapital The new capital value
    event AssetCapitalUpdated(address indexed token, uint256 oldCapital, uint256 newCapital);

    /// @dev Event emitted when MI share is updated
    ///
    /// @param oldShareMI The previous MI share value
    /// @param newShareMI The new MI share value
    event ShareMiUpdated(uint256 oldShareMI, uint256 newShareMI);

    /// @dev Initializes the Investment Vault with the provided data
    /// @param initData Initialization data for the vault
    function initialize(DataTypes.InvestmentVaultInitData calldata initData) external;

    /// @dev Initializes first swap from MI token to MV token
    /// Only admin can call this function
    /// @param miToMvPath Path for swapping MI token to MV token
    /// @param deadline Deadline for swap transaction
    /// @return amountOut The amount of MV tokens received
    function initMiToMvSwap(DataTypes.InitSwapsData calldata miToMvPath, uint256 deadline)
        external
        returns (uint256 amountOut);

    /// @dev Initializes secondary swaps from MV token to other tokens
    /// Only admin can call this function
    /// Must be called after initMiToMvSwap
    ///
    /// For each asset, this function:
    /// - Calculates and sets the capital based on mvBought and shareToken
    /// - Executes swaps from MV token to the asset tokens
    /// - Updates tracking data
    ///
    /// @param mvToTokenPaths Paths for swapping MV token to other tokens
    /// @param deadline Deadline for swap transactions
    function initMvToTokensSwaps(DataTypes.InitSwapsData[] calldata mvToTokenPaths, uint256 deadline) external;

    /// @dev Withdraws specified amount of token from vault to a recipient
    /// Only the main vault can call this function
    ///
    /// @param token Token to withdraw
    /// @param amount Amount to withdraw
    /// @param to Recipient address
    function withdraw(IERC20 token, uint256 amount, address to) external;

    /// @dev Withdraws profit to appropriate wallets
    /// Only manager can call this function
    /// Investor profit can only be withdrawn if profit lock is expired
    /// Fee profit can be withdrawn regardless of lock
    ///
    /// @return investorProfitWithdrawn Whether investor profit was withdrawn
    /// @return investorProfitAmount Amount of investor profit withdrawn
    /// @return feeProfitWithdrawn Whether fee profit was withdrawn
    /// @return feeProfitAmount Amount of fee profit withdrawn
    function withdrawProfit()
        external
        returns (
            bool investorProfitWithdrawn,
            uint256 investorProfitAmount,
            bool feeProfitWithdrawn,
            uint256 feeProfitAmount
        );

    /// @dev Increases token allowance for a router
    /// Only admin can call this function
    /// Router and token must be in the list of available routers and tokens in MainVault
    ///
    /// @param token Token to approve
    /// @param router Router to increase allowance for
    /// @param amount Amount to increase allowance by
    function increaseRouterAllowance(IERC20 token, address router, uint256 amount) external;

    /// @dev Decreases token allowance for a router
    /// Only admin can call this function
    /// Router and token must be in the list of available routers and tokens in MainVault
    ///
    /// @param token Token to approve
    /// @param router Router to decrease allowance for
    /// @param amount Amount to decrease allowance by
    function decreaseRouterAllowance(IERC20 token, address router, uint256 amount) external;

    /// @dev Closes the investment position
    /// Only admin can call this function
    /// Calculates profit as the difference between current tokenMI balance and initial deposit
    /// Applies fee percentage from MainVault
    /// Transfers initial deposit back to MainVault
    /// Updates profit tracking variables
    /// Marks the position as closed
    function closePosition() external;

    /// @dev Updates the share of MV tokens allocated to specific assets
    /// Only admin can call this function
    ///
    /// @param tokens Array of tokens to update
    /// @param shares Array of new share values to set for each token
    function setAssetShares(IERC20[] calldata tokens, uint256[] calldata shares) external;

    /// @dev Updates the capital amount for specific assets
    /// Only admin can call this function
    ///
    /// @param tokens Array of tokens to update
    /// @param capitals Array of new capital values to set for each token
    function setAssetCapital(IERC20[] calldata tokens, uint256[] calldata capitals) external;

    /// @dev Updates the MI share value
    /// Only admin can call this function
    /// This value determines the proportion of MI tokens that will be swapped to MV tokens
    /// during the first phase of initialization
    ///
    /// @param newShareMI New MI share value
    function setShareMi(uint256 newShareMI) external;

    /// @dev Swaps an exact amount of input tokens for as many output tokens as possible using Uniswap
    /// Only manager can call this function
    /// Router and tokens must be in the list of available routers and tokens in MainVault
    ///
    /// @param router The Uniswap router address to use
    /// @param amountIn The amount of input tokens to send
    /// @param amountOutMin The minimum amount of output tokens to receive
    /// @param path An array of token addresses representing the swap path
    /// @param deadline Unix timestamp after which the transaction will revert
    /// @return amounts The input token amount and all subsequent output token amounts
    function swapExactTokensForTokens(
        address router,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}
