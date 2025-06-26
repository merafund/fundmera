// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 fundmera.com

// https://github.com/merafund
pragma solidity ^0.8.0;
pragma abicoder v2;

import {IQuoterV2} from "../../src/interfaces/IQuoterV2.sol";

// Mock contract for QuoterV2 with fixed quotes
contract QuoterV2Mock is IQuoterV2 {
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
        returns (
            uint256 amountOut,
            uint160[] memory sqrtPriceX96AfterList,
            uint32[] memory initializedTicksCrossedList,
            uint256 gasEstimate
        )
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

        // Mock values for other return parameters
        sqrtPriceX96AfterList = new uint160[](1);
        sqrtPriceX96AfterList[0] = uint160(1e18);

        initializedTicksCrossedList = new uint32[](1);
        initializedTicksCrossedList[0] = 1;

        gasEstimate = 100000;

        return (amountOut, sqrtPriceX96AfterList, initializedTicksCrossedList, gasEstimate);
    }

    function quoteExactInputSingle(QuoteExactInputSingleParams calldata params)
        external
        returns (uint256 amountOut, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed, uint256 gasEstimate)
    {
        amountOut = (params.amountIn * prices[params.tokenIn][params.tokenOut]) / 1e18;
        sqrtPriceX96After = uint160(1e18);
        initializedTicksCrossed = 1;
        gasEstimate = 100000;
        return (amountOut, sqrtPriceX96After, initializedTicksCrossed, gasEstimate);
    }

    function quoteExactOutput(bytes calldata path, uint256 amountOut)
        external
        returns (
            uint256 amountIn,
            uint160[] memory sqrtPriceX96AfterList,
            uint32[] memory initializedTicksCrossedList,
            uint256 gasEstimate
        )
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

        // Mock values for other return parameters
        sqrtPriceX96AfterList = new uint160[](1);
        sqrtPriceX96AfterList[0] = uint160(1e18);

        initializedTicksCrossedList = new uint32[](1);
        initializedTicksCrossedList[0] = 1;

        gasEstimate = 100000;

        return (amountIn, sqrtPriceX96AfterList, initializedTicksCrossedList, gasEstimate);
    }

    function quoteExactOutputSingle(QuoteExactOutputSingleParams calldata params)
        external
        returns (uint256 amountIn, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed, uint256 gasEstimate)
    {
        amountIn = (params.amount * 1e18) / prices[params.tokenIn][params.tokenOut];
        sqrtPriceX96After = uint160(1e18);
        initializedTicksCrossed = 1;
        gasEstimate = 100000;
        return (amountIn, sqrtPriceX96After, initializedTicksCrossed, gasEstimate);
    }
}
