// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 fundmera.com

// https://github.com/merafund
pragma solidity ^0.8.29;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IUniswapV2Router02} from "../interfaces/IUniswapV2Router02.sol";
import {ISwapRouter} from "../interfaces/ISwapRouter.sol";
import {ISwapRouterBase} from "../interfaces/ISwapRouterBase.sol";
import {Constants} from "./Constants.sol";
import {DataTypes} from "./DataTypes.sol";
import {IMainVault} from "../interfaces/IMainVault.sol";
import {IQuickswapV3Router} from "../interfaces/IQuickswapV3Router.sol";
/// @title SwapLibrary
/// @dev Library providing swap functionality for InvestmentVault

library SwapLibrary {
    using SafeERC20 for IERC20;
    using DataTypes for *;

    // Calculation errors
    error InvalidTokensInSwap();
    error NoTokensReceived();
    error NonAdvantageousPurchasePrice();
    error PriceDidNotDecreaseEnough();
    error SpentMoreThanExpected();
    error SpentMoreThanExpectedWOD();
    error NoPreviousPurchases();
    error PriceDidNotIncreaseEnough();
    error SoldMoreThanExpectedWOB();
    error InsufficientTokensRemaining();
    error InvalidSwap();

    // Execution errors
    error RouterNotAvailable();
    error TokenNotAvailable();
    error PositionNotOpened();
    error ShareMVIsNotZero();
    error DepositIsGreaterThanCapital();
    error ReceivedLessThanExpectedWOB();
    error NoProfit();
    error ProfitNotZero();
    error BadPriceAndTimeBetweenBuys();
    error AssetBoughtTooMuch();
    // Calculation events

    event ProfitCalculated(address indexed fromToken, address indexed toToken, uint256 profitAmount);

    // Execution events
    event ExactInputSingleDelegateExecuted(
        address indexed router, address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut
    );

    event ExactInputDelegateExecuted(
        address indexed router, address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut
    );

    event ExactTokensSwapped(
        address indexed router, address indexed fromToken, address indexed toToken, uint256 amountIn, uint256 amountOut
    );

    event PositionClosed(address indexed token);

    event SwapMvProfitToMiProfit(
        address indexed fromToken, address indexed toToken, uint256 amountIn, uint256 amountOut, uint256 feeAmount
    );

    /// @dev Process swap data and update stored information
    /// @param swapParams Swap parameters including tokens and balances
    /// @param tokenData Storage for token data
    /// @param profitData Storage for profit data
    /// @param assetsData Mapping of asset data
    /// @param feePercentage Function to get the fee percentage
    function computeDataSwap(
        DataTypes.SwapParams memory swapParams,
        DataTypes.TokenData storage tokenData,
        DataTypes.ProfitData storage profitData,
        mapping(IERC20 => DataTypes.AssetData) storage assetsData,
        function() external view returns (uint256) feePercentage,
        IMainVault mainVault
    ) internal {
        require(swapParams.fromToken != swapParams.toToken, InvalidTokensInSwap());

        if (swapParams.swapType == DataTypes.SwapType.ProfitMvToProfitMi) {
            require(
                swapParams.fromToken == tokenData.tokenMV && swapParams.toToken == tokenData.tokenMI,
                InvalidTokensInSwap()
            );
            handleProfitMvToProfitMiSwap(swapParams, tokenData, profitData, feePercentage, mainVault);
            return;
        }

        // Case 1: MI to MV swap (buying MV with MI)
        if (swapParams.fromToken == tokenData.tokenMI && swapParams.toToken == tokenData.tokenMV) {
            handleMiToMvSwap(swapParams, tokenData);
        }
        // Case 2: MV to MI swap (selling MV for MI)
        else if (swapParams.fromToken == tokenData.tokenMV && swapParams.toToken == tokenData.tokenMI) {
            handleMvToMiSwap(swapParams, tokenData, profitData, feePercentage);
        }
        // Case 3: MV to Asset swap (buying asset with MV)
        else if (swapParams.fromToken == tokenData.tokenMV && assetsData[swapParams.toToken].decimals > 0) {
            if (assetsData[swapParams.toToken].strategy == DataTypes.Strategy.Zero) {
                handleZeroStrategyBuy(swapParams, assetsData, profitData);
            } else if (assetsData[swapParams.toToken].strategy == DataTypes.Strategy.First) {
                checkFirstStrategyBuy(swapParams, assetsData, profitData);
            }
        }
        // Case 4: Asset to MV swap (selling asset for MV)
        else if (swapParams.toToken == tokenData.tokenMV && assetsData[swapParams.fromToken].decimals > 0) {
            if (assetsData[swapParams.fromToken].strategy == DataTypes.Strategy.Zero) {
                handleZeroStrategySell(swapParams, assetsData, tokenData, profitData, feePercentage, mainVault);
            } else if (assetsData[swapParams.fromToken].strategy == DataTypes.Strategy.First) {
                checkFirstStrategySell(swapParams, assetsData, tokenData, profitData, feePercentage, mainVault);
            }
        }
        // Case 5: Asset to MI swap (selling asset for MI directly) for Zero strategy
        else if (swapParams.toToken == tokenData.tokenMI && assetsData[swapParams.fromToken].decimals > 0) {
            if (assetsData[swapParams.fromToken].strategy == DataTypes.Strategy.Zero) {
                handleZeroStrategySellToMi(swapParams, assetsData, tokenData, profitData, feePercentage, mainVault);
            }
        } else {
            revert InvalidSwap();
        }
    }

    function addMvProfit(
        DataTypes.TokenData storage tokenData,
        DataTypes.ProfitData storage profitData,
        uint256 mvProfit,
        function() external view returns (uint256) feePercentage,
        IMainVault mainVault
    ) internal {
        profitData.profitMV += mvProfit;

        if (address(tokenData.tokenMI) == address(tokenData.tokenMV)) {
            if (tokenData.profitType == DataTypes.ProfitType.Dynamic) {
                uint256 feePercent = feePercentage();
                uint256 feeAmount = (mvProfit * feePercent) / Constants.MAX_PERCENT;
                uint256 investorProfit = mvProfit - feeAmount;

                profitData.earntProfitInvestor += investorProfit;
                profitData.earntProfitFee += feeAmount;
                profitData.earntProfitTotal += mvProfit;
            } else {
                profitData.earntProfitTotal += mvProfit;
                uint256 currentFixedProfitPercent = mainVault.currentFixedProfitPercent();
                uint256 daysSinceStart = (block.timestamp - tokenData.timestampOfStartInvestment) / 1 days;
                uint256 fixedProfit =
                    currentFixedProfitPercent * daysSinceStart * tokenData.capitalOfMi / 365 / Constants.MAX_PERCENT;

                if (fixedProfit < profitData.earntProfitTotal) {
                    uint256 mustEarntProfitFee = profitData.earntProfitTotal - fixedProfit;
                    if (mustEarntProfitFee > profitData.earntProfitFee) {
                        profitData.earntProfitFee = mustEarntProfitFee;
                        profitData.earntProfitInvestor = fixedProfit;
                    } else {
                        profitData.earntProfitFee =
                            mustEarntProfitFee + (profitData.earntProfitFee - mustEarntProfitFee);
                        profitData.earntProfitInvestor = fixedProfit - (profitData.earntProfitFee - mustEarntProfitFee);
                    }
                } else {
                    profitData.earntProfitInvestor += mvProfit;
                }
            }
        }
    }

    function handleProfitMvToProfitMiSwap(
        DataTypes.SwapParams memory swapParams,
        DataTypes.TokenData storage tokenData,
        DataTypes.ProfitData storage profitData,
        function() external view returns (uint256) feePercentage,
        IMainVault mainVault
    ) internal {
        uint256 miReceived = IERC20(swapParams.toToken).balanceOf(address(this)) - swapParams.secondBalanceBefore;
        uint256 mvSpent = swapParams.firstBalanceBefore - IERC20(swapParams.fromToken).balanceOf(address(this));

        require(miReceived > 0, NoTokensReceived());

        uint256 currentPrice = (mvSpent * Constants.SHARE_DENOMINATOR) / miReceived;

        uint256 averagePriceBefore = (tokenData.depositInMv * Constants.SHARE_DENOMINATOR) / tokenData.mvBought;
        tokenData.lastBuyPrice = averagePriceBefore;

        require(averagePriceBefore > currentPrice, NonAdvantageousPurchasePrice());

        profitData.profitMV -= mvSpent;

        if (tokenData.profitType == DataTypes.ProfitType.Dynamic) {
            uint256 feePercent = feePercentage();
            uint256 feeAmount = (miReceived * feePercent) / Constants.MAX_PERCENT;
            uint256 investorProfit = miReceived - feeAmount;

            profitData.earntProfitInvestor += investorProfit;
            profitData.earntProfitFee += feeAmount;
            profitData.earntProfitTotal += miReceived;
        } else {
            profitData.earntProfitTotal += miReceived;
            uint256 currentFixedProfitPercent = mainVault.currentFixedProfitPercent();
            uint256 daysSinceStart = (block.timestamp - tokenData.timestampOfStartInvestment) / 1 days;
            uint256 fixedProfit =
                currentFixedProfitPercent * daysSinceStart * tokenData.capitalOfMi / 365 / Constants.MAX_PERCENT;

            if (fixedProfit < profitData.earntProfitTotal) {
                uint256 mustEarntProfitFee = profitData.earntProfitTotal - fixedProfit;
                if (mustEarntProfitFee > profitData.earntProfitFee) {
                    profitData.earntProfitFee = mustEarntProfitFee;
                    profitData.earntProfitInvestor = fixedProfit;
                } else {
                    profitData.earntProfitFee = mustEarntProfitFee + (profitData.earntProfitFee - mustEarntProfitFee);
                    profitData.earntProfitInvestor = fixedProfit - (profitData.earntProfitFee - mustEarntProfitFee);
                }
            } else {
                profitData.earntProfitInvestor += miReceived;
            }
        }
        emit SwapMvProfitToMiProfit(
            address(swapParams.fromToken),
            address(swapParams.toToken),
            miReceived,
            profitData.earntProfitInvestor,
            profitData.earntProfitFee
        );
    }

    /// @dev Handle MI to MV swap logic
    function handleMiToMvSwap(DataTypes.SwapParams memory swapParams, DataTypes.TokenData storage tokenData) internal {
        // Check if the average price before is higher than the current purchase price
        // Only apply this check if there were previous purchases

        require(tokenData.mvBought > 0 && tokenData.depositInMv > 0, PositionNotOpened());

        // Calculate the average price before this swap (MI/MV)
        uint256 averagePriceBefore = (tokenData.depositInMv * Constants.SHARE_DENOMINATOR) / tokenData.mvBought;

        // Calculate the current purchase price (MI/MV)
        uint256 miSpent = swapParams.firstBalanceBefore - IERC20(swapParams.fromToken).balanceOf(address(this));
        uint256 mvReceived = IERC20(swapParams.toToken).balanceOf(address(this)) - swapParams.secondBalanceBefore;

        require(mvReceived > 0, NoTokensReceived());

        uint256 currentPrice = (miSpent * Constants.SHARE_DENOMINATOR) / mvReceived;

        // Check that the average price before was higher (which means we're buying at a better price now)

        require(averagePriceBefore > currentPrice, NonAdvantageousPurchasePrice());

        require(
            tokenData.lastBuyTimestamp < block.timestamp - Constants.MIN_TIME_BETWEEN_BUYS
                || tokenData.lastBuyPrice * (Constants.SHARE_DENOMINATOR - tokenData.step) / Constants.SHARE_DENOMINATOR
                    >= currentPrice,
            BadPriceAndTimeBetweenBuys()
        );

        require(
            tokenData.mvBought * tokenData.step * tokenData.capitalOfMi
                / (tokenData.depositInMv * Constants.SHARE_DENOMINATOR) >= mvReceived,
            AssetBoughtTooMuch()
        );

        // Update tracking variables
        tokenData.depositInMv += miSpent;
        tokenData.mvBought += mvReceived;

        if (
            tokenData.lastBuyPrice * (Constants.SHARE_DENOMINATOR - tokenData.step) / Constants.SHARE_DENOMINATOR
                > currentPrice
        ) {
            tokenData.lastBuyPrice =
                tokenData.lastBuyPrice * (Constants.SHARE_DENOMINATOR - tokenData.step) / Constants.SHARE_DENOMINATOR;
        } else {
            tokenData.lastBuyPrice = currentPrice < tokenData.lastBuyPrice ? currentPrice : tokenData.lastBuyPrice; // minimum between current price and last buy price
        }

        tokenData.lastBuyTimestamp = block.timestamp;
    }

    /// @dev Handle MV to MI swap logic
    function handleMvToMiSwap(
        DataTypes.SwapParams memory swapParams,
        DataTypes.TokenData storage tokenData,
        DataTypes.ProfitData storage profitData,
        function() external view returns (uint256) feePercentage
    ) internal {
        // Average purchase price (MI per MV) before selling
        uint256 averageBuyPrice = (tokenData.depositInMv * Constants.SHARE_DENOMINATOR) / tokenData.mvBought;
        // Calculate how many MV tokens were spent and how many MI tokens were received

        int256 newDeposit;
        uint256 currentSellPrice;
        {
            uint256 mvBalanceAfter = IERC20(swapParams.fromToken).balanceOf(address(this));
            uint256 miReceived = IERC20(swapParams.toToken).balanceOf(address(this)) - swapParams.secondBalanceBefore;
            uint256 mvSpent = swapParams.firstBalanceBefore - mvBalanceAfter;

            require(mvBalanceAfter >= profitData.profitMV, SpentMoreThanExpected());
            // Ensure that we actually received MI tokens
            require(miReceived > 0, NoTokensReceived());
            newDeposit = int256(tokenData.depositInMv) - int256(miReceived);
            currentSellPrice = (miReceived * Constants.SHARE_DENOMINATOR) / mvSpent;

            // Update MV tokens balance after the sale

            if (tokenData.mvBought > mvSpent) {
                tokenData.mvBought -= mvSpent;
            } else {
                require(profitData.profitMV == 0, ProfitNotZero());
                tokenData.mvBought = 0;
            }
        }

        // We only allow sale if the current price is higher than the average purchase price
        require(currentSellPrice > averageBuyPrice, PriceDidNotIncreaseEnough());

        // Calculate new deposit after the sale
        uint256 initialDeposit = tokenData.capitalOfMi * tokenData.shareMI / Constants.SHARE_DENOMINATOR; // Using init deposit instead of capital

        uint256 profit = 0;

        // If the new deposit is less than the initial deposit we have profit
        if (newDeposit < int256(initialDeposit)) {
            profit = uint256(int256(initialDeposit) - newDeposit);
            tokenData.depositInMv = initialDeposit; // Do not reduce deposit below the initial one
        } else {
            tokenData.depositInMv = uint256(newDeposit);
        }

        if (tokenData.mvBought > 0) {
            tokenData.lastBuyPrice = (tokenData.depositInMv * Constants.SHARE_DENOMINATOR) / tokenData.mvBought;
        } else {
            tokenData.lastBuyPrice = currentSellPrice;
        }

        // Calculate the minimum required MV tokens that should remain after the sale
        uint256 remainingTokens = tokenData.mvBought;
        uint256 minRequiredTokens = (tokenData.capitalOfMi * tokenData.shareMI) / currentSellPrice;

        // Ensure we still hold enough MV tokens
        require(remainingTokens >= minRequiredTokens, InsufficientTokensRemaining());

        // If there is profit, distribute it between investor and fee wallets
        if (profit > 0) {
            uint256 feePercent = feePercentage();
            uint256 feeAmount = (profit * feePercent) / Constants.MAX_PERCENT;
            uint256 investorProfit = profit - feeAmount;

            profitData.earntProfitInvestor += investorProfit;
            profitData.earntProfitFee += feeAmount;
            profitData.earntProfitTotal += profit;

            emit ProfitCalculated(address(swapParams.fromToken), address(swapParams.toToken), profit);
        }
    }

    /// @dev Handle Zero strategy buy logic
    function handleZeroStrategyBuy(
        DataTypes.SwapParams memory swapParams,
        mapping(IERC20 => DataTypes.AssetData) storage assetsData,
        DataTypes.ProfitData storage profitData
    ) internal {
        // Similar check for Zero strategy when buying asset tokens with MV
        DataTypes.AssetData storage assetData = assetsData[swapParams.toToken];
        require(assetData.tokenBought > 0 && assetData.deposit > 0, PositionNotOpened());
        // Calculate the average price before this swap (MV/Asset)
        uint256 averagePriceBefore = (uint256(assetData.deposit) * Constants.SHARE_DENOMINATOR) / assetData.tokenBought;

        uint256 mvBalanceAfter = IERC20(swapParams.fromToken).balanceOf(address(this));
        require(mvBalanceAfter >= profitData.profitMV, SpentMoreThanExpected());

        // Calculate the current purchase price (MV/Asset)
        uint256 mvSpent = swapParams.firstBalanceBefore - mvBalanceAfter;
        uint256 assetReceived = IERC20(swapParams.toToken).balanceOf(address(this)) - swapParams.secondBalanceBefore;

        require(assetReceived > 0, NoTokensReceived());

        uint256 currentPrice = (mvSpent * Constants.SHARE_DENOMINATOR) / assetReceived;

        require(averagePriceBefore > currentPrice, NonAdvantageousPurchasePrice());

        require(
            assetData.tokenBought * assetData.step * assetData.capital
                / (uint256(assetData.deposit) * Constants.SHARE_DENOMINATOR) >= assetReceived,
            AssetBoughtTooMuch()
        );

        assetData.deposit += int256(mvSpent);
        require(assetData.deposit <= int256(assetData.capital), DepositIsGreaterThanCapital());

        require(
            assetData.lastBuyTimestamp < block.timestamp - Constants.MIN_TIME_BETWEEN_BUYS
                || assetData.lastBuyPrice * (Constants.SHARE_DENOMINATOR - assetData.step) / Constants.SHARE_DENOMINATOR
                    >= currentPrice,
            BadPriceAndTimeBetweenBuys()
        );

        assetData.tokenBought += assetReceived;

        if (
            assetData.lastBuyPrice * (Constants.SHARE_DENOMINATOR - assetData.step) / Constants.SHARE_DENOMINATOR
                > currentPrice
        ) {
            assetData.lastBuyPrice =
                assetData.lastBuyPrice * (Constants.SHARE_DENOMINATOR - assetData.step) / Constants.SHARE_DENOMINATOR;
        } else {
            assetData.lastBuyPrice = currentPrice < assetData.lastBuyPrice ? currentPrice : assetData.lastBuyPrice; // minimum between current price and last buy price
        }

        assetData.lastBuyTimestamp = block.timestamp;
    }

    /// @dev Handle Zero strategy sell logic
    function handleZeroStrategySell(
        DataTypes.SwapParams memory swapParams,
        mapping(IERC20 => DataTypes.AssetData) storage assetsData,
        DataTypes.TokenData storage tokenData,
        DataTypes.ProfitData storage profitData,
        function() external view returns (uint256) feePercentage,
        IMainVault mainVault
    ) internal {
        // Logic for selling tokens with Zero strategy

        uint256 tokenSpent = swapParams.firstBalanceBefore - IERC20(swapParams.fromToken).balanceOf(address(this));
        uint256 mvReceived = IERC20(swapParams.toToken).balanceOf(address(this)) - swapParams.secondBalanceBefore;

        require(mvReceived > 0, NoTokensReceived());

        DataTypes.AssetData storage assetData = assetsData[swapParams.fromToken];

        uint256 initialDeposit = (assetData.capital * assetData.shareMV) / Constants.SHARE_DENOMINATOR;

        int256 newDeposit = int256(assetData.deposit) - int256(mvReceived);
        // Calculate average purchase price (MV/Asset)
        uint256 averageBuyPrice = (uint256(assetData.deposit) * Constants.SHARE_DENOMINATOR) / assetData.tokenBought;

        // Calculate current selling price (MV/Asset)
        uint256 currentSellPrice = (mvReceived * Constants.SHARE_DENOMINATOR) / tokenSpent;

        // Check if we're selling at a price higher than the average purchase price
        require(currentSellPrice > averageBuyPrice, PriceDidNotIncreaseEnough());
        // Calculate profit in MV tokens

        if (newDeposit < int256(initialDeposit)) {
            uint256 profit = uint256(int256(initialDeposit) - newDeposit);
            assetData.deposit = int256(initialDeposit);
            addMvProfit(tokenData, profitData, profit, feePercentage, mainVault);
        } else {
            assetData.deposit = newDeposit;
        }

        // Check that we're not selling too much asset
        uint256 remainingTokens = assetData.tokenBought - tokenSpent;
        uint256 minRequiredTokens = (assetData.capital * assetData.shareMV) / currentSellPrice;

        // Ensure that we have enough tokens left after the sale
        require(remainingTokens >= minRequiredTokens, InsufficientTokensRemaining());

        assetData.tokenBought -= tokenSpent;

        if (assetData.tokenBought > 0) {
            assetData.lastBuyPrice = (uint256(assetData.deposit) * Constants.SHARE_DENOMINATOR) / assetData.tokenBought;
        } else {
            assetData.lastBuyPrice = currentSellPrice;
        }
    }

    /// @dev Check First strategy buy logic
    function checkFirstStrategyBuy(
        DataTypes.SwapParams memory swapParams,
        mapping(IERC20 => DataTypes.AssetData) storage assetsData,
        DataTypes.ProfitData storage profitData
    ) internal returns (bool) {
        // Get asset data
        DataTypes.AssetData storage assetData = assetsData[swapParams.toToken];
        require(assetData.deposit != 0 && assetData.tokenBought != 0, PositionNotOpened());

        uint256 mvBalanceAfter = IERC20(swapParams.fromToken).balanceOf(address(this));
        require(mvBalanceAfter >= profitData.profitMV, SpentMoreThanExpected());

        // Calculate how many MV tokens were spent and how many asset tokens received
        uint256 mvSpent = swapParams.firstBalanceBefore - mvBalanceAfter;
        uint256 assetReceived = IERC20(swapParams.toToken).balanceOf(address(this)) - swapParams.secondBalanceBefore;

        // Check that we received tokens
        require(assetReceived > 0, NoTokensReceived());

        // Calculate current purchase price (MV per Asset)
        uint256 currentPrice = (mvSpent * Constants.SHARE_DENOMINATOR) / assetReceived;

        // Calculate average purchase price before this transaction
        uint256 averagePurchasePrice =
            (uint256(assetData.deposit) * Constants.SHARE_DENOMINATOR) / assetData.tokenBought;

        uint256 workingOrderDeposit = (assetData.capital * assetData.shareMV * assetData.step)
            / (Constants.SHARE_DENOMINATOR * (Constants.SHARE_DENOMINATOR + assetData.step));

        uint256 workingBalanceBuy = (assetData.tokenBought * assetData.step) / (Constants.SHARE_DENOMINATOR);

        require(workingOrderDeposit >= mvSpent, SpentMoreThanExpectedWOD());

        require(workingBalanceBuy < assetReceived, ReceivedLessThanExpectedWOB());

        assetData.deposit += int256(mvSpent);
        assetData.tokenBought += assetReceived;

        // Update last buy price according to strategy requirements
        if (currentPrice < assetData.lastBuyPrice) {
            // If current purchase price is lower than previous, record it
            assetData.lastBuyPrice = currentPrice;
        } else if (currentPrice > averagePurchasePrice) {
            // If current purchase price is higher than average purchase price, record the average purchase price
            assetData.lastBuyPrice = averagePurchasePrice;
        }
        // If currentPrice is between lastBuyPrice and averagePurchasePrice, keep the existing lastBuyPrice

        // Always update the timestamp
        assetData.lastBuyTimestamp = block.timestamp;

        return true;
    }

    /// @dev Check First strategy sell logic
    function checkFirstStrategySell(
        DataTypes.SwapParams memory swapParams,
        mapping(IERC20 => DataTypes.AssetData) storage assetsData,
        DataTypes.TokenData storage tokenData,
        DataTypes.ProfitData storage profitData,
        function() external view returns (uint256) feePercentage,
        IMainVault mainVault
    ) internal {
        // Get asset data
        DataTypes.AssetData storage assetData = assetsData[swapParams.fromToken];

        // Calculate how many asset tokens were spent and how many MV tokens received
        uint256 assetSpent = swapParams.firstBalanceBefore - IERC20(swapParams.fromToken).balanceOf(address(this));
        uint256 mvReceived = IERC20(swapParams.toToken).balanceOf(address(this)) - swapParams.secondBalanceBefore;

        // Check that we received tokens
        require(mvReceived > 0, NoTokensReceived());

        if (assetSpent == assetData.tokenBought) {
            assetData.deposit -= int256(mvReceived);
            require(assetData.deposit < 0, NoProfit());
            uint256 profit = uint256(-assetData.deposit);
            addMvProfit(tokenData, profitData, profit, feePercentage, mainVault);
            assetData.deposit = int256(0);
            assetData.tokenBought = 0;
            emit ProfitCalculated(address(swapParams.fromToken), address(swapParams.toToken), profit);
            emit PositionClosed(address(swapParams.fromToken));
            return;
        }

        // Calculate working order depisit (WOD)
        uint256 workingOrderDeposit = (assetData.capital * assetData.shareMV * assetData.step)
            / (Constants.SHARE_DENOMINATOR * (Constants.SHARE_DENOMINATOR + assetData.step));

        // Calculate working order balance (WOB)
        uint256 workingOrderBalance =
            (assetData.tokenBought * assetData.step) / (Constants.SHARE_DENOMINATOR + assetData.step);

        require(workingOrderBalance >= assetSpent, SoldMoreThanExpectedWOB());
        require(workingOrderDeposit < mvReceived, PriceDidNotIncreaseEnough());

        uint256 profit = mvReceived - workingOrderDeposit;
        // Add to profit
        addMvProfit(tokenData, profitData, profit, feePercentage, mainVault);

        // Update deposit and balance
        assetData.deposit -= int256(workingOrderDeposit);
        assetData.tokenBought -= assetSpent;

        // Emit profit calculated event
        emit ProfitCalculated(address(swapParams.fromToken), address(swapParams.toToken), profit);
    }

    /// @dev Extract first and last token from a Uniswap V3 path
    function extractTokensFromPath(bytes memory path) public pure returns (address firstToken, address lastToken) {
        // Get first token from path (first 20 bytes)
        assembly {
            firstToken := mload(add(path, 32))
            // Right-align address
            firstToken := shr(96, firstToken)
        }

        // Get last token from path (last 20 bytes)
        uint256 lastTokenPos = path.length - 20;
        assembly {
            lastToken := mload(add(add(path, 32), lastTokenPos))
            // Right-align address
            lastToken := shr(96, lastToken)
        }

        return (firstToken, lastToken);
    }

    /// @dev Execute exactInput swap and process the results
    /// @param router The router address
    /// @param params The parameters for the multi-hop swap
    /// @param tokenData Token data storage
    /// @param profitData Profit data storage
    /// @param assetsData Asset data mapping
    /// @param mainVault Reference to the main vault for checking token and router availability
    /// @return amountOut Amount of tokens received
    function executeExactInputSwap(
        address router,
        DataTypes.DelegateExactInputParams memory params,
        DataTypes.TokenData storage tokenData,
        DataTypes.ProfitData storage profitData,
        mapping(IERC20 => DataTypes.AssetData) storage assetsData,
        IMainVault mainVault
    ) external returns (uint256 amountOut) {
        // Verify router and tokens are available
        require(
            mainVault.availableRouterByInvestor(router) && mainVault.availableRouterByAdmin(router),
            RouterNotAvailable()
        );

        // Extract first and last token from the path
        (address firstToken, address lastToken) = extractTokensFromPath(params.path);

        // Verify the tokens are available
        require(
            mainVault.availableTokensByInvestor(firstToken) && mainVault.availableTokensByInvestor(lastToken)
                && mainVault.availableTokensByAdmin(firstToken) && mainVault.availableTokensByAdmin(lastToken),
            TokenNotAvailable()
        );

        // Converting our params to Uniswap's params using the function
        ISwapRouter.ExactInputParams memory routerParams = ISwapRouter.ExactInputParams({
            path: params.path,
            recipient: address(this),
            deadline: params.deadline,
            amountIn: params.amountIn,
            amountOutMinimum: params.amountOutMinimum
        });

        // Get balances before swap to track changes
        uint256 firstBalanceBefore = IERC20(firstToken).balanceOf(address(this));
        uint256 secondBalanceBefore = IERC20(lastToken).balanceOf(address(this));

        // Execute the swap
        if (params.deadline == 0) {
            amountOut = ISwapRouterBase(router).exactInput(
                ISwapRouterBase.ExactInputParams({
                    path: params.path,
                    recipient: address(this),
                    amountIn: params.amountIn,
                    amountOutMinimum: params.amountOutMinimum
                })
            );
        } else {
            amountOut = ISwapRouter(router).exactInput(routerParams);
        }

        // Process swap data
        computeDataSwap(
            DataTypes.SwapParams({
                fromToken: IERC20(firstToken),
                toToken: IERC20(lastToken),
                firstBalanceBefore: firstBalanceBefore,
                secondBalanceBefore: secondBalanceBefore,
                feePercent: mainVault.feePercentage(),
                swapType: params.swapType
            }),
            tokenData,
            profitData,
            assetsData,
            mainVault.feePercentage,
            mainVault
        );

        // Emit event
        emit ExactInputDelegateExecuted(router, firstToken, lastToken, params.amountIn, amountOut);

        return amountOut;
    }

    /// @dev Execute exactInputSingle swap and process the results
    /// @param router The router address
    /// @param params The parameters for the swap
    /// @param tokenData Token data storage
    /// @param profitData Profit data storage
    /// @param assetsData Asset data mapping
    /// @param mainVault Reference to the main vault for checking token and router availability
    /// @return amountOut Amount of tokens received
    function executeExactInputSingleSwap(
        address router,
        DataTypes.DelegateExactInputSingleParams memory params,
        DataTypes.TokenData storage tokenData,
        DataTypes.ProfitData storage profitData,
        mapping(IERC20 => DataTypes.AssetData) storage assetsData,
        IMainVault mainVault
    ) external returns (uint256 amountOut) {
        // Verify router and tokens are available
        require(
            mainVault.availableRouterByInvestor(router) && mainVault.availableRouterByAdmin(router),
            RouterNotAvailable()
        );
        require(
            mainVault.availableTokensByInvestor(params.tokenIn) && mainVault.availableTokensByInvestor(params.tokenOut)
                && mainVault.availableTokensByAdmin(params.tokenIn) && mainVault.availableTokensByAdmin(params.tokenOut),
            TokenNotAvailable()
        );

        // Converting params to Uniswap's params using the function
        ISwapRouter.ExactInputSingleParams memory routerParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: params.tokenIn,
            tokenOut: params.tokenOut,
            fee: params.fee,
            recipient: address(this),
            deadline: params.deadline,
            amountIn: params.amountIn,
            amountOutMinimum: params.amountOutMinimum,
            sqrtPriceLimitX96: params.sqrtPriceLimitX96
        });

        // Get input and output tokens
        IERC20 inputToken = IERC20(params.tokenIn);
        IERC20 outputToken = IERC20(params.tokenOut);

        // Get balances before swap to track changes
        uint256 firstBalanceBefore = inputToken.balanceOf(address(this));
        uint256 secondBalanceBefore = outputToken.balanceOf(address(this));

        // Execute the swap
        if (params.deadline == 0) {
            amountOut = ISwapRouterBase(router).exactInputSingle(
                ISwapRouterBase.ExactInputSingleParams({
                    tokenIn: params.tokenIn,
                    tokenOut: params.tokenOut,
                    fee: params.fee,
                    recipient: address(this),
                    amountIn: params.amountIn,
                    amountOutMinimum: params.amountOutMinimum,
                    sqrtPriceLimitX96: params.sqrtPriceLimitX96
                })
            );
        } else {
            amountOut = ISwapRouter(router).exactInputSingle(routerParams);
        }

        // Process swap data
        computeDataSwap(
            DataTypes.SwapParams({
                fromToken: inputToken,
                toToken: outputToken,
                firstBalanceBefore: firstBalanceBefore,
                secondBalanceBefore: secondBalanceBefore,
                feePercent: mainVault.feePercentage(),
                swapType: params.swapType
            }),
            tokenData,
            profitData,
            assetsData,
            mainVault.feePercentage,
            mainVault
        );

        // Emit event
        emit ExactInputSingleDelegateExecuted(router, params.tokenIn, params.tokenOut, params.amountIn, amountOut);

        return amountOut;
    }

    /// @dev Execute swapExactTokensForTokens (Uniswap V2) and process the results
    /// @param router The router address
    /// @param amountIn Amount of input tokens
    /// @param amountOutMin Minimum amount of output tokens
    /// @param path Path of tokens for the swap
    /// @param deadline Deadline for the swap
    /// @param tokenData Token data storage
    /// @param profitData Profit data storage
    /// @param assetsData Asset data mapping
    /// @param mainVault Reference to the main vault for checking token and router availability
    /// @return amounts Array of amounts for each token in the path
    function executeSwapExactTokensForTokens(
        address router,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        uint256 deadline,
        DataTypes.TokenData storage tokenData,
        DataTypes.ProfitData storage profitData,
        mapping(IERC20 => DataTypes.AssetData) storage assetsData,
        IMainVault mainVault
    ) external returns (uint256[] memory amounts) {
        // Verify router and tokens are available
        require(
            mainVault.availableRouterByInvestor(router) && mainVault.availableRouterByAdmin(router),
            RouterNotAvailable()
        );

        // Verify tokens are available
        require(
            mainVault.availableTokensByInvestor(path[0]) && mainVault.availableTokensByInvestor(path[path.length - 1])
                && mainVault.availableTokensByAdmin(path[0]) && mainVault.availableTokensByAdmin(path[path.length - 1]),
            TokenNotAvailable()
        );

        // Get balances before swap to track changes
        uint256 firstBalanceBefore = IERC20(path[0]).balanceOf(address(this));
        uint256 secondBalanceBefore = IERC20(path[path.length - 1]).balanceOf(address(this));

        // Execute the swap
        amounts =
            IUniswapV2Router02(router).swapExactTokensForTokens(amountIn, amountOutMin, path, address(this), deadline);

        // Process swap data
        computeDataSwap(
            DataTypes.SwapParams({
                fromToken: IERC20(path[0]),
                toToken: IERC20(path[path.length - 1]),
                firstBalanceBefore: firstBalanceBefore,
                secondBalanceBefore: secondBalanceBefore,
                feePercent: mainVault.feePercentage(),
                swapType: DataTypes.SwapType.Default
            }),
            tokenData,
            profitData,
            assetsData,
            mainVault.feePercentage,
            mainVault
        );

        // Emit event
        emit ExactTokensSwapped(router, path[0], path[path.length - 1], amountIn, amounts[amounts.length - 1]);

        return amounts;
    }

    /// @dev Execute Quickswap exactInputSingle swap and process the results
    /// @param router The router address
    /// @param params The parameters for the swap
    /// @param tokenData Token data storage
    /// @param profitData Profit data storage
    /// @param assetsData Asset data mapping
    /// @param mainVault Reference to the main vault for checking token and router availability
    /// @return amountOut Amount of tokens received
    function executeQuickswapExactInputSingleSwap(
        address router,
        DataTypes.DelegateQuickswapExactInputSingleParams memory params,
        DataTypes.TokenData storage tokenData,
        DataTypes.ProfitData storage profitData,
        mapping(IERC20 => DataTypes.AssetData) storage assetsData,
        IMainVault mainVault
    ) external returns (uint256 amountOut) {
        // Verify router and tokens are available
        require(
            mainVault.availableRouterByInvestor(router) && mainVault.availableRouterByAdmin(router),
            RouterNotAvailable()
        );
        require(
            mainVault.availableTokensByInvestor(params.tokenIn) && mainVault.availableTokensByInvestor(params.tokenOut)
                && mainVault.availableTokensByAdmin(params.tokenIn) && mainVault.availableTokensByAdmin(params.tokenOut),
            TokenNotAvailable()
        );

        // Create Quickswap params
        IQuickswapV3Router.ExactInputSingleParams memory quickswapParams = IQuickswapV3Router.ExactInputSingleParams({
            tokenIn: params.tokenIn,
            tokenOut: params.tokenOut,
            recipient: address(this),
            deadline: params.deadline,
            amountIn: params.amountIn,
            amountOutMinimum: params.amountOutMinimum,
            limitSqrtPrice: params.limitSqrtPrice
        });

        // Get input and output tokens
        IERC20 inputToken = IERC20(params.tokenIn);
        IERC20 outputToken = IERC20(params.tokenOut);

        // Get balances before swap to track changes
        uint256 firstBalanceBefore = inputToken.balanceOf(address(this));
        uint256 secondBalanceBefore = outputToken.balanceOf(address(this));

        // Execute the swap
        amountOut = IQuickswapV3Router(router).exactInputSingle(quickswapParams);

        // Process swap data
        computeDataSwap(
            DataTypes.SwapParams({
                fromToken: inputToken,
                toToken: outputToken,
                firstBalanceBefore: firstBalanceBefore,
                secondBalanceBefore: secondBalanceBefore,
                feePercent: mainVault.feePercentage(),
                swapType: params.swapType
            }),
            tokenData,
            profitData,
            assetsData,
            mainVault.feePercentage,
            mainVault
        );

        // Emit event
        emit ExactInputSingleDelegateExecuted(router, params.tokenIn, params.tokenOut, params.amountIn, amountOut);

        return amountOut;
    }

    /// @dev Execute Quickswap exactInput swap and process the results
    /// @param router The router address
    /// @param params The parameters for the multi-hop swap
    /// @param tokenData Token data storage
    /// @param profitData Profit data storage
    /// @param assetsData Asset data mapping
    /// @param mainVault Reference to the main vault for checking token and router availability
    /// @return amountOut Amount of tokens received
    function executeQuickswapExactInputSwap(
        address router,
        DataTypes.DelegateQuickswapExactInputParams memory params,
        DataTypes.TokenData storage tokenData,
        DataTypes.ProfitData storage profitData,
        mapping(IERC20 => DataTypes.AssetData) storage assetsData,
        IMainVault mainVault
    ) external returns (uint256 amountOut) {
        // Verify router and tokens are available
        require(
            mainVault.availableRouterByInvestor(router) && mainVault.availableRouterByAdmin(router),
            RouterNotAvailable()
        );

        // Extract first and last token from the path
        (address firstToken, address lastToken) = extractTokensFromPath(params.path);

        // Verify tokens are available
        require(
            mainVault.availableTokensByInvestor(firstToken) && mainVault.availableTokensByInvestor(lastToken)
                && mainVault.availableTokensByAdmin(firstToken) && mainVault.availableTokensByAdmin(lastToken),
            TokenNotAvailable()
        );

        // Create Quickswap params
        IQuickswapV3Router.ExactInputParams memory quickswapParams = IQuickswapV3Router.ExactInputParams({
            path: params.path,
            recipient: address(this),
            deadline: params.deadline,
            amountIn: params.amountIn,
            amountOutMinimum: params.amountOutMinimum
        });

        // Get balances before swap to track changes
        uint256 firstBalanceBefore = IERC20(firstToken).balanceOf(address(this));
        uint256 secondBalanceBefore = IERC20(lastToken).balanceOf(address(this));

        // Execute the swap
        amountOut = IQuickswapV3Router(router).exactInput(quickswapParams);

        // Process swap data
        computeDataSwap(
            DataTypes.SwapParams({
                fromToken: IERC20(firstToken),
                toToken: IERC20(lastToken),
                firstBalanceBefore: firstBalanceBefore,
                secondBalanceBefore: secondBalanceBefore,
                feePercent: mainVault.feePercentage(),
                swapType: params.swapType
            }),
            tokenData,
            profitData,
            assetsData,
            mainVault.feePercentage,
            mainVault
        );

        // Emit event
        emit ExactInputDelegateExecuted(router, firstToken, lastToken, params.amountIn, amountOut);

        return amountOut;
    }

    /// @dev Handle Zero strategy sell logic directly into MI token
    function handleZeroStrategySellToMi(
        DataTypes.SwapParams memory swapParams,
        mapping(IERC20 => DataTypes.AssetData) storage assetsData,
        DataTypes.TokenData storage tokenData,
        DataTypes.ProfitData storage profitData,
        function() external view returns (uint256) feePercentage,
        IMainVault mainVault
    ) internal {
        // Calculate amounts spent and received
        uint256 assetSpent = swapParams.firstBalanceBefore - IERC20(swapParams.fromToken).balanceOf(address(this));
        uint256 miReceived = IERC20(swapParams.toToken).balanceOf(address(this)) - swapParams.secondBalanceBefore;

        // Must receive some MI tokens
        require(miReceived > 0, NoTokensReceived());

        DataTypes.AssetData storage assetData = assetsData[swapParams.fromToken];

        // Ensure the position was opened and we're selling entire balance
        require(assetData.tokenBought > 0 && uint256(assetData.deposit) > 0, PositionNotOpened());
        require(assetSpent == assetData.tokenBought, SoldMoreThanExpectedWOB());

        // Require we have MV purchase history for average price calculation
        require(tokenData.mvBought > 0 && tokenData.depositInMv > 0, NoPreviousPurchases());

        // Average price MI per MV (scaled by SHARE_DENOMINATOR)
        uint256 averagePriceMiPerMv = (tokenData.depositInMv * Constants.SHARE_DENOMINATOR) / tokenData.mvBought;

        // Minimum MI that should be received to cover the deposit
        uint256 minMiRequired = (uint256(assetData.deposit) * averagePriceMiPerMv) / Constants.SHARE_DENOMINATOR;

        // Ensure we receive at least the minimum amount
        require(miReceived >= minMiRequired, PriceDidNotIncreaseEnough());

        uint256 profit = miReceived - minMiRequired;

        tokenData.mvBought -= uint256(assetData.deposit);
        tokenData.depositInMv -= uint256(minMiRequired);

        // Reset asset pair (portfolio dismantled)
        assetData.deposit = int256(0);
        assetData.tokenBought = 0;
        assetData.capital = 0;

        // Distribute profit (if any) between investor and fee wallets
        if (profit > 0) {
            if (tokenData.profitType == DataTypes.ProfitType.Dynamic) {
                uint256 feePercent = feePercentage();
                uint256 feeAmount = (profit * feePercent) / Constants.MAX_PERCENT;
                uint256 investorProfit = profit - feeAmount;

                profitData.earntProfitInvestor += investorProfit;
                profitData.earntProfitFee += feeAmount;
                profitData.earntProfitTotal += profit;
            } else {
                profitData.earntProfitTotal += profit;
                uint256 currentFixedProfitPercent = mainVault.currentFixedProfitPercent();
                uint256 daysSinceStart = (block.timestamp - tokenData.timestampOfStartInvestment) / 1 days;
                uint256 fixedProfit =
                    (currentFixedProfitPercent * daysSinceStart * tokenData.capitalOfMi) / 365 / Constants.MAX_PERCENT;

                if (fixedProfit < profitData.earntProfitTotal) {
                    uint256 mustEarntProfitFee = profitData.earntProfitTotal - fixedProfit;
                    if (mustEarntProfitFee > profitData.earntProfitFee) {
                        profitData.earntProfitFee = mustEarntProfitFee;
                        profitData.earntProfitInvestor = fixedProfit;
                    } else {
                        profitData.earntProfitFee =
                            mustEarntProfitFee + (profitData.earntProfitFee - mustEarntProfitFee);
                        profitData.earntProfitInvestor = fixedProfit - (profitData.earntProfitFee - mustEarntProfitFee);
                    }
                } else {
                    profitData.earntProfitInvestor += profit;
                }
            }

            emit ProfitCalculated(address(swapParams.fromToken), address(swapParams.toToken), profit);
        }

        // Emit position closed event
        emit PositionClosed(address(swapParams.fromToken));
    }
}
