// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 fundmera.com

// https://github.com/merafund
pragma solidity ^0.8.0;
pragma abicoder v2;

import {IQuoterQuickswap} from "../../src/interfaces/IQuoterQuickswap.sol";

// Mock contract for QuoterQuickswap with fixed quotes
contract QuoterQuickswapMock is IQuoterQuickswap {
    // Price mapping for token pairs (token0 -> token1 -> price)
    mapping(address => mapping(address => uint256)) public prices;

    // Set price for token pair (price = token1/token0)
    function setPrice(address token0, address token1, uint256 price) external {
        prices[token0][token1] = price;
        // Set reverse price
        prices[token1][token0] = 1e18 * 1e18 / price;
    }

    function quoteExactInput(bytes calldata path, uint256 amountIn)
        external
        returns (uint256 amountOut, uint16[] memory fees)
    {
        // Extract first and last token from path
        address tokenIn;
        address tokenOut;

        // Get first token from path (first 20 bytes)
        require(path.length >= 20, "Invalid path length");
        assembly {
            tokenIn := shr(96, calldataload(path.offset))
        }

        // Get last token from path (last 20 bytes)
        uint256 lastTokenPos = path.length - 20;
        assembly {
            tokenOut := shr(96, calldataload(add(path.offset, lastTokenPos)))
        }

        // Calculate output amount based on fixed price
        amountOut = (amountIn * prices[tokenIn][tokenOut]) / 1e18;

        // Mock fees
        fees = new uint16[](1);
        fees[0] = 500; // 0.05%

        return (amountOut, fees);
    }

    function quoteExactInputSingle(address tokenIn, address tokenOut, uint256 amountIn, uint160 limitSqrtPrice)
        external
        returns (uint256 amountOut, uint16 fee)
    {
        amountOut = (amountIn * prices[tokenIn][tokenOut]) / 1e18;
        fee = 500; // 0.05%
        return (amountOut, fee);
    }

    function quoteExactOutput(bytes calldata path, uint256 amountOut)
        external
        returns (uint256 amountIn, uint16[] memory fees)
    {
        // Extract first and last token from path
        address tokenIn;
        address tokenOut;

        // Get first token from path (first 20 bytes)
        require(path.length >= 20, "Invalid path length");
        assembly {
            tokenIn := shr(96, calldataload(path.offset))
        }

        // Get last token from path (last 20 bytes)
        uint256 lastTokenPos = path.length - 20;
        assembly {
            tokenOut := shr(96, calldataload(add(path.offset, lastTokenPos)))
        }

        // Calculate input amount based on fixed price
        amountIn = (amountOut * 1e18) / prices[tokenIn][tokenOut];

        // Mock fees
        fees = new uint16[](1);
        fees[0] = 500; // 0.05%

        return (amountIn, fees);
    }

    function quoteExactOutputSingle(address tokenIn, address tokenOut, uint256 amountOut, uint160 limitSqrtPrice)
        external
        returns (uint256 amountIn, uint16 fee)
    {
        amountIn = (amountOut * 1e18) / prices[tokenIn][tokenOut];
        fee = 500; // 0.05%
        return (amountIn, fee);
    }
}
