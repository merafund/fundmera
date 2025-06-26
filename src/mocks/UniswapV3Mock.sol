// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 fundmera.com

// https://github.com/merafund
pragma solidity ^0.8.0;
pragma abicoder v2;

import {ISwapRouter} from "../../src/interfaces/ISwapRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Mock contract for UniswapV3Router with fixed price swaps
contract UniswapV3Mock is ISwapRouter {
    // Price mapping for token pairs (token0 -> token1 -> price)
    mapping(address => mapping(address => uint256)) public prices;

    // Set price for token pair (price = token1/token0)
    function setPrice(address token0, address token1, uint256 price) external {
        prices[token0][token1] = price;
        // Set reverse price
        if (price > 0) {
            prices[token1][token0] = 1e18 * 1e18 / price;
        }
    }

    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        override
        returns (uint256 amountOut)
    {
        require(params.deadline >= block.timestamp, "UniswapV3Mock: EXPIRED");

        // Calculate output amount based on fixed price
        amountOut = (params.amountIn * prices[params.tokenIn][params.tokenOut]) / 1e18;
        require(amountOut >= params.amountOutMinimum, "UniswapV3Mock: INSUFFICIENT_OUTPUT_AMOUNT");

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
        require(params.deadline >= block.timestamp, "UniswapV3Mock: EXPIRED");

        // Calculate required input amount based on fixed price
        amountIn = (params.amountOut * 1e18) / prices[params.tokenIn][params.tokenOut];
        require(amountIn <= params.amountInMaximum, "UniswapV3Mock: EXCESSIVE_INPUT_AMOUNT");

        // Transfer tokens
        IERC20(params.tokenIn).transferFrom(msg.sender, address(this), amountIn);
        IERC20(params.tokenOut).transfer(params.recipient, params.amountOut);

        return amountIn;
    }

    // Multi-hop swaps implementation using first and last tokens from path
    function exactInput(ExactInputParams calldata params) external payable override returns (uint256 amountOut) {
        require(params.deadline >= block.timestamp, "UniswapV3Mock: EXPIRED");

        // Extract tokens from path
        // Path format: [token1, fee1, token2, fee2, token3]
        address[] memory tokens = new address[]((params.path.length + 20) / 23);
        tokens[0] = address(uint160(bytes20(params.path[0:20])));

        uint256 i;
        uint256 offset = 0;
        while (offset < params.path.length - 20) {
            offset += 23; // token (20) + fee (3)
            tokens[++i] = address(uint160(bytes20(params.path[offset:offset + 20])));
        }

        // Calculate output amount through all hops
        amountOut = params.amountIn;
        for (i = 0; i < tokens.length - 1; i++) {
            amountOut = (amountOut * prices[tokens[i]][tokens[i + 1]]) / 1e18;
        }
        require(amountOut >= params.amountOutMinimum, "UniswapV3Mock: INSUFFICIENT_OUTPUT_AMOUNT");

        // Transfer tokens
        IERC20(tokens[0]).transferFrom(msg.sender, address(this), params.amountIn);
        IERC20(tokens[tokens.length - 1]).transfer(params.recipient, amountOut);

        return amountOut;
    }

    function exactOutput(ExactOutputParams calldata params) external payable override returns (uint256 amountIn) {
        require(params.deadline >= block.timestamp, "UniswapV3Mock: EXPIRED");

        // Extract tokens from path
        // Path format: [token1, fee1, token2, fee2, token3]
        address[] memory tokens = new address[]((params.path.length + 20) / 23);
        tokens[0] = address(uint160(bytes20(params.path[0:20])));

        uint256 i;
        uint256 offset = 0;
        while (offset < params.path.length - 20) {
            offset += 23; // token (20) + fee (3)
            tokens[++i] = address(uint160(bytes20(params.path[offset:offset + 20])));
        }

        // Calculate input amount through all hops in reverse
        uint256 currentAmount = params.amountOut;
        for (i = tokens.length - 1; i > 0; i--) {
            currentAmount = (currentAmount * 1e18) / prices[tokens[i - 1]][tokens[i]];
        }
        amountIn = currentAmount;

        require(amountIn <= params.amountInMaximum, "UniswapV3Mock: EXCESSIVE_INPUT_AMOUNT");

        // Transfer tokens
        IERC20(tokens[0]).transferFrom(msg.sender, address(this), amountIn);
        IERC20(tokens[tokens.length - 1]).transfer(params.recipient, params.amountOut);

        return amountIn;
    }

    function uniswapV3SwapCallback(int256, int256, bytes calldata) external pure override {
        revert("UniswapV3Mock: UNIMPLEMENTED");
    }
}
