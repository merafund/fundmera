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
import {IQuickswapV3Router} from "../interfaces/IQuickswapV3Router.sol";
import {Constants} from "./Constants.sol";
import {DataTypes} from "./DataTypes.sol";

/// @title MainVaultSwapLibrary
/// @dev Library for swap operations in MainVault
/// @custom:oz-upgrades-unsafe-allow delegatecall
library MainVaultSwapLibrary {
    using SafeERC20 for IERC20;

    // Custom Errors
    error RouterNotAvailable();
    error TokenNotAvailable();
    error ZeroAmountNotAllowed();

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

    /// @dev Emitted when swapExactTokensForTokens is executed
    event ExactTokensSwapped(
        address indexed router, address indexed fromToken, address indexed toToken, uint256 amountIn, uint256 amountOut
    );

    /// @dev Emitted when swapTokensForExactTokens is executed
    event TokensSwappedForExact(
        address indexed router, address indexed fromToken, address indexed toToken, uint256 amountIn, uint256 amountOut
    );

    /// @dev Execute exactInputSingle swap
    /// @param router The router address
    /// @param params The parameters for the swap
    /// @param availableRouterByAdmin Mapping to check if router is available
    /// @param availableTokensByAdmin Mapping to check if token is available
    /// @return amountOut Amount of tokens received
    function executeExactInputSingle(
        address router,
        DataTypes.DelegateExactInputSingleParams memory params,
        mapping(address => bool) storage availableRouterByAdmin,
        mapping(address => bool) storage availableTokensByAdmin
    ) external returns (uint256 amountOut) {
        // Verify router and tokens are available
        require(availableRouterByAdmin[router], RouterNotAvailable());
        require(params.amountIn > 0, ZeroAmountNotAllowed());
        require(availableTokensByAdmin[params.tokenIn] && availableTokensByAdmin[params.tokenOut], TokenNotAvailable());

        // Create router params
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

        // Set token allowance if needed
        IERC20 inputToken = IERC20(params.tokenIn);
        inputToken.safeIncreaseAllowance(router, params.amountIn);

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

        // Emit event
        emit ExactInputSingleDelegateExecuted(router, params.tokenIn, params.tokenOut, params.amountIn, amountOut);

        return amountOut;
    }

    /// @dev Execute exactInput swap
    /// @param router The router address
    /// @param params The parameters for the multi-hop swap
    /// @param availableRouterByAdmin Mapping to check if router is available
    /// @param availableTokensByAdmin Mapping to check if token is available
    /// @return amountOut Amount of tokens received
    function executeExactInput(
        address router,
        DataTypes.DelegateExactInputParams memory params,
        mapping(address => bool) storage availableRouterByAdmin,
        mapping(address => bool) storage availableTokensByAdmin
    ) external returns (uint256 amountOut) {
        // Verify router and tokens are available
        require(availableRouterByAdmin[router], RouterNotAvailable());
        require(params.amountIn > 0, ZeroAmountNotAllowed());

        // Extract first and last token from the path
        address firstToken;
        address lastToken;

        // Get first token from path (first 20 bytes)
        bytes memory path = params.path;

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

        // Verify tokens are available
        require(availableTokensByAdmin[firstToken] && availableTokensByAdmin[lastToken], TokenNotAvailable());

        // Create router params
        ISwapRouter.ExactInputParams memory routerParams = ISwapRouter.ExactInputParams({
            path: params.path,
            recipient: address(this),
            deadline: params.deadline,
            amountIn: params.amountIn,
            amountOutMinimum: params.amountOutMinimum
        });

        // Set token allowance if needed
        IERC20 inputToken = IERC20(firstToken);
        inputToken.safeIncreaseAllowance(router, params.amountIn);

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

        // Emit event
        emit ExactInputDelegateExecuted(router, firstToken, lastToken, params.amountIn, amountOut);

        return amountOut;
    }

    /// @dev Execute exactOutputSingle swap
    /// @param router The router address
    /// @param params The parameters for the swap
    /// @param availableRouterByAdmin Mapping to check if router is available
    /// @param availableTokensByAdmin Mapping to check if token is available
    /// @return amountIn Amount of tokens spent
    function executeExactOutputSingle(
        address router,
        DataTypes.DelegateExactOutputSingleParams memory params,
        mapping(address => bool) storage availableRouterByAdmin,
        mapping(address => bool) storage availableTokensByAdmin
    ) external returns (uint256 amountIn) {
        // Verify router and tokens are available
        require(availableRouterByAdmin[router], RouterNotAvailable());
        require(params.amountOut > 0, ZeroAmountNotAllowed());
        require(availableTokensByAdmin[params.tokenIn] && availableTokensByAdmin[params.tokenOut], TokenNotAvailable());

        // Create router params
        ISwapRouter.ExactOutputSingleParams memory routerParams = ISwapRouter.ExactOutputSingleParams({
            tokenIn: params.tokenIn,
            tokenOut: params.tokenOut,
            fee: params.fee,
            recipient: address(this),
            deadline: params.deadline,
            amountOut: params.amountOut,
            amountInMaximum: params.amountInMaximum,
            sqrtPriceLimitX96: params.sqrtPriceLimitX96
        });

        // Set token allowance if needed
        IERC20 inputToken = IERC20(params.tokenIn);
        inputToken.safeIncreaseAllowance(router, params.amountInMaximum);

        if (params.deadline == 0) {
            amountIn = ISwapRouterBase(router).exactOutputSingle(
                ISwapRouterBase.ExactOutputSingleParams({
                    tokenIn: params.tokenIn,
                    tokenOut: params.tokenOut,
                    fee: params.fee,
                    recipient: address(this),
                    amountOut: params.amountOut,
                    amountInMaximum: params.amountInMaximum,
                    sqrtPriceLimitX96: params.sqrtPriceLimitX96
                })
            );
        } else {
            amountIn = ISwapRouter(router).exactOutputSingle(routerParams);
        }

        // Emit event
        emit ExactOutputSingleDelegateExecuted(router, params.tokenIn, params.tokenOut, amountIn, params.amountOut);

        return amountIn;
    }

    /// @dev Execute exactOutput swap
    /// @param router The router address
    /// @param params The parameters for the multi-hop swap
    /// @param availableRouterByAdmin Mapping to check if router is available
    /// @param availableTokensByAdmin Mapping to check if token is available
    /// @return amountIn Amount of tokens spent
    function executeExactOutput(
        address router,
        DataTypes.DelegateExactOutputParams memory params,
        mapping(address => bool) storage availableRouterByAdmin,
        mapping(address => bool) storage availableTokensByAdmin
    ) external returns (uint256 amountIn) {
        // Verify router and amount
        require(availableRouterByAdmin[router], RouterNotAvailable());
        require(params.amountOut > 0, ZeroAmountNotAllowed());

        // Extract first and last token from the path
        address firstToken; // Output token
        address lastToken; // Input token

        // Get first token from path (first 20 bytes)
        bytes memory path = params.path;

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

        // Verify tokens are available
        require(availableTokensByAdmin[lastToken] && availableTokensByAdmin[firstToken], TokenNotAvailable());

        // Create router params
        ISwapRouter.ExactOutputParams memory routerParams = ISwapRouter.ExactOutputParams({
            path: params.path,
            recipient: address(this),
            deadline: params.deadline,
            amountOut: params.amountOut,
            amountInMaximum: params.amountInMaximum
        });

        // Set token allowance if needed
        IERC20 inputToken = IERC20(firstToken);
        inputToken.safeIncreaseAllowance(router, params.amountInMaximum);

        if (params.deadline == 0) {
            amountIn = ISwapRouterBase(router).exactOutput(
                ISwapRouterBase.ExactOutputParams({
                    path: params.path,
                    recipient: address(this),
                    amountOut: params.amountOut,
                    amountInMaximum: params.amountInMaximum
                })
            );
        } else {
            amountIn = ISwapRouter(router).exactOutput(routerParams);
        }

        // Emit event
        emit ExactOutputDelegateExecuted(router, lastToken, firstToken, amountIn, params.amountOut);

        return amountIn;
    }

    /// @dev Execute swapExactTokensForTokens (Uniswap V2) and process the results
    /// @param router The router address
    /// @param amountIn Amount of input tokens
    /// @param amountOutMin Minimum amount of output tokens
    /// @param path Path of tokens for the swap
    /// @param deadline Deadline for the swap
    /// @param availableRouterByAdmin Mapping to check if router is available
    /// @param availableTokensByAdmin Mapping to check if token is available
    /// @return amounts Array of amounts for each token in the path
    function executeSwapExactTokensForTokens(
        address router,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        uint256 deadline,
        mapping(address => bool) storage availableRouterByAdmin,
        mapping(address => bool) storage availableTokensByAdmin
    ) external returns (uint256[] memory amounts) {
        // Verify router and tokens are available
        require(availableRouterByAdmin[router], RouterNotAvailable());
        require(amountIn > 0, ZeroAmountNotAllowed());

        // Get input and output tokens from path
        address firstToken = path[0];
        address lastToken = path[path.length - 1];

        // Verify tokens are available
        require(availableTokensByAdmin[firstToken] && availableTokensByAdmin[lastToken], TokenNotAvailable());

        // Check and set token allowance if needed
        IERC20 inputToken = IERC20(firstToken);
        inputToken.safeIncreaseAllowance(router, amountIn);

        // Execute the swap
        amounts = IUniswapV2Router02(router).swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            address(this), // tokens come back to the vault
            deadline
        );

        // Emit event
        emit ExactTokensSwapped(router, firstToken, lastToken, amountIn, amounts[amounts.length - 1]);

        return amounts;
    }

    /// @dev Execute swapTokensForExactTokens (Uniswap V2) and process the results
    /// @param router The router address
    /// @param amountOut Amount of output tokens
    /// @param amountInMax Maximum amount of input tokens
    /// @param path Path of tokens for the swap
    /// @param deadline Deadline for the swap
    /// @param availableRouterByAdmin Mapping to check if router is available
    /// @param availableTokensByAdmin Mapping to check if token is available
    /// @return amounts Array of amounts for each token in the path
    function executeSwapTokensForExactTokens(
        address router,
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        uint256 deadline,
        mapping(address => bool) storage availableRouterByAdmin,
        mapping(address => bool) storage availableTokensByAdmin
    ) external returns (uint256[] memory amounts) {
        // Verify router and tokens are available
        require(availableRouterByAdmin[router], RouterNotAvailable());
        require(amountOut > 0, ZeroAmountNotAllowed());

        require(availableTokensByAdmin[path[0]] && availableTokensByAdmin[path[path.length - 1]], TokenNotAvailable());

        // Check and set token allowance if needed
        IERC20 inputToken = IERC20(path[0]);
        inputToken.safeIncreaseAllowance(router, amountInMax);
        // Execute the swap
        amounts = IUniswapV2Router02(router).swapTokensForExactTokens(
            amountOut,
            amountInMax,
            path,
            address(this), // tokens come back to the vault
            deadline
        );

        // Emit event
        emit TokensSwappedForExact(router, path[0], path[path.length - 1], amounts[0], amountOut);

        return amounts;
    }

    /// @dev Execute Quickswap exactInputSingle swap
    /// @param router The router address
    /// @param params The parameters for the swap
    /// @param availableRouterByAdmin Mapping to check if router is available
    /// @param availableTokensByAdmin Mapping to check if token is available
    /// @return amountOut Amount of tokens received
    function executeQuickswapExactInputSingle(
        address router,
        DataTypes.DelegateQuickswapExactInputSingleParams memory params,
        mapping(address => bool) storage availableRouterByAdmin,
        mapping(address => bool) storage availableTokensByAdmin
    ) external returns (uint256 amountOut) {
        // Verify router and tokens are available
        require(availableRouterByAdmin[router], RouterNotAvailable());
        require(params.amountIn > 0, ZeroAmountNotAllowed());
        require(availableTokensByAdmin[params.tokenIn] && availableTokensByAdmin[params.tokenOut], TokenNotAvailable());

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

        // Set token allowance if needed
        IERC20 inputToken = IERC20(params.tokenIn);
        inputToken.safeIncreaseAllowance(router, params.amountIn);

        // Execute the swap
        amountOut = IQuickswapV3Router(router).exactInputSingle(quickswapParams);

        // Emit event
        emit ExactInputSingleDelegateExecuted(router, params.tokenIn, params.tokenOut, params.amountIn, amountOut);

        return amountOut;
    }

    /// @dev Execute Quickswap exactInput swap
    /// @param router The router address
    /// @param params The parameters for the multi-hop swap
    /// @param availableRouterByAdmin Mapping to check if router is available
    /// @param availableTokensByAdmin Mapping to check if token is available
    /// @return amountOut Amount of tokens received
    function executeQuickswapExactInput(
        address router,
        DataTypes.DelegateQuickswapExactInputParams memory params,
        mapping(address => bool) storage availableRouterByAdmin,
        mapping(address => bool) storage availableTokensByAdmin
    ) external returns (uint256 amountOut) {
        // Verify router and tokens are available
        require(availableRouterByAdmin[router], RouterNotAvailable());
        require(params.amountIn > 0, ZeroAmountNotAllowed());

        // Extract first and last token from the path
        address firstToken;
        address lastToken;

        // Get first token from path (first 20 bytes)
        bytes memory path = params.path;

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

        // Verify tokens are available
        require(availableTokensByAdmin[firstToken] && availableTokensByAdmin[lastToken], TokenNotAvailable());

        // Create Quickswap params
        IQuickswapV3Router.ExactInputParams memory quickswapParams = IQuickswapV3Router.ExactInputParams({
            path: params.path,
            recipient: address(this),
            deadline: params.deadline,
            amountIn: params.amountIn,
            amountOutMinimum: params.amountOutMinimum
        });

        // Set token allowance if needed
        IERC20 inputToken = IERC20(firstToken);
        inputToken.safeIncreaseAllowance(router, params.amountIn);

        // Execute the swap
        amountOut = IQuickswapV3Router(router).exactInput(quickswapParams);

        // Emit event
        emit ExactInputDelegateExecuted(router, firstToken, lastToken, params.amountIn, amountOut);

        return amountOut;
    }

    /// @dev Execute Quickswap exactOutputSingle swap
    /// @param router The router address
    /// @param params The parameters for the swap
    /// @param availableRouterByAdmin Mapping to check if router is available
    /// @param availableTokensByAdmin Mapping to check if token is available
    /// @return amountIn Amount of tokens spent
    function executeQuickswapExactOutputSingle(
        address router,
        DataTypes.DelegateQuickswapExactOutputSingleParams memory params,
        mapping(address => bool) storage availableRouterByAdmin,
        mapping(address => bool) storage availableTokensByAdmin
    ) external returns (uint256 amountIn) {
        // Verify router and tokens are available
        require(availableRouterByAdmin[router], RouterNotAvailable());
        require(params.amountOut > 0, ZeroAmountNotAllowed());
        require(availableTokensByAdmin[params.tokenIn] && availableTokensByAdmin[params.tokenOut], TokenNotAvailable());

        // Create Quickswap params
        IQuickswapV3Router.ExactOutputSingleParams memory quickswapParams = IQuickswapV3Router.ExactOutputSingleParams({
            tokenIn: params.tokenIn,
            tokenOut: params.tokenOut,
            fee: params.fee,
            recipient: address(this),
            deadline: params.deadline,
            amountOut: params.amountOut,
            amountInMaximum: params.amountInMaximum,
            limitSqrtPrice: params.limitSqrtPrice
        });

        // Set token allowance if needed
        IERC20 inputToken = IERC20(params.tokenIn);
        inputToken.safeIncreaseAllowance(router, params.amountInMaximum);

        // Execute the swap
        amountIn = IQuickswapV3Router(router).exactOutputSingle(quickswapParams);

        // Emit event
        emit ExactOutputSingleDelegateExecuted(router, params.tokenIn, params.tokenOut, amountIn, params.amountOut);

        return amountIn;
    }

    /// @dev Execute Quickswap exactOutput swap
    /// @param router The router address
    /// @param params The parameters for the multi-hop swap
    /// @param availableRouterByAdmin Mapping to check if router is available
    /// @param availableTokensByAdmin Mapping to check if token is available
    /// @return amountIn Amount of tokens spent
    function executeQuickswapExactOutput(
        address router,
        DataTypes.DelegateQuickswapExactOutputParams memory params,
        mapping(address => bool) storage availableRouterByAdmin,
        mapping(address => bool) storage availableTokensByAdmin
    ) external returns (uint256 amountIn) {
        // Verify router and amount
        require(availableRouterByAdmin[router], RouterNotAvailable());
        require(params.amountOut > 0, ZeroAmountNotAllowed());

        // Extract first and last token from the path
        address firstToken; // Output token
        address lastToken; // Input token

        // Get first token from path (first 20 bytes)
        bytes memory path = params.path;

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

        // Verify tokens are available
        require(availableTokensByAdmin[lastToken] && availableTokensByAdmin[firstToken], TokenNotAvailable());

        // Create Quickswap params
        IQuickswapV3Router.ExactOutputParams memory quickswapParams = IQuickswapV3Router.ExactOutputParams({
            path: params.path,
            recipient: address(this),
            deadline: params.deadline,
            amountOut: params.amountOut,
            amountInMaximum: params.amountInMaximum
        });

        // Set token allowance if needed
        IERC20 inputToken = IERC20(firstToken);
        inputToken.safeIncreaseAllowance(router, params.amountInMaximum);

        // Execute the swap
        amountIn = IQuickswapV3Router(router).exactOutput(quickswapParams);

        // Emit event
        emit ExactOutputDelegateExecuted(router, lastToken, firstToken, amountIn, params.amountOut);

        return amountIn;
    }
}
