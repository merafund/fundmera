// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 fundmera.com

// https://github.com/merafund
pragma solidity ^0.8.0;
pragma abicoder v2;

import {IUniswapV2Router02} from "../interfaces/IUniswapV2Router02.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract UniswapV2MockWithDecimals is IUniswapV2Router02 {
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

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override returns (uint256[] memory amounts) {
        require(deadline >= block.timestamp, "UniswapV2Mock: EXPIRED");

        amounts = new uint256[](path.length);
        amounts[0] = amountIn;

        // Calculate output amounts through all hops
        for (uint256 i = 0; i < path.length - 1; i++) {
            uint8 currentDecimals = IERC20Metadata(path[i]).decimals();
            uint8 nextDecimals = IERC20Metadata(path[i + 1]).decimals();

            uint256 normalizedAmount = amounts[i] * 10 ** (18 - currentDecimals);
            amounts[i + 1] = (normalizedAmount * prices[path[i]][path[i + 1]]) / 1e18;
            amounts[i + 1] = amounts[i + 1] / 10 ** (18 - nextDecimals);
        }

        require(amounts[amounts.length - 1] >= amountOutMin, "UniswapV2Mock: INSUFFICIENT_OUTPUT_AMOUNT");

        // Transfer tokens
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        IERC20(path[path.length - 1]).transfer(to, amounts[amounts.length - 1]);

        return amounts;
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override returns (uint256[] memory amounts) {
        require(deadline >= block.timestamp, "UniswapV2Mock: EXPIRED");

        amounts = new uint256[](path.length);
        amounts[amounts.length - 1] = amountOut;

        // Calculate input amounts through all hops in reverse
        for (uint256 i = path.length - 1; i > 0; i--) {
            uint8 currentDecimals = IERC20Metadata(path[i]).decimals();
            uint8 prevDecimals = IERC20Metadata(path[i - 1]).decimals();

            uint256 normalizedAmount = amounts[i] * 10 ** (18 - currentDecimals);
            amounts[i - 1] = (normalizedAmount * 1e18) / prices[path[i - 1]][path[i]];
            amounts[i - 1] = amounts[i - 1] / 10 ** (18 - prevDecimals);
        }

        require(amounts[0] <= amountInMax, "UniswapV2Mock: EXCESSIVE_INPUT_AMOUNT");

        // Transfer tokens
        IERC20(path[0]).transferFrom(msg.sender, address(this), amounts[0]);
        IERC20(path[path.length - 1]).transfer(to, amountOut);

        return amounts;
    }

    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        override
        returns (uint256[] memory amounts)
    {
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;

        // Calculate output amounts through all hops
        for (uint256 i = 0; i < path.length - 1; i++) {
            uint8 currentDecimals = IERC20Metadata(path[i]).decimals();
            uint8 nextDecimals = IERC20Metadata(path[i + 1]).decimals();

            uint256 normalizedAmount = amounts[i] * 10 ** (18 - currentDecimals);
            amounts[i + 1] = (normalizedAmount * prices[path[i]][path[i + 1]]) / 1e18;
            amounts[i + 1] = amounts[i + 1] / 10 ** (18 - nextDecimals);
        }

        return amounts;
    }

    function getAmountsIn(uint256 amountOut, address[] calldata path)
        external
        view
        override
        returns (uint256[] memory amounts)
    {
        amounts = new uint256[](path.length);
        amounts[amounts.length - 1] = amountOut;

        // Calculate input amounts through all hops in reverse
        for (uint256 i = path.length - 1; i > 0; i--) {
            uint8 currentDecimals = IERC20Metadata(path[i]).decimals();
            uint8 prevDecimals = IERC20Metadata(path[i - 1]).decimals();

            uint256 normalizedAmount = amounts[i] * 10 ** (18 - currentDecimals);
            amounts[i - 1] = (normalizedAmount * 1e18) / prices[path[i - 1]][path[i]];
            amounts[i - 1] = amounts[i - 1] / 10 ** (18 - prevDecimals);
        }

        return amounts;
    }

    // Required interface functions that are not used in our tests
    function WETH() external pure override returns (address) {
        return address(0);
    }

    function factory() external pure override returns (address) {
        return address(0);
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external override returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        revert("Not implemented");
    }

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable override returns (uint256 amountToken, uint256 amountETH, uint256 liquidity) {
        revert("Not implemented");
    }

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external override returns (uint256 amountA, uint256 amountB) {
        revert("Not implemented");
    }

    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external override returns (uint256 amountToken, uint256 amountETH) {
        revert("Not implemented");
    }

    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override returns (uint256 amountA, uint256 amountB) {
        revert("Not implemented");
    }

    function removeLiquidityETHWithPermit(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override returns (uint256 amountToken, uint256 amountETH) {
        revert("Not implemented");
    }

    function swapExactETHForTokens(uint256 amountOutMin, address[] calldata path, address to, uint256 deadline)
        external
        payable
        override
        returns (uint256[] memory amounts)
    {
        revert("Not implemented");
    }

    function swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override returns (uint256[] memory amounts) {
        revert("Not implemented");
    }

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override returns (uint256[] memory amounts) {
        revert("Not implemented");
    }

    function swapETHForExactTokens(uint256 amountOut, address[] calldata path, address to, uint256 deadline)
        external
        payable
        override
        returns (uint256[] memory amounts)
    {
        revert("Not implemented");
    }

    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB)
        external
        pure
        override
        returns (uint256 amountB)
    {
        revert("Not implemented");
    }

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        external
        pure
        override
        returns (uint256 amountOut)
    {
        revert("Not implemented");
    }

    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        external
        pure
        override
        returns (uint256 amountIn)
    {
        revert("Not implemented");
    }

    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external override returns (uint256 amountETH) {
        revert("Not implemented");
    }

    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override returns (uint256 amountETH) {
        revert("Not implemented");
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override {
        revert("Not implemented");
    }

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable override {
        revert("Not implemented");
    }

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override {
        revert("Not implemented");
    }
}
