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
import {ISwapRouterBase} from "../src/interfaces/ISwapRouterBase.sol";
import {UniswapV3Mock} from "../src/mocks/UniswapV3Mock.sol";

contract MainVaultSwapLibraryTest is Test {
    using MainVaultSwapLibrary for *;

    mapping(address => bool) public availableRouterByAdmin;
    mapping(address => bool) public availableTokensByAdmin;

    address public router;
    UniswapV3Mock public swapRouterMock;
    MockERC20 public tokenIn;
    MockERC20 public tokenOut;
    address public user;

    function setUp() public {
        router = address(0x1);
        tokenIn = new MockERC20("TokenIn", "IN", 18);
        tokenOut = new MockERC20("TokenOut", "OUT", 18);
        user = address(0x2);
    }

    // Helper function to setup mock router for ISwapRouterBase tests
    function _setupMockRouter() internal {
        swapRouterMock = new UniswapV3Mock();

        // Setup tokens and router
        availableRouterByAdmin[address(swapRouterMock)] = true;
        availableTokensByAdmin[address(tokenIn)] = true;
        availableTokensByAdmin[address(tokenOut)] = true;

        // Set price for token swap (1:2 ratio)
        swapRouterMock.setPrice(address(tokenIn), address(tokenOut), 2e18);

        // Mint tokens to this contract for testing
        tokenIn.mint(address(this), 1000000 * 10 ** 18);
        tokenOut.mint(address(this), 1000000 * 10 ** 18);

        // Mint tokens to swapRouterMock for swaps
        tokenIn.mint(address(swapRouterMock), 1000000 * 10 ** 18);
        tokenOut.mint(address(swapRouterMock), 1000000 * 10 ** 18);
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

    // ==================== TESTS FOR ISwapRouterBase (deadline == 0) ====================

    // Test executeExactInputSingle with deadline = 0 (uses ISwapRouterBase)
    function testExecuteExactInputSingle_DeadlineZero_UsesSwapRouterBase() public {
        _setupMockRouter();

        DataTypes.DelegateExactInputSingleParams memory params = DataTypes.DelegateExactInputSingleParams({
            router: address(swapRouterMock),
            tokenIn: address(tokenIn),
            tokenOut: address(tokenOut),
            fee: 3000,
            deadline: 0, // This triggers ISwapRouterBase usage
            amountIn: 1e18,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0,
            swapType: DataTypes.SwapType.Default
        });

        uint256 amountOut = MainVaultSwapLibrary.executeExactInputSingle(
            address(swapRouterMock), params, availableRouterByAdmin, availableTokensByAdmin
        );

        // Verify the swap was successful
        assertEq(amountOut, 2e18); // 1e18 * 2 = 2e18
    }

    // Test executeExactInput with deadline = 0 (uses ISwapRouterBase)
    function testExecuteExactInput_DeadlineZero_UsesSwapRouterBase() public {
        _setupMockRouter();
        bytes memory path = abi.encodePacked(address(tokenIn), uint24(3000), address(tokenOut));

        DataTypes.DelegateExactInputParams memory params = DataTypes.DelegateExactInputParams({
            router: address(swapRouterMock),
            path: path,
            deadline: 0, // This triggers ISwapRouterBase usage
            amountIn: 1e18,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        // Expect event emission (check only the event, not other logs like Approval)
        vm.expectEmit(false, false, false, false);
        emit MainVaultSwapLibrary.ExactInputDelegateExecuted(
            address(swapRouterMock),
            address(tokenIn),
            address(tokenOut),
            1e18,
            2e18 // Expected output based on 1:2 price ratio
        );

        uint256 amountOut = MainVaultSwapLibrary.executeExactInput(
            address(swapRouterMock), params, availableRouterByAdmin, availableTokensByAdmin
        );

        // Verify the swap was successful
        assertEq(amountOut, 2e18); // 1e18 * 2 = 2e18
    }

    // Test executeExactOutputSingle with deadline = 0 (uses ISwapRouterBase)
    function testExecuteExactOutputSingle_DeadlineZero_UsesSwapRouterBase() public {
        _setupMockRouter();
        DataTypes.DelegateExactOutputSingleParams memory params = DataTypes.DelegateExactOutputSingleParams({
            router: address(swapRouterMock),
            tokenIn: address(tokenIn),
            tokenOut: address(tokenOut),
            fee: 3000,
            deadline: 0, // This triggers ISwapRouterBase usage
            amountOut: 2e18,
            amountInMaximum: 5e18,
            sqrtPriceLimitX96: 0,
            swapType: DataTypes.SwapType.Default
        });

        // Expect event emission (check only the event, not other logs like Approval)
        vm.expectEmit(false, false, false, false);
        emit MainVaultSwapLibrary.ExactOutputSingleDelegateExecuted(
            address(swapRouterMock),
            address(tokenIn),
            address(tokenOut),
            1e18, // Expected input based on 1:2 price ratio
            2e18
        );

        uint256 amountIn = MainVaultSwapLibrary.executeExactOutputSingle(
            address(swapRouterMock), params, availableRouterByAdmin, availableTokensByAdmin
        );

        // Verify the swap was successful
        assertEq(amountIn, 1e18); // 2e18 / 2 = 1e18
    }

    // Test executeExactOutput with deadline = 0 (uses ISwapRouterBase)
    function testExecuteExactOutput_DeadlineZero_UsesSwapRouterBase() public {
        _setupMockRouter();
        bytes memory path = abi.encodePacked(address(tokenIn), uint24(3000), address(tokenOut));

        DataTypes.DelegateExactOutputParams memory params = DataTypes.DelegateExactOutputParams({
            router: address(swapRouterMock),
            path: path,
            deadline: 0, // This triggers ISwapRouterBase usage
            amountOut: 2e18,
            amountInMaximum: 5e18,
            swapType: DataTypes.SwapType.Default
        });

        // Expect event emission (check only the event, not other logs like Approval)
        vm.expectEmit(false, false, false, false);
        emit MainVaultSwapLibrary.ExactOutputDelegateExecuted(
            address(swapRouterMock),
            address(tokenIn),
            address(tokenOut),
            1e18, // Expected input based on 1:2 price ratio
            2e18
        );

        uint256 amountIn = MainVaultSwapLibrary.executeExactOutput(
            address(swapRouterMock), params, availableRouterByAdmin, availableTokensByAdmin
        );

        // Verify the swap was successful
        assertEq(amountIn, 1e18); // 2e18 / 2 = 1e18
    }

    // Test executeExactInputSingle with deadline > 0 (uses ISwapRouter)
    function testExecuteExactInputSingle_DeadlineNonZero_UsesSwapRouter() public {
        _setupMockRouter();
        DataTypes.DelegateExactInputSingleParams memory params = DataTypes.DelegateExactInputSingleParams({
            router: address(swapRouterMock),
            tokenIn: address(tokenIn),
            tokenOut: address(tokenOut),
            fee: 3000,
            deadline: block.timestamp + 1, // This triggers ISwapRouter usage
            amountIn: 1e18,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0,
            swapType: DataTypes.SwapType.Default
        });

        // Expect event emission (check only the event, not other logs like Approval)
        vm.expectEmit(false, false, false, false);
        emit MainVaultSwapLibrary.ExactInputSingleDelegateExecuted(
            address(swapRouterMock),
            address(tokenIn),
            address(tokenOut),
            1e18,
            2e18 // Expected output based on 1:2 price ratio
        );

        uint256 amountOut = MainVaultSwapLibrary.executeExactInputSingle(
            address(swapRouterMock), params, availableRouterByAdmin, availableTokensByAdmin
        );

        // Verify the swap was successful
        assertEq(amountOut, 2e18); // 1e18 * 2 = 2e18
    }

    // Test executeExactInput with deadline > 0 (uses ISwapRouter)
    function testExecuteExactInput_DeadlineNonZero_UsesSwapRouter() public {
        _setupMockRouter();
        bytes memory path = abi.encodePacked(address(tokenIn), uint24(3000), address(tokenOut));

        DataTypes.DelegateExactInputParams memory params = DataTypes.DelegateExactInputParams({
            router: address(swapRouterMock),
            path: path,
            deadline: block.timestamp + 1, // This triggers ISwapRouter usage
            amountIn: 1e18,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        // Expect event emission (check only the event, not other logs like Approval)
        vm.expectEmit(false, false, false, false);
        emit MainVaultSwapLibrary.ExactInputDelegateExecuted(
            address(swapRouterMock),
            address(tokenIn),
            address(tokenOut),
            1e18,
            2e18 // Expected output based on 1:2 price ratio
        );

        uint256 amountOut = MainVaultSwapLibrary.executeExactInput(
            address(swapRouterMock), params, availableRouterByAdmin, availableTokensByAdmin
        );

        // Verify the swap was successful
        assertEq(amountOut, 2e18); // 1e18 * 2 = 2e18
    }

    // Test executeExactOutputSingle with deadline > 0 (uses ISwapRouter)
    function testExecuteExactOutputSingle_DeadlineNonZero_UsesSwapRouter() public {
        _setupMockRouter();
        DataTypes.DelegateExactOutputSingleParams memory params = DataTypes.DelegateExactOutputSingleParams({
            router: address(swapRouterMock),
            tokenIn: address(tokenIn),
            tokenOut: address(tokenOut),
            fee: 3000,
            deadline: block.timestamp + 1, // This triggers ISwapRouter usage
            amountOut: 2e18,
            amountInMaximum: 5e18,
            sqrtPriceLimitX96: 0,
            swapType: DataTypes.SwapType.Default
        });

        // Expect event emission (check only the event, not other logs like Approval)
        vm.expectEmit(false, false, false, false);
        emit MainVaultSwapLibrary.ExactOutputSingleDelegateExecuted(
            address(swapRouterMock),
            address(tokenIn),
            address(tokenOut),
            1e18, // Expected input based on 1:2 price ratio
            2e18
        );

        uint256 amountIn = MainVaultSwapLibrary.executeExactOutputSingle(
            address(swapRouterMock), params, availableRouterByAdmin, availableTokensByAdmin
        );

        // Verify the swap was successful
        assertEq(amountIn, 1e18); // 2e18 / 2 = 1e18
    }

    // Test executeExactOutput with deadline > 0 (uses ISwapRouter)
    function testExecuteExactOutput_DeadlineNonZero_UsesSwapRouter() public {
        _setupMockRouter();
        bytes memory path = abi.encodePacked(address(tokenIn), uint24(3000), address(tokenOut));

        DataTypes.DelegateExactOutputParams memory params = DataTypes.DelegateExactOutputParams({
            router: address(swapRouterMock),
            path: path,
            deadline: block.timestamp + 1, // This triggers ISwapRouter usage
            amountOut: 2e18,
            amountInMaximum: 5e18,
            swapType: DataTypes.SwapType.Default
        });

        // Expect event emission (check only the event, not other logs like Approval)
        vm.expectEmit(false, false, false, false);
        emit MainVaultSwapLibrary.ExactOutputDelegateExecuted(
            address(swapRouterMock),
            address(tokenIn),
            address(tokenOut),
            1e18, // Expected input based on 1:2 price ratio
            2e18
        );

        uint256 amountIn = MainVaultSwapLibrary.executeExactOutput(
            address(swapRouterMock), params, availableRouterByAdmin, availableTokensByAdmin
        );

        // Verify the swap was successful
        assertEq(amountIn, 1e18); // 2e18 / 2 = 1e18
    }

    // Test that both ISwapRouterBase and ISwapRouter produce same results
    function testSwapRouterBaseAndSwapRouterProduceSameResults() public {
        _setupMockRouter();
        uint256 amountIn = 1e18;
        uint256 expectedAmountOut = 2e18;

        // Test with deadline = 0 (ISwapRouterBase)
        DataTypes.DelegateExactInputSingleParams memory paramsBase = DataTypes.DelegateExactInputSingleParams({
            router: address(swapRouterMock),
            tokenIn: address(tokenIn),
            tokenOut: address(tokenOut),
            fee: 3000,
            deadline: 0,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0,
            swapType: DataTypes.SwapType.Default
        });

        uint256 amountOutBase = MainVaultSwapLibrary.executeExactInputSingle(
            address(swapRouterMock), paramsBase, availableRouterByAdmin, availableTokensByAdmin
        );

        // Test with deadline > 0 (ISwapRouter)
        DataTypes.DelegateExactInputSingleParams memory paramsRouter = DataTypes.DelegateExactInputSingleParams({
            router: address(swapRouterMock),
            tokenIn: address(tokenIn),
            tokenOut: address(tokenOut),
            fee: 3000,
            deadline: block.timestamp + 1,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0,
            swapType: DataTypes.SwapType.Default
        });

        uint256 amountOutRouter = MainVaultSwapLibrary.executeExactInputSingle(
            address(swapRouterMock), paramsRouter, availableRouterByAdmin, availableTokensByAdmin
        );

        // Both should produce the same result
        assertEq(amountOutBase, expectedAmountOut);
        assertEq(amountOutRouter, expectedAmountOut);
        assertEq(amountOutBase, amountOutRouter);
    }
}
