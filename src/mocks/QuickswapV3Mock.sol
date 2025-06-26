// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 fundmera.com

// https://github.com/merafund
pragma solidity ^0.8.0;
pragma abicoder v2;

import {IQuickswapV3Router} from "../../src/interfaces/IQuickswapV3Router.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// Mock contract for QuickswapV3Router with fixed price swaps

contract QuickswapV3Mock is IQuickswapV3Router {
    // Price mapping for token pairs (token0 -> token1 -> price)
    mapping(address => mapping(address => uint256)) public prices;

    // Set price for token pair (price = token1/token0)
    function setPrice(address token0, address token1, uint256 price) external {
        prices[token0][token1] = price;
        // Set reverse price
        prices[token1][token0] = 1e18 * 1e18 / price;
    }

    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        override
        returns (uint256 amountOut)
    {
        require(params.deadline >= block.timestamp, "QuickswapV3Mock: EXPIRED");

        // Calculate output amount based on fixed price
        amountOut = (params.amountIn * prices[params.tokenIn][params.tokenOut]) / 1e18;
        require(amountOut >= params.amountOutMinimum, "QuickswapV3Mock: INSUFFICIENT_OUTPUT_AMOUNT");

        // Transfer tokens
        IERC20(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn);
        IERC20(params.tokenOut).transfer(params.recipient, amountOut);

        return amountOut;
    }

    function exactOutputSingle(ExactOutputSingleParams calldata params)
        external
        payable
        override
        returns (uint256 amountIn)
    {
        require(params.deadline >= block.timestamp, "QuickswapV3Mock: EXPIRED");

        // Calculate required input amount based on fixed price
        amountIn = (params.amountOut * 1e18) / prices[params.tokenIn][params.tokenOut];
        require(amountIn <= params.amountInMaximum, "QuickswapV3Mock: EXCESSIVE_INPUT_AMOUNT");

        // Transfer tokens
        IERC20(params.tokenIn).transferFrom(msg.sender, address(this), amountIn);
        IERC20(params.tokenOut).transfer(params.recipient, params.amountOut);

        return amountIn;
    }

    function exactInput(ExactInputParams calldata params) external payable override returns (uint256 amountOut) {
        require(params.deadline >= block.timestamp, "QuickswapV3Mock: EXPIRED");

        // Extract first and last token from path
        // Path format: [token1, fee1, token2, fee2, token3]
        address tokenIn = address(bytes20(params.path[0:20]));
        address tokenOut = address(bytes20(params.path[params.path.length - 20:params.path.length]));

        // Calculate output amount based on fixed price
        amountOut = (params.amountIn * prices[tokenIn][tokenOut]) / 1e18;
        require(amountOut >= params.amountOutMinimum, "QuickswapV3Mock: INSUFFICIENT_OUTPUT_AMOUNT");

        // Transfer tokens
        IERC20(tokenIn).transferFrom(msg.sender, address(this), params.amountIn);
        IERC20(tokenOut).transfer(params.recipient, amountOut);

        return amountOut;
    }

    function exactOutput(ExactOutputParams calldata params) external payable override returns (uint256 amountIn) {
        require(params.deadline >= block.timestamp, "QuickswapV3Mock: EXPIRED");

        // Extract first and last token from path
        // Path format: [token1, fee1, token2, fee2, token3]
        address tokenIn = address(bytes20(params.path[0:20]));
        address tokenOut = address(bytes20(params.path[params.path.length - 20:params.path.length]));

        // Calculate required input amount based on fixed price
        amountIn = (params.amountOut * 1e18) / prices[tokenIn][tokenOut];
        require(amountIn <= params.amountInMaximum, "QuickswapV3Mock: EXCESSIVE_INPUT_AMOUNT");

        // Transfer tokens
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenOut).transfer(params.recipient, params.amountOut);

        return amountIn;
    }

    function exactInputSingleSupportingFeeOnTransferTokens(ExactInputSingleParams calldata params)
        external
        override
        returns (uint256 amountOut)
    {
        require(params.deadline >= block.timestamp, "QuickswapV3Mock: EXPIRED");

        // Calculate output amount based on fixed price
        amountOut = (params.amountIn * prices[params.tokenIn][params.tokenOut]) / 1e18;
        require(amountOut >= params.amountOutMinimum, "QuickswapV3Mock: INSUFFICIENT_OUTPUT_AMOUNT");

        // Transfer tokens
        IERC20(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn);
        IERC20(params.tokenOut).transfer(params.recipient, amountOut);

        return amountOut;
    }

    function algebraSwapCallback(int256, /* amount0Delta */ int256, /* amount1Delta */ bytes calldata /* data */ )
        external
        pure
        override
    {
        revert("QuickswapV3Mock: UNIMPLEMENTED");
    }
}
