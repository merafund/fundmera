// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 fundmera.com

// https://github.com/merafund
pragma solidity ^0.8.29;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {IInvestmentVault} from "./interfaces/IInvestmentVault.sol";
import {IMainVault} from "./interfaces/IMainVault.sol";
import {IUniswapV2Router02} from "./interfaces/IUniswapV2Router02.sol";
import {ISwapRouter} from "./interfaces/ISwapRouter.sol";
import {IQuickswapV3Router} from "./interfaces/IQuickswapV3Router.sol";
import {Constants} from "./utils/Constants.sol";
import {SwapLibrary} from "./utils/SwapLibrary.sol";
import {DataTypes} from "./utils/DataTypes.sol";
import {IQuoterV2} from "./interfaces/IQuoterV2.sol";
import {IQuoterQuickswap} from "./interfaces/IQuoterQuickswap.sol";
import {IMeraPriceOracle} from "./interfaces/IMeraPriceOracle.sol";

/// @title InvestmentVault
/// @dev Contract for managing investment positions with multiple assets and swap strategies
contract InvestmentVault is Initializable, UUPSUpgradeable, IInvestmentVault {
    using SafeERC20 for IERC20;
    using DataTypes for *;

    error InvalidImplementationAddress();
    error SwapsNotInitialized();
    error OnlyMainVaultError();
    error OnlyAdminError();
    error OnlyManagerError();
    error TokenNotAvailable();
    error RouterNotAvailable();
    error ZeroAmountNotAllowed();
    error PositionAlreadyClosed();
    error NoProfit();
    error NoProfitToWithdraw();
    error InvalidMvToTokenPaths();
    error InvalidMiInPath();
    error InvalidMvInPath();
    error NotEnoughBalance();
    error InvalidMVToken();
    error InsufficientMvCapital();
    error InvalidSwapState();
    error SwapAlreadyInitialized();
    error InvalidShareMi();
    error MainContractIsPaused();
    error InitializePause();
    error BigDeviation();
    error QuoterNotAvailable();
    error ArrayLengthsMustMatch();
    error AssetNotFound();
    error ShareExceedsMaximum();
    error ShareMustBePositive();
    error ShareMustBeLessThanOrEqualToDeposit();
    error AssetAlreadyBought();
    error BigDeviationOracle();
    error InvalidStep();
    error InvalidToken();

    event ProfitCalculated(address indexed fromToken, address indexed toToken, uint256 profitAmount);

    /// @dev Emitted when exactInputSingleDelegate is executed
    event ExactInputSingleDelegateExecuted(
        address indexed router, address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut
    );

    /// @dev Emitted when exactInputDelegate is executed
    event ExactInputDelegateExecuted(
        address indexed router, address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut
    );

    /// @dev Emitted when exactOutputSingleDelegate is executed
    event ExactOutputSingleDelegateExecuted(
        address indexed router, address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut
    );

    /// @dev Emitted when exactOutputDelegate is executed
    event ExactOutputDelegateExecuted(
        address indexed router, address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut
    );

    IMainVault public mainVault;

    DataTypes.TokenData public tokenData;
    DataTypes.ProfitData public profitData;

    DataTypes.VaultState public vaultState;

    mapping(IERC20 => DataTypes.AssetData) public assetsData;

    /// @dev Ensures that swaps have been fully initialized before certain operations
    /// Reverts with SwapsNotInitialized if swaps are not yet fully initialized
    modifier SwapsInitialized() {
        require(vaultState.swapInitState == DataTypes.SwapInitState.FullyInitialized, SwapsNotInitialized());
        _;
    }

    modifier IsNotInitializePause() {
        require(block.timestamp > vaultState.pauseToTimestamp, InitializePause());
        _;
    }

    modifier OnlyMainVault() {
        require(msg.sender == address(mainVault), OnlyMainVaultError());
        _;
    }

    modifier OnlyAdmin() {
        require(mainVault.hasRole(mainVault.ADMIN_ROLE(), msg.sender), OnlyAdminError());
        _;
    }

    modifier OnlyManager() {
        require(mainVault.hasRole(mainVault.MANAGER_ROLE(), msg.sender), OnlyManagerError());
        _;
    }

    modifier whenNotPaused() {
        require(!mainVault.paused(), MainContractIsPaused());
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc IInvestmentVault
    function initialize(DataTypes.InvestmentVaultInitData calldata initData) public initializer {
        mainVault = IMainVault(address(initData.mainVault));

        require(initData.step <= Constants.MAX_STEP && initData.step >= Constants.MIN_STEP, InvalidStep());
        require(
            initData.shareMI <= Constants.SHARE_INITIAL_MAX || initData.shareMI == Constants.SHARE_DENOMINATOR,
            ShareExceedsMaximum()
        );

        // Initialize TokenData
        tokenData = DataTypes.TokenData({
            tokenMI: initData.tokenMI,
            tokenMV: initData.tokenMV,
            initDeposit: initData.initDeposit,
            mvBought: 0,
            shareMI: initData.shareMI,
            depositInMv: 0,
            timestampOfStartInvestment: block.timestamp,
            profitType: mainVault.profitType(),
            step: initData.step,
            lastBuyPrice: 0,
            lastBuyTimestamp: 0
        });

        // Initialize ProfitData
        profitData = DataTypes.ProfitData({
            profitMV: 0,
            earntProfitInvestor: 0,
            earntProfitFee: 0,
            earntProfitTotal: 0,
            withdrawnProfitInvestor: 0,
            withdrawnProfitFee: 0
        });

        // Initialize VaultState
        vaultState = DataTypes.VaultState({
            closed: false,
            assetsDataLength: initData.assets.length,
            pauseToTimestamp: block.timestamp + Constants.PAUSE_AFTER_INIT,
            swapInitState: DataTypes.SwapInitState.NotInitialized
        });

        for (uint256 i = 0; i < initData.assets.length; i++) {
            require(
                initData.assets[i].step <= Constants.MAX_STEP && initData.assets[i].step >= Constants.MIN_STEP,
                InvalidStep()
            );
            require(initData.assets[i].shareMV <= Constants.SHARE_INITIAL_MAX, ShareExceedsMaximum());
            require(
                initData.assets[i].token != initData.tokenMI && initData.assets[i].token != initData.tokenMV,
                InvalidToken()
            );
            assetsData[initData.assets[i].token] = DataTypes.AssetData({
                shareMV: initData.assets[i].shareMV,
                step: initData.assets[i].step,
                strategy: initData.assets[i].strategy,
                deposit: 0,
                capital: 0, // Initialize with zero, will be set in initMvToTokensSwaps
                tokenBought: 0,
                decimals: IERC20Metadata(address(initData.assets[i].token)).decimals(),
                lastBuyPrice: 0,
                lastBuyTimestamp: 0
            });
        }
        if (initData.tokenMI == initData.tokenMV) {
            require(initData.shareMI == Constants.SHARE_DENOMINATOR, InvalidShareMi());
            tokenData.mvBought = initData.initDeposit;
            tokenData.depositInMv = initData.initDeposit;
            vaultState.swapInitState = DataTypes.SwapInitState.MiToMvInitialized;
        }

        __UUPSUpgradeable_init();
    }

    /// @inheritdoc IInvestmentVault
    function initMiToMvSwap(DataTypes.InitSwapsData calldata miToMvPath, uint256 deadline)
        external
        OnlyManager
        IsNotInitializePause
        whenNotPaused
        returns (uint256 amountOut)
    {
        require(tokenData.tokenMI.balanceOf(address(this)) >= tokenData.initDeposit, NotEnoughBalance());

        (address tokenIn, address tokenOut) = extractTokenInAndOut(miToMvPath);
        require(tokenIn == address(tokenData.tokenMI), InvalidMiInPath());
        require(tokenOut == address(tokenData.tokenMV), InvalidMvInPath());

        require(mainVault.availableRouterByAdmin(miToMvPath.router), RouterNotAvailable());
        require(mainVault.availableRouterByAdmin(miToMvPath.quouter), QuoterNotAvailable());

        require(tokenData.mvBought == 0, AssetAlreadyBought());

        uint256 amountIn = tokenData.initDeposit * tokenData.shareMI / Constants.SHARE_DENOMINATOR;

        amountOut = _performSwapAndValidate(miToMvPath, amountIn, deadline, tokenIn, tokenOut);

        tokenData.mvBought = amountOut;
        tokenData.depositInMv = amountIn;
        tokenData.lastBuyPrice = amountIn * Constants.SHARE_DENOMINATOR / amountOut;
        tokenData.lastBuyTimestamp = block.timestamp;

        // Update state
        if (vaultState.swapInitState == DataTypes.SwapInitState.NotInitialized) {
            vaultState.swapInitState = DataTypes.SwapInitState.MiToMvInitialized;
        }

        emit MiToMvSwapInitialized(miToMvPath.router, amountIn, amountOut, block.timestamp);

        return amountOut;
    }

    /// @inheritdoc IInvestmentVault
    function initMvToTokensSwaps(DataTypes.InitSwapsData[] calldata mvToTokenPaths, uint256 deadline)
        external
        OnlyManager
        IsNotInitializePause
        whenNotPaused
    {
        require(
            vaultState.swapInitState == DataTypes.SwapInitState.MiToMvInitialized
                || vaultState.swapInitState == DataTypes.SwapInitState.FullyInitialized,
            InvalidSwapState()
        );
        require(
            mvToTokenPaths.length == vaultState.assetsDataLength
                || vaultState.swapInitState == DataTypes.SwapInitState.FullyInitialized,
            InvalidMvToTokenPaths()
        );

        // Calculate available capital from mvBought
        uint256 availableMvCapital = tokenData.mvBought;

        for (uint256 i = 0; i < mvToTokenPaths.length; i++) {
            require(mainVault.availableRouterByAdmin(mvToTokenPaths[i].router), RouterNotAvailable());
            require(mainVault.availableRouterByAdmin(mvToTokenPaths[i].quouter), QuoterNotAvailable());

            (address tokenIn, address tokenOut) = extractTokenInAndOut(mvToTokenPaths[i]);
            require(tokenIn == address(tokenData.tokenMV), InvalidMVToken());
            IERC20 targetToken = IERC20(tokenOut);
            DataTypes.AssetData memory assetData = assetsData[targetToken];
            require(assetData.shareMV > 0, InvalidMVToken());
            require(assetData.tokenBought == 0, AssetAlreadyBought());

            assetData.capital = mvToTokenPaths[i].capital;

            uint256 amountIn = (assetData.capital * assetData.shareMV) / Constants.SHARE_DENOMINATOR;
            require(amountIn <= availableMvCapital, InsufficientMvCapital());
            availableMvCapital -= amountIn;
            uint256 amountOut = _performSwapAndValidate(mvToTokenPaths[i], amountIn, deadline, tokenIn, tokenOut);

            assetData.tokenBought = amountOut;
            assetData.lastBuyPrice = amountIn * Constants.SHARE_DENOMINATOR / amountOut;
            assetData.lastBuyTimestamp = block.timestamp;
            assetData.deposit = int256(amountIn);

            assetsData[targetToken] = assetData;
        }

        // Update state
        vaultState.swapInitState = DataTypes.SwapInitState.FullyInitialized;

        emit MvToTokensSwapsInitialized(mvToTokenPaths.length, block.timestamp);
    }

    /// @inheritdoc IInvestmentVault
    function withdraw(IERC20 token, uint256 amount, address to) external OnlyMainVault {
        token.safeTransfer(to, amount);
    }

    /// @inheritdoc IInvestmentVault
    function setAssetShares(IERC20[] calldata tokens, uint256[] calldata shares) external OnlyAdmin whenNotPaused {
        require(tokens.length == shares.length, ArrayLengthsMustMatch());

        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20 token = tokens[i];
            uint256 newShareMV = shares[i];

            // Get current asset data and verify it exists
            DataTypes.AssetData memory assetData = assetsData[token];

            require(assetData.decimals > 0, AssetNotFound());
            require(
                newShareMV <= uint256(assetData.deposit) * Constants.SHARE_DENOMINATOR / assetData.capital,
                ShareMustBeLessThanOrEqualToDeposit()
            );

            uint256 oldShareMV = assetData.shareMV;

            // Update the share value
            assetData.shareMV = newShareMV;
            assetsData[token] = assetData;

            emit AssetShareUpdated(address(token), oldShareMV, newShareMV);
        }
    }

    /// @inheritdoc IInvestmentVault
    function setAssetCapital(IERC20[] calldata tokens, uint256[] calldata capitals) external OnlyAdmin whenNotPaused {
        require(tokens.length == capitals.length, ArrayLengthsMustMatch());

        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20 token = tokens[i];
            uint256 newCapital = capitals[i];

            // Get current asset data and verify it exists
            DataTypes.AssetData memory assetData = assetsData[token];
            require(assetData.decimals > 0, AssetNotFound());

            uint256 oldCapital = assetData.capital;

            // Update the capital value
            assetData.capital = newCapital;
            assetsData[token] = assetData;

            emit AssetCapitalUpdated(address(token), oldCapital, newCapital);
        }
    }

    /// @inheritdoc IInvestmentVault
    function setShareMi(uint256 newShareMI) external OnlyAdmin whenNotPaused {
        require(newShareMI <= Constants.SHARE_DENOMINATOR, ShareExceedsMaximum());
        require(
            newShareMI <= tokenData.depositInMv * Constants.SHARE_DENOMINATOR / tokenData.initDeposit,
            ShareMustBeLessThanOrEqualToDeposit()
        );

        uint256 oldShareMI = tokenData.shareMI;
        tokenData.shareMI = newShareMI;

        emit ShareMiUpdated(oldShareMI, newShareMI);
    }

    /// @inheritdoc IInvestmentVault
    function withdrawProfit()
        external
        returns (
            bool investorProfitWithdrawn,
            uint256 investorProfitAmount,
            bool feeProfitWithdrawn,
            uint256 feeProfitAmount
        )
    {
        uint256 remainingInvestorProfit = profitData.earntProfitInvestor - profitData.withdrawnProfitInvestor;
        uint256 remainingFeeProfit = profitData.earntProfitFee - profitData.withdrawnProfitFee;

        if (remainingInvestorProfit == 0 && remainingFeeProfit == 0) {
            revert NoProfitToWithdraw();
        }

        bool profitLockExpired = block.timestamp > mainVault.profitLockedUntil();

        if (profitLockExpired && remainingInvestorProfit > 0) {
            investorProfitWithdrawn = true;
            investorProfitAmount = remainingInvestorProfit;

            tokenData.tokenMI.safeTransfer(mainVault.profitWallet(), remainingInvestorProfit);

            profitData.withdrawnProfitInvestor += remainingInvestorProfit;
        }

        if (remainingFeeProfit > 0) {
            feeProfitWithdrawn = true;
            feeProfitAmount = remainingFeeProfit;

            tokenData.tokenMI.safeTransfer(mainVault.feeWallet(), remainingFeeProfit);

            profitData.withdrawnProfitFee += remainingFeeProfit;
        }

        emit ProfitWithdrawn(investorProfitWithdrawn, investorProfitAmount, feeProfitWithdrawn, feeProfitAmount);
    }

    /// @inheritdoc IInvestmentVault
    function closePosition() external OnlyAdmin whenNotPaused {
        require(!vaultState.closed, PositionAlreadyClosed());

        uint256 finalBalance = tokenData.tokenMI.balanceOf(address(this));
        require(finalBalance >= tokenData.initDeposit, NoProfit());

        uint256 totalProfit = finalBalance - tokenData.initDeposit
            - (profitData.earntProfitTotal - profitData.withdrawnProfitInvestor - profitData.withdrawnProfitFee);
        if (tokenData.profitType == DataTypes.ProfitType.Dynamic) {
            uint256 feePercent = mainVault.feePercentage();
            uint256 feeAmount = (totalProfit * feePercent) / Constants.MAX_PERCENT;
            uint256 investorProfit = totalProfit - feeAmount;
            profitData.earntProfitInvestor += investorProfit;
            profitData.earntProfitFee += feeAmount;
            profitData.earntProfitTotal += totalProfit;
        } else {
            profitData.earntProfitTotal += totalProfit;
            uint256 currentFixedProfitPercent = mainVault.currentFixedProfitPercent();
            uint256 daysSinceStart = (block.timestamp - tokenData.timestampOfStartInvestment) / 1 days;
            uint256 fixedProfit =
                currentFixedProfitPercent * daysSinceStart * tokenData.initDeposit / (365 * Constants.MAX_PERCENT);

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
                profitData.earntProfitInvestor += totalProfit;
            }
        }

        tokenData.tokenMI.safeTransfer(address(mainVault), tokenData.initDeposit);

        vaultState.closed = true;

        emit PositionClosed(
            tokenData.initDeposit, finalBalance, totalProfit, profitData.earntProfitInvestor, profitData.earntProfitFee
        );
    }

    /// @inheritdoc IInvestmentVault
    function increaseRouterAllowance(IERC20 token, address router, uint256 amount) external OnlyAdmin whenNotPaused {
        require(mainVault.availableTokensByAdmin(address(token)), TokenNotAvailable());
        require(mainVault.availableRouterByAdmin(router), RouterNotAvailable());

        token.safeIncreaseAllowance(router, amount);

        emit TokenAllowanceIncreased(address(token), router, amount);
    }

    /// @inheritdoc IInvestmentVault
    function decreaseRouterAllowance(IERC20 token, address router, uint256 amount) external OnlyAdmin whenNotPaused {
        token.safeDecreaseAllowance(router, amount);

        emit TokenAllowanceDecreased(address(token), router, amount);
    }

    /// @inheritdoc IInvestmentVault
    function swapExactTokensForTokens(
        address router,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        uint256 deadline
    ) external OnlyManager SwapsInitialized returns (uint256[] memory amounts) {
        amounts = SwapLibrary.executeSwapExactTokensForTokens(
            router, amountIn, amountOutMin, path, deadline, tokenData, profitData, assetsData, mainVault
        );
    }

    /// @dev Swaps an exact amount of input tokens for as many output tokens as possible using Uniswap V3
    /// Only manager can call this function
    /// Router must be in the list of available routers
    /// Input and output tokens must be in the list of available tokens
    /// Swaps must be initialized
    ///
    /// @param params The parameters necessary for the swap
    /// @return amountOut The amount of the received token
    function exactInputSingle(DataTypes.DelegateExactInputSingleParams calldata params)
        external
        OnlyManager
        SwapsInitialized
        returns (uint256 amountOut)
    {
        amountOut =
            SwapLibrary.executeExactInputSingleSwap(params.router, params, tokenData, profitData, assetsData, mainVault);
    }

    /// @dev Swaps an exact amount of tokens for as many output tokens as possible along the specified path using Uniswap V3
    /// Only manager can call this function
    /// Router must be in the list of available routers
    /// First and last tokens in the path must be in the list of available tokens
    /// Swaps must be initialized
    ///
    /// @param params The parameters necessary for the multi-hop swap
    /// @return amountOut The amount of the received token
    function exactInput(DataTypes.DelegateExactInputParams calldata params)
        external
        OnlyManager
        SwapsInitialized
        returns (uint256 amountOut)
    {
        amountOut =
            SwapLibrary.executeExactInputSwap(params.router, params, tokenData, profitData, assetsData, mainVault);
    }

    /// @dev Swaps an exact amount of input tokens for as many output tokens as possible using Quickswap V3
    /// @param params The parameters necessary for the swap
    /// @return amountOut The amount of the received token
    function quickswapExactInputSingle(DataTypes.DelegateQuickswapExactInputSingleParams calldata params)
        external
        OnlyManager
        SwapsInitialized
        returns (uint256 amountOut)
    {
        amountOut = SwapLibrary.executeQuickswapExactInputSingleSwap(
            params.router, params, tokenData, profitData, assetsData, mainVault
        );
    }

    /// @dev Swaps an exact amount of tokens for as many output tokens as possible along the specified path using Quickswap V3
    /// @param params The parameters necessary for the multi-hop swap
    /// @return amountOut The amount of the received token
    function quickswapExactInput(DataTypes.DelegateQuickswapExactInputParams calldata params)
        external
        OnlyManager
        SwapsInitialized
        returns (uint256 amountOut)
    {
        amountOut = SwapLibrary.executeQuickswapExactInputSwap(
            params.router, params, tokenData, profitData, assetsData, mainVault
        );
    }

    /// @dev Validates if the price deviation between two swaps is within acceptable range
    /// @param amountIn1 Amount of tokens given in first swap
    /// @param amountOut1 Amount of tokens received in first swap
    /// @param amountIn2 Amount of tokens given in second swap
    /// @param amountOut2 Amount of tokens received in second swap
    /// @return bool Returns true if price deviation is within acceptable range
    function _validatePriceDeviation(uint256 amountIn1, uint256 amountOut1, uint256 amountIn2, uint256 amountOut2)
        internal
        pure
        virtual
        returns (bool)
    {
        if (amountIn2 != amountIn1 * Constants.PRICE_CHECK_DENOMINATOR + amountIn2 % Constants.PRICE_CHECK_DENOMINATOR)
        {
            return false;
        }

        uint256 price1 = (amountIn1 * Constants.SHARE_DENOMINATOR) / amountOut1;
        uint256 price2 = (amountIn2 * Constants.SHARE_DENOMINATOR) / amountOut2;

        uint256 priceDiff;
        if (price1 > price2) {
            priceDiff = ((price1 - price2) * Constants.PRICE_DIFF_MULTIPLIER * Constants.SHARE_DENOMINATOR) / price1;
        } else {
            priceDiff = ((price2 - price1) * Constants.PRICE_DIFF_MULTIPLIER * Constants.SHARE_DENOMINATOR) / price2;
        }

        return priceDiff <= Constants.MAX_PRICE_DEVIATION;
    }

    function _validatePriceDeviationFromOracle(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut)
        internal
        view
        virtual
        returns (bool)
    {
        // If oracle check is canceled in MainVault, skip validation
        if (mainVault.isCanceledOracleCheck()) {
            return true;
        }

        // Get price oracle from MainVault
        IMeraPriceOracle oracle = mainVault.meraPriceOracle();

        // Prepare array of assets for oracle query
        address[] memory assets = new address[](2);
        assets[0] = tokenIn;
        assets[1] = tokenOut;

        // Get price data from oracle
        IMeraPriceOracle.AssetPriceData[] memory priceData = oracle.getAssetsPriceData(assets);

        // Get decimals from asset data
        uint8 decimalsIn = IERC20Metadata(address(tokenIn)).decimals();
        uint8 decimalsOut = IERC20Metadata(address(tokenOut)).decimals();

        // Calculate actual price considering asset decimals
        uint256 actualPrice = (amountOut * (10 ** (18 + decimalsIn - decimalsOut))) / amountIn;

        // Get oracle price with oracle decimals
        uint256 oraclePrice =
            (priceData[0].price * (10 ** (18 + priceData[1].decimals - priceData[0].decimals))) / priceData[1].price;

        // Calculate deviation percentage (scaled to 1e18)
        uint256 deviation;
        if (actualPrice > oraclePrice) {
            deviation = ((actualPrice - oraclePrice) * Constants.PRICE_DIFF_MULTIPLIER * Constants.SHARE_DENOMINATOR)
                / oraclePrice;
        } else {
            deviation = ((oraclePrice - actualPrice) * Constants.PRICE_DIFF_MULTIPLIER * Constants.SHARE_DENOMINATOR)
                / oraclePrice;
        }

        // Check if deviation is within allowed range (5e18 = 5%)
        return deviation <= Constants.MAX_PRICE_DEVIATION_FROM_ORACLE;
    }

    function _performSwapAndValidate(
        DataTypes.InitSwapsData memory initSwapsData,
        uint256 amountIn,
        uint256 deadline,
        address tokenIn,
        address tokenOut
    ) internal returns (uint256 amountOut) {
        uint256 decreasedAmountIn = amountIn / Constants.PRICE_CHECK_DENOMINATOR;
        uint256 decreasedAmountOut;

        if (initSwapsData.routerType == DataTypes.Router.UniswapV3) {
            ISwapRouter router = ISwapRouter(initSwapsData.router);
            IQuoterV2 quoter = IQuoterV2(initSwapsData.quouter);

            (decreasedAmountOut,,,) = quoter.quoteExactInput(initSwapsData.pathBytes, decreasedAmountIn);

            ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
                path: initSwapsData.pathBytes,
                recipient: address(this),
                deadline: deadline,
                amountIn: amountIn,
                amountOutMinimum: initSwapsData.amountOutMin
            });
            amountOut = router.exactInput(params);
        } else if (initSwapsData.routerType == DataTypes.Router.QuickswapV3) {
            IQuickswapV3Router router = IQuickswapV3Router(initSwapsData.router);
            IQuoterQuickswap quoter = IQuoterQuickswap(initSwapsData.quouter);

            (decreasedAmountOut,) = quoter.quoteExactInput(initSwapsData.pathBytes, decreasedAmountIn);

            IQuickswapV3Router.ExactInputParams memory params = IQuickswapV3Router.ExactInputParams({
                path: initSwapsData.pathBytes,
                recipient: address(this),
                deadline: deadline,
                amountIn: amountIn,
                amountOutMinimum: initSwapsData.amountOutMin
            });
            amountOut = router.exactInput(params);
        } else {
            IUniswapV2Router02 router = IUniswapV2Router02(initSwapsData.router);

            uint256[] memory decreasedAmountsOut = router.getAmountsOut(decreasedAmountIn, initSwapsData.path);
            decreasedAmountOut = decreasedAmountsOut[decreasedAmountsOut.length - 1];

            uint256[] memory amounts = router.swapExactTokensForTokens(
                amountIn, initSwapsData.amountOutMin, initSwapsData.path, address(this), deadline
            );
            amountOut = amounts[amounts.length - 1];
        }
        require(
            _validatePriceDeviationFromOracle(tokenIn, tokenOut, decreasedAmountIn, decreasedAmountOut),
            BigDeviationOracle()
        );
        require(_validatePriceDeviation(decreasedAmountIn, decreasedAmountOut, amountIn, amountOut), BigDeviation());

        return amountOut;
    }

    function extractTokenInAndOut(DataTypes.InitSwapsData memory initSwapsData)
        internal
        pure
        returns (address tokenIn, address tokenOut)
    {
        if (initSwapsData.routerType == DataTypes.Router.UniswapV2) {
            tokenIn = initSwapsData.path[0];
            tokenOut = initSwapsData.path[initSwapsData.path.length - 1];
        } else if (initSwapsData.routerType == DataTypes.Router.UniswapV3) {
            (tokenIn, tokenOut) = SwapLibrary.extractTokensFromPath(initSwapsData.pathBytes);
        } else if (initSwapsData.routerType == DataTypes.Router.QuickswapV3) {
            (tokenIn, tokenOut) = SwapLibrary.extractTokensFromPath(initSwapsData.pathBytes);
        }
    }

    function _authorizeUpgrade(address newImplementation) internal view override OnlyAdmin {
        require(newImplementation == mainVault.currentImplementationOfInvestmentVault(), InvalidImplementationAddress());
    }
}
