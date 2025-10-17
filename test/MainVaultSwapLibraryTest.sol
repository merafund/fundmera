// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 fundmera.com

// https://github.com/merafund
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {MainVaultSwapLibrary} from "../src/utils/MainVaultSwapLibrary.sol";
import {DataTypes} from "../src/utils/DataTypes.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {ISwapRouter} from "../src/interfaces/ISwapRouter.sol";

contract MainVaultSwapLibraryTest is Test {
    using MainVaultSwapLibrary for *;

    mapping(address => bool) public availableRouterByAdmin;
    mapping(address => bool) public availableTokensByAdmin;

    address public router;
    MockERC20 public tokenIn;
    MockERC20 public tokenOut;
    address public user;

    function setUp() public {
        router = address(0x1);
        tokenIn = new MockERC20("TokenIn", "IN", 18);
        tokenOut = new MockERC20("TokenOut", "OUT", 18);
        user = address(0x2);
    }

    // Tests for executeExactInputSingle
    function testExecuteExactInputSingle_RouterNotAvailable() public {
        DataTypes.DelegateExactInputSingleParams memory params = DataTypes.DelegateExactInputSingleParams({
            router: address(router),
            tokenIn: address(tokenIn),
            tokenOut: address(tokenOut),
            fee: 3000,
            deadline: block.timestamp + 1,
            amountIn: 1e18,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(MainVaultSwapLibrary.RouterNotAvailable.selector);
        MainVaultSwapLibrary.executeExactInputSingle(router, params, availableRouterByAdmin, availableTokensByAdmin);
    }

    function testExecuteExactInputSingle_ZeroAmountNotAllowed() public {
        availableRouterByAdmin[router] = true;

        DataTypes.DelegateExactInputSingleParams memory params = DataTypes.DelegateExactInputSingleParams({
            router: address(router),
            tokenIn: address(tokenIn),
            tokenOut: address(tokenOut),
            fee: 3000,
            deadline: block.timestamp + 1,
            amountIn: 0, // Zero amount
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(MainVaultSwapLibrary.ZeroAmountNotAllowed.selector);
        MainVaultSwapLibrary.executeExactInputSingle(router, params, availableRouterByAdmin, availableTokensByAdmin);
    }

    function testExecuteExactInputSingle_TokenNotAvailable() public {
        availableRouterByAdmin[router] = true;

        DataTypes.DelegateExactInputSingleParams memory params = DataTypes.DelegateExactInputSingleParams({
            router: address(router),
            tokenIn: address(tokenIn),
            tokenOut: address(tokenOut),
            fee: 3000,
            deadline: block.timestamp + 1,
            amountIn: 1e18,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(MainVaultSwapLibrary.TokenNotAvailable.selector);
        MainVaultSwapLibrary.executeExactInputSingle(router, params, availableRouterByAdmin, availableTokensByAdmin);
    }

    // Tests for executeExactInput
    function testExecuteExactInput_RouterNotAvailable() public {
        bytes memory path = abi.encodePacked(address(tokenIn), uint24(3000), address(tokenOut));

        DataTypes.DelegateExactInputParams memory params = DataTypes.DelegateExactInputParams({
            router: address(router),
            path: path,
            deadline: block.timestamp + 1,
            amountIn: 1e18,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(MainVaultSwapLibrary.RouterNotAvailable.selector);
        MainVaultSwapLibrary.executeExactInput(router, params, availableRouterByAdmin, availableTokensByAdmin);
    }

    function testExecuteExactInput_ZeroAmountNotAllowed() public {
        availableRouterByAdmin[router] = true;

        bytes memory path = abi.encodePacked(address(tokenIn), uint24(3000), address(tokenOut));

        DataTypes.DelegateExactInputParams memory params = DataTypes.DelegateExactInputParams({
            router: address(router),
            path: path,
            deadline: block.timestamp + 1,
            amountIn: 0, // Zero amount
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(MainVaultSwapLibrary.ZeroAmountNotAllowed.selector);
        MainVaultSwapLibrary.executeExactInput(router, params, availableRouterByAdmin, availableTokensByAdmin);
    }

    function testExecuteExactInput_TokenNotAvailable() public {
        availableRouterByAdmin[router] = true;

        bytes memory path = abi.encodePacked(address(tokenIn), uint24(3000), address(tokenOut));

        DataTypes.DelegateExactInputParams memory params = DataTypes.DelegateExactInputParams({
            router: address(router),
            path: path,
            deadline: block.timestamp + 1,
            amountIn: 1e18,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(MainVaultSwapLibrary.TokenNotAvailable.selector);
        MainVaultSwapLibrary.executeExactInput(router, params, availableRouterByAdmin, availableTokensByAdmin);
    }

    // Tests for executeExactOutputSingle
    function testExecuteExactOutputSingle_RouterNotAvailable() public {
        DataTypes.DelegateExactOutputSingleParams memory params = DataTypes.DelegateExactOutputSingleParams({
            router: address(router),
            tokenIn: address(tokenIn),
            tokenOut: address(tokenOut),
            fee: 3000,
            deadline: block.timestamp + 1,
            amountOut: 1e18,
            amountInMaximum: 2e18,
            sqrtPriceLimitX96: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(MainVaultSwapLibrary.RouterNotAvailable.selector);
        MainVaultSwapLibrary.executeExactOutputSingle(router, params, availableRouterByAdmin, availableTokensByAdmin);
    }

    function testExecuteExactOutputSingle_ZeroAmountNotAllowed() public {
        availableRouterByAdmin[router] = true;

        DataTypes.DelegateExactOutputSingleParams memory params = DataTypes.DelegateExactOutputSingleParams({
            router: address(router),
            tokenIn: address(tokenIn),
            tokenOut: address(tokenOut),
            fee: 3000,
            deadline: block.timestamp + 1,
            amountOut: 0, // Zero amount
            amountInMaximum: 2e18,
            sqrtPriceLimitX96: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(MainVaultSwapLibrary.ZeroAmountNotAllowed.selector);
        MainVaultSwapLibrary.executeExactOutputSingle(router, params, availableRouterByAdmin, availableTokensByAdmin);
    }

    function testExecuteExactOutputSingle_TokenNotAvailable() public {
        availableRouterByAdmin[router] = true;

        DataTypes.DelegateExactOutputSingleParams memory params = DataTypes.DelegateExactOutputSingleParams({
            router: address(router),
            tokenIn: address(tokenIn),
            tokenOut: address(tokenOut),
            fee: 3000,
            deadline: block.timestamp + 1,
            amountOut: 1e18,
            amountInMaximum: 2e18,
            sqrtPriceLimitX96: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(MainVaultSwapLibrary.TokenNotAvailable.selector);
        MainVaultSwapLibrary.executeExactOutputSingle(router, params, availableRouterByAdmin, availableTokensByAdmin);
    }

    // Tests for executeExactOutput
    function testExecuteExactOutput_RouterNotAvailable() public {
        bytes memory path = abi.encodePacked(address(tokenIn), uint24(3000), address(tokenOut));

        DataTypes.DelegateExactOutputParams memory params = DataTypes.DelegateExactOutputParams({
            router: address(router),
            path: path,
            deadline: block.timestamp + 1,
            amountOut: 1e18,
            amountInMaximum: type(uint256).max,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(MainVaultSwapLibrary.RouterNotAvailable.selector);
        MainVaultSwapLibrary.executeExactOutput(router, params, availableRouterByAdmin, availableTokensByAdmin);
    }

    function testExecuteExactOutput_ZeroAmountNotAllowed() public {
        availableRouterByAdmin[router] = true;

        bytes memory path = abi.encodePacked(address(tokenIn), uint24(3000), address(tokenOut));

        DataTypes.DelegateExactOutputParams memory params = DataTypes.DelegateExactOutputParams({
            router: address(router),
            path: path,
            deadline: block.timestamp + 1,
            amountOut: 0, // Zero amount
            amountInMaximum: type(uint256).max,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(MainVaultSwapLibrary.ZeroAmountNotAllowed.selector);
        MainVaultSwapLibrary.executeExactOutput(router, params, availableRouterByAdmin, availableTokensByAdmin);
    }

    function testExecuteExactOutput_TokenNotAvailable() public {
        availableRouterByAdmin[router] = true;

        bytes memory path = abi.encodePacked(address(tokenIn), uint24(3000), address(tokenOut));

        DataTypes.DelegateExactOutputParams memory params = DataTypes.DelegateExactOutputParams({
            router: address(router),
            path: path,
            deadline: block.timestamp + 1,
            amountOut: 1e18,
            amountInMaximum: type(uint256).max,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(MainVaultSwapLibrary.TokenNotAvailable.selector);
        MainVaultSwapLibrary.executeExactOutput(router, params, availableRouterByAdmin, availableTokensByAdmin);
    }

    // Tests for executeSwapExactTokensForTokens
    function testExecuteSwapExactTokensForTokens_RouterNotAvailable() public {
        address[] memory path = new address[](2);
        path[0] = address(tokenIn);
        path[1] = address(tokenOut);

        vm.expectRevert(MainVaultSwapLibrary.RouterNotAvailable.selector);
        MainVaultSwapLibrary.executeSwapExactTokensForTokens(
            router, 1e18, 0, path, block.timestamp + 1, availableRouterByAdmin, availableTokensByAdmin
        );
    }

    function testExecuteSwapExactTokensForTokens_ZeroAmountNotAllowed() public {
        availableRouterByAdmin[router] = true;

        address[] memory path = new address[](2);
        path[0] = address(tokenIn);
        path[1] = address(tokenOut);

        vm.expectRevert(MainVaultSwapLibrary.ZeroAmountNotAllowed.selector);
        MainVaultSwapLibrary.executeSwapExactTokensForTokens(
            router,
            0, // Zero amount
            0,
            path,
            block.timestamp + 1,
            availableRouterByAdmin,
            availableTokensByAdmin
        );
    }

    function testExecuteSwapExactTokensForTokens_TokenNotAvailable() public {
        availableRouterByAdmin[router] = true;

        address[] memory path = new address[](2);
        path[0] = address(tokenIn);
        path[1] = address(tokenOut);

        vm.expectRevert(MainVaultSwapLibrary.TokenNotAvailable.selector);
        MainVaultSwapLibrary.executeSwapExactTokensForTokens(
            router, 1e18, 0, path, block.timestamp + 1, availableRouterByAdmin, availableTokensByAdmin
        );
    }

    // Tests for executeSwapTokensForExactTokens
    function testExecuteSwapTokensForExactTokens_RouterNotAvailable() public {
        address[] memory path = new address[](2);
        path[0] = address(tokenIn);
        path[1] = address(tokenOut);

        vm.expectRevert(MainVaultSwapLibrary.RouterNotAvailable.selector);
        MainVaultSwapLibrary.executeSwapTokensForExactTokens(
            router, 1e18, 2e18, path, block.timestamp + 1, availableRouterByAdmin, availableTokensByAdmin
        );
    }

    function testExecuteSwapTokensForExactTokens_ZeroAmountNotAllowed() public {
        availableRouterByAdmin[router] = true;

        address[] memory path = new address[](2);
        path[0] = address(tokenIn);
        path[1] = address(tokenOut);

        vm.expectRevert(MainVaultSwapLibrary.ZeroAmountNotAllowed.selector);
        MainVaultSwapLibrary.executeSwapTokensForExactTokens(
            router,
            0, // Zero amount
            2e18,
            path,
            block.timestamp + 1,
            availableRouterByAdmin,
            availableTokensByAdmin
        );
    }

    function testExecuteSwapTokensForExactTokens_TokenNotAvailable() public {
        availableRouterByAdmin[router] = true;

        address[] memory path = new address[](2);
        path[0] = address(tokenIn);
        path[1] = address(tokenOut);

        vm.expectRevert(MainVaultSwapLibrary.TokenNotAvailable.selector);
        MainVaultSwapLibrary.executeSwapTokensForExactTokens(
            router, 1e18, 2e18, path, block.timestamp + 1, availableRouterByAdmin, availableTokensByAdmin
        );
    }

    // Tests for executeQuickswapExactInputSingle
    function testExecuteQuickswapExactInputSingle_RouterNotAvailable() public {
        DataTypes.DelegateQuickswapExactInputSingleParams memory params =
            DataTypes.DelegateQuickswapExactInputSingleParams({
                router: router,
                tokenIn: address(tokenIn),
                tokenOut: address(tokenOut),
                amountIn: 1e18,
                amountOutMinimum: 0,
                limitSqrtPrice: 0,
                deadline: block.timestamp + 1,
                swapType: DataTypes.SwapType.Default
            });

        vm.expectRevert(MainVaultSwapLibrary.RouterNotAvailable.selector);
        MainVaultSwapLibrary.executeQuickswapExactInputSingle(
            router, params, availableRouterByAdmin, availableTokensByAdmin
        );
    }

    function testExecuteQuickswapExactInputSingle_ZeroAmountNotAllowed() public {
        availableRouterByAdmin[router] = true;

        DataTypes.DelegateQuickswapExactInputSingleParams memory params =
            DataTypes.DelegateQuickswapExactInputSingleParams({
                router: router,
                tokenIn: address(tokenIn),
                tokenOut: address(tokenOut),
                amountIn: 0, // Zero amount
                amountOutMinimum: 0,
                limitSqrtPrice: 0,
                deadline: block.timestamp + 1,
                swapType: DataTypes.SwapType.Default
            });

        vm.expectRevert(MainVaultSwapLibrary.ZeroAmountNotAllowed.selector);
        MainVaultSwapLibrary.executeQuickswapExactInputSingle(
            router, params, availableRouterByAdmin, availableTokensByAdmin
        );
    }

    function testExecuteQuickswapExactInputSingle_TokenNotAvailable() public {
        availableRouterByAdmin[router] = true;

        DataTypes.DelegateQuickswapExactInputSingleParams memory params =
            DataTypes.DelegateQuickswapExactInputSingleParams({
                router: router,
                tokenIn: address(tokenIn),
                tokenOut: address(tokenOut),
                amountIn: 1e18,
                amountOutMinimum: 0,
                limitSqrtPrice: 0,
                deadline: block.timestamp + 1,
                swapType: DataTypes.SwapType.Default
            });

        vm.expectRevert(MainVaultSwapLibrary.TokenNotAvailable.selector);
        MainVaultSwapLibrary.executeQuickswapExactInputSingle(
            router, params, availableRouterByAdmin, availableTokensByAdmin
        );
    }

    // Tests for executeQuickswapExactInput
    function testExecuteQuickswapExactInput_RouterNotAvailable() public {
        bytes memory path = abi.encodePacked(address(tokenIn), uint24(3000), address(tokenOut));

        DataTypes.DelegateQuickswapExactInputParams memory params = DataTypes.DelegateQuickswapExactInputParams({
            router: router,
            path: path,
            deadline: block.timestamp + 1,
            amountIn: 1e18,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(MainVaultSwapLibrary.RouterNotAvailable.selector);
        MainVaultSwapLibrary.executeQuickswapExactInput(router, params, availableRouterByAdmin, availableTokensByAdmin);
    }

    function testExecuteQuickswapExactInput_ZeroAmountNotAllowed() public {
        availableRouterByAdmin[router] = true;

        bytes memory path = abi.encodePacked(address(tokenIn), uint24(3000), address(tokenOut));

        DataTypes.DelegateQuickswapExactInputParams memory params = DataTypes.DelegateQuickswapExactInputParams({
            router: router,
            path: path,
            deadline: block.timestamp + 1,
            amountIn: 0, // Zero amount
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(MainVaultSwapLibrary.ZeroAmountNotAllowed.selector);
        MainVaultSwapLibrary.executeQuickswapExactInput(router, params, availableRouterByAdmin, availableTokensByAdmin);
    }

    function testExecuteQuickswapExactInput_TokenNotAvailable() public {
        availableRouterByAdmin[router] = true;

        bytes memory path = abi.encodePacked(address(tokenIn), uint24(3000), address(tokenOut));

        DataTypes.DelegateQuickswapExactInputParams memory params = DataTypes.DelegateQuickswapExactInputParams({
            router: router,
            path: path,
            deadline: block.timestamp + 1,
            amountIn: 1e18,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(MainVaultSwapLibrary.TokenNotAvailable.selector);
        MainVaultSwapLibrary.executeQuickswapExactInput(router, params, availableRouterByAdmin, availableTokensByAdmin);
    }

    // Tests for executeQuickswapExactOutputSingle
    function testExecuteQuickswapExactOutputSingle_RouterNotAvailable() public {
        DataTypes.DelegateQuickswapExactOutputSingleParams memory params =
            DataTypes.DelegateQuickswapExactOutputSingleParams({
                router: router,
                tokenIn: address(tokenIn),
                tokenOut: address(tokenOut),
                fee: 3000,
                deadline: block.timestamp + 1,
                amountOut: 1e18,
                amountInMaximum: 2e18,
                limitSqrtPrice: 0,
                swapType: DataTypes.SwapType.Default
            });

        vm.expectRevert(MainVaultSwapLibrary.RouterNotAvailable.selector);
        MainVaultSwapLibrary.executeQuickswapExactOutputSingle(
            router, params, availableRouterByAdmin, availableTokensByAdmin
        );
    }

    function testExecuteQuickswapExactOutputSingle_ZeroAmountNotAllowed() public {
        availableRouterByAdmin[router] = true;

        DataTypes.DelegateQuickswapExactOutputSingleParams memory params =
            DataTypes.DelegateQuickswapExactOutputSingleParams({
                router: router,
                tokenIn: address(tokenIn),
                tokenOut: address(tokenOut),
                fee: 3000,
                deadline: block.timestamp + 1,
                amountOut: 0, // Zero amount
                amountInMaximum: 2e18,
                limitSqrtPrice: 0,
                swapType: DataTypes.SwapType.Default
            });

        vm.expectRevert(MainVaultSwapLibrary.ZeroAmountNotAllowed.selector);
        MainVaultSwapLibrary.executeQuickswapExactOutputSingle(
            router, params, availableRouterByAdmin, availableTokensByAdmin
        );
    }

    function testExecuteQuickswapExactOutputSingle_TokenNotAvailable() public {
        availableRouterByAdmin[router] = true;

        DataTypes.DelegateQuickswapExactOutputSingleParams memory params =
            DataTypes.DelegateQuickswapExactOutputSingleParams({
                router: router,
                tokenIn: address(tokenIn),
                tokenOut: address(tokenOut),
                fee: 3000,
                deadline: block.timestamp + 1,
                amountOut: 1e18,
                amountInMaximum: 2e18,
                limitSqrtPrice: 0,
                swapType: DataTypes.SwapType.Default
            });

        vm.expectRevert(MainVaultSwapLibrary.TokenNotAvailable.selector);
        MainVaultSwapLibrary.executeQuickswapExactOutputSingle(
            router, params, availableRouterByAdmin, availableTokensByAdmin
        );
    }

    // Tests for executeQuickswapExactOutput
    function testExecuteQuickswapExactOutput_RouterNotAvailable() public {
        bytes memory path = abi.encodePacked(address(tokenIn), uint24(3000), address(tokenOut));

        DataTypes.DelegateQuickswapExactOutputParams memory params = DataTypes.DelegateQuickswapExactOutputParams({
            router: router,
            path: path,
            deadline: block.timestamp + 1,
            amountOut: 1e18,
            amountInMaximum: 2e18,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(MainVaultSwapLibrary.RouterNotAvailable.selector);
        MainVaultSwapLibrary.executeQuickswapExactOutput(router, params, availableRouterByAdmin, availableTokensByAdmin);
    }

    function testExecuteQuickswapExactOutput_ZeroAmountNotAllowed() public {
        availableRouterByAdmin[router] = true;

        bytes memory path = abi.encodePacked(address(tokenIn), uint24(3000), address(tokenOut));

        DataTypes.DelegateQuickswapExactOutputParams memory params = DataTypes.DelegateQuickswapExactOutputParams({
            router: router,
            path: path,
            deadline: block.timestamp + 1,
            amountOut: 0, // Zero amount
            amountInMaximum: 2e18,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(MainVaultSwapLibrary.ZeroAmountNotAllowed.selector);
        MainVaultSwapLibrary.executeQuickswapExactOutput(router, params, availableRouterByAdmin, availableTokensByAdmin);
    }

    function testExecuteQuickswapExactOutput_TokenNotAvailable() public {
        availableRouterByAdmin[router] = true;

        bytes memory path = abi.encodePacked(address(tokenIn), uint24(3000), address(tokenOut));

        DataTypes.DelegateQuickswapExactOutputParams memory params = DataTypes.DelegateQuickswapExactOutputParams({
            router: router,
            path: path,
            deadline: block.timestamp + 1,
            amountOut: 1e18,
            amountInMaximum: 2e18,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(MainVaultSwapLibrary.TokenNotAvailable.selector);
        MainVaultSwapLibrary.executeQuickswapExactOutput(router, params, availableRouterByAdmin, availableTokensByAdmin);
    }
}
