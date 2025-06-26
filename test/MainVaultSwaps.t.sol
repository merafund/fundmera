// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 fundmera.com

// https://github.com/merafund
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {MainVault} from "../src/MainVault.sol";
import {IMainVault} from "../src/interfaces/IMainVault.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {UniswapV2Mock} from "../src/mocks/UniswapV2Mock.sol";
import {UniswapV3Mock} from "../src/mocks/UniswapV3Mock.sol";
import {QuickswapV3Mock} from "../src/mocks/QuickswapV3Mock.sol";
import {DataTypes} from "../src/utils/DataTypes.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MainVaultSwapsTest is Test {
    MainVault public vault;
    MockERC20 public token0;
    MockERC20 public token1;
    MockERC20 public token2;
    UniswapV2Mock public uniswapV2;
    UniswapV3Mock public uniswapV3;
    QuickswapV3Mock public quickswapV3;

    // Test addresses
    address public constant ALICE = address(0x1);
    address public constant BOB = address(0x2);

    function setUp() public {
        // Deploy tokens
        token0 = new MockERC20("Token0", "TK0", 18);
        token1 = new MockERC20("Token1", "TK1", 18);
        token2 = new MockERC20("Token2", "TK2", 18);

        // Deploy DEX mocks
        uniswapV2 = new UniswapV2Mock();
        uniswapV3 = new UniswapV3Mock();
        quickswapV3 = new QuickswapV3Mock();

        // Deploy vault implementation
        MainVault vaultImplementation = new MainVault();

        // Initialize vault with ALICE as main investor
        IMainVault.InitParams memory params = IMainVault.InitParams({
            mainInvestor: ALICE,
            backupInvestor: address(0),
            emergencyInvestor: address(0),
            manager: address(0),
            admin: address(this),
            backupAdmin: address(0),
            emergencyAdmin: address(0),
            feeWallet: address(0),
            profitWallet: address(0),
            feePercentage: 0,
            currentImplementationOfInvestmentVault: address(0),
            pauserList: address(0),
            meraPriceOracle: address(0)
        });

        // Deploy proxy
        bytes memory initData = abi.encodeWithSelector(MainVault.initialize.selector, params);
        ERC1967Proxy proxy = new ERC1967Proxy(address(vaultImplementation), initData);
        vault = MainVault(address(proxy));

        // Make tokens and routers available
        vm.startPrank(ALICE);
        IMainVault.TokenAvailability[] memory tokenAvailabilities = new IMainVault.TokenAvailability[](3);
        tokenAvailabilities[0] = IMainVault.TokenAvailability(address(token0), true);
        tokenAvailabilities[1] = IMainVault.TokenAvailability(address(token1), true);
        tokenAvailabilities[2] = IMainVault.TokenAvailability(address(token2), true);
        vault.setTokenAvailabilityByInvestor(tokenAvailabilities);

        address[] memory routers = new address[](3);
        routers[0] = address(uniswapV2);
        routers[1] = address(uniswapV3);
        routers[2] = address(quickswapV3);
        vault.setRouterAvailabilityByInvestor(routers);
        vm.stopPrank();

        vm.startPrank(address(this));
        vault.setTokenAvailabilityByAdmin(tokenAvailabilities);
        IMainVault.RouterAvailability[] memory routerAvailabilities = new IMainVault.RouterAvailability[](3);
        routerAvailabilities[0] = IMainVault.RouterAvailability(address(uniswapV2), true);
        routerAvailabilities[1] = IMainVault.RouterAvailability(address(uniswapV3), true);
        routerAvailabilities[2] = IMainVault.RouterAvailability(address(quickswapV3), true);
        vault.setRouterAvailabilityByAdmin(routerAvailabilities);
        vm.stopPrank();

        // Set prices in DEXes (1 token0 = 2 token1, 1 token1 = 3 token2)
        uniswapV2.setPrice(address(token0), address(token1), 2e18);
        uniswapV2.setPrice(address(token1), address(token2), 3e18);
        uniswapV2.setPrice(address(token0), address(token2), 6e18); // Direct price for token0->token2 (2 * 3 = 6)

        uniswapV3.setPrice(address(token0), address(token1), 2e18);
        uniswapV3.setPrice(address(token1), address(token2), 3e18);
        uniswapV3.setPrice(address(token0), address(token2), 6e18); // Direct price for token0->token2 (2 * 3 = 6)

        quickswapV3.setPrice(address(token0), address(token1), 2e18);
        quickswapV3.setPrice(address(token1), address(token2), 3e18);
        quickswapV3.setPrice(address(token0), address(token2), 6e18); // Direct price for token0->token2 (2 * 3 = 6)

        // Mint tokens to DEX mocks for swaps
        token0.mint(address(uniswapV2), 1000e18);
        token1.mint(address(uniswapV2), 1000e18);
        token2.mint(address(uniswapV2), 1000e18);

        token0.mint(address(uniswapV3), 1000e18);
        token1.mint(address(uniswapV3), 1000e18);
        token2.mint(address(uniswapV3), 1000e18);

        token0.mint(address(quickswapV3), 1000e18);
        token1.mint(address(quickswapV3), 1000e18);
        token2.mint(address(quickswapV3), 1000e18);

        // // Approve DEX mocks to spend vault's tokens
        // vm.startPrank(address(vault));
        // token0.approve(address(uniswapV2), type(uint256).max);
        // token1.approve(address(uniswapV2), type(uint256).max);
        // token2.approve(address(uniswapV2), type(uint256).max);

        // token0.approve(address(uniswapV3), type(uint256).max);
        // token1.approve(address(uniswapV3), type(uint256).max);
        // token2.approve(address(uniswapV3), type(uint256).max);

        // token0.approve(address(quickswapV3), type(uint256).max);
        // token1.approve(address(quickswapV3), type(uint256).max);
        // token2.approve(address(quickswapV3), type(uint256).max);
        // vm.stopPrank();

        // Setup test accounts
        vm.startPrank(ALICE);
        token0.mint(ALICE, 1000e18);
        token1.mint(ALICE, 1000e18);
        token2.mint(ALICE, 1000e18);

        token0.approve(address(vault), type(uint256).max);
        token1.approve(address(vault), type(uint256).max);
        token2.approve(address(vault), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(BOB);
        token0.mint(BOB, 1000e18);
        token1.mint(BOB, 1000e18);
        token2.mint(BOB, 1000e18);

        token0.approve(address(vault), type(uint256).max);
        token1.approve(address(vault), type(uint256).max);
        token2.approve(address(vault), type(uint256).max);
        vm.stopPrank();

        // Deposit initial tokens to vault for testing swaps
        vm.startPrank(ALICE);
        vault.deposit(IERC20(address(token0)), 500e18);
        vault.deposit(IERC20(address(token1)), 500e18);
        vault.deposit(IERC20(address(token2)), 500e18);
        vm.stopPrank();
    }

    function test_SwapExactTokensForTokensUniV2() public {
        vm.startPrank(ALICE);

        uint256 amountIn = 100e18;
        uint256 expectedAmountOut = 200e18; // Based on price 1:2

        uint256 balanceBefore = token1.balanceOf(address(vault));

        address[] memory path = new address[](2);
        path[0] = address(token0);
        path[1] = address(token1);

        vault.swapExactTokensForTokens(
            address(uniswapV2),
            amountIn,
            expectedAmountOut * 95 / 100, // 5% slippage
            path,
            block.timestamp
        );

        uint256 balanceAfter = token1.balanceOf(address(vault));
        assertEq(balanceAfter - balanceBefore, expectedAmountOut, "Incorrect swap amount");

        vm.stopPrank();
    }

    function test_SwapExactTokensForTokensUniV3() public {
        vm.startPrank(ALICE);

        uint256 amountIn = 100e18;
        uint256 expectedAmountOut = 200e18; // Based on price 1:2

        uint256 balanceBefore = token1.balanceOf(address(vault));

        DataTypes.DelegateExactInputSingleParams memory params = DataTypes.DelegateExactInputSingleParams({
            router: address(uniswapV3),
            tokenIn: address(token0),
            tokenOut: address(token1),
            fee: 3000,
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: expectedAmountOut * 95 / 100, // 5% slippage
            sqrtPriceLimitX96: 0,
            swapType: DataTypes.SwapType.Default
        });

        vault.exactInputSingle(params);

        uint256 balanceAfter = token1.balanceOf(address(vault));
        assertEq(balanceAfter - balanceBefore, expectedAmountOut, "Incorrect swap amount");

        vm.stopPrank();
    }

    function test_SwapExactTokensForTokensQuickswap() public {
        vm.startPrank(ALICE);

        uint256 amountIn = 100e18;
        uint256 expectedAmountOut = 200e18; // Based on price 1:2

        uint256 balanceBefore = token1.balanceOf(address(vault));

        DataTypes.DelegateQuickswapExactInputSingleParams memory params = DataTypes
            .DelegateQuickswapExactInputSingleParams({
            router: address(quickswapV3),
            tokenIn: address(token0),
            tokenOut: address(token1),
            amountIn: amountIn,
            amountOutMinimum: expectedAmountOut * 95 / 100, // 5% slippage
            limitSqrtPrice: 0,
            deadline: block.timestamp,
            swapType: DataTypes.SwapType.Default
        });

        vault.quickswapExactInputSingle(params);

        uint256 balanceAfter = token1.balanceOf(address(vault));
        assertEq(balanceAfter - balanceBefore, expectedAmountOut, "Incorrect swap amount");

        vm.stopPrank();
    }

    function test_SwapTokensForExactTokensUniV2() public {
        vm.startPrank(ALICE);

        uint256 amountOut = 200e18;
        uint256 expectedAmountIn = 100e18; // Based on price 1:2

        uint256 balanceBefore = token0.balanceOf(address(vault));

        address[] memory path = new address[](2);
        path[0] = address(token0);
        path[1] = address(token1);

        vault.swapTokensForExactTokens(
            address(uniswapV2),
            amountOut,
            expectedAmountIn * 105 / 100, // 5% slippage
            path,
            block.timestamp
        );

        uint256 balanceAfter = token0.balanceOf(address(vault));
        assertEq(balanceBefore - balanceAfter, expectedAmountIn, "Incorrect swap amount");

        vm.stopPrank();
    }

    function test_SwapTokensForExactTokensUniV3() public {
        vm.startPrank(ALICE);

        uint256 amountOut = 200e18;
        uint256 expectedAmountIn = 100e18; // Based on price 1:2

        uint256 balanceBefore = token0.balanceOf(address(vault));

        DataTypes.DelegateExactOutputSingleParams memory params = DataTypes.DelegateExactOutputSingleParams({
            router: address(uniswapV3),
            tokenIn: address(token0),
            tokenOut: address(token1),
            fee: 3000,
            deadline: block.timestamp,
            amountOut: amountOut,
            amountInMaximum: expectedAmountIn * 105 / 100, // 5% slippage
            sqrtPriceLimitX96: 0,
            swapType: DataTypes.SwapType.Default
        });

        vault.exactOutputSingle(params);

        uint256 balanceAfter = token0.balanceOf(address(vault));
        assertEq(balanceBefore - balanceAfter, expectedAmountIn, "Incorrect swap amount");

        vm.stopPrank();
    }

    function test_SwapTokensForExactTokensQuickswap() public {
        vm.startPrank(ALICE);

        uint256 amountOut = 200e18;
        uint256 expectedAmountIn = 100e18; // Based on price 1:2

        uint256 balanceBefore = token0.balanceOf(address(vault));

        DataTypes.DelegateQuickswapExactOutputSingleParams memory params = DataTypes
            .DelegateQuickswapExactOutputSingleParams({
            router: address(quickswapV3),
            tokenIn: address(token0),
            tokenOut: address(token1),
            fee: 3000,
            deadline: block.timestamp,
            amountOut: amountOut,
            amountInMaximum: expectedAmountIn * 105 / 100, // 5% slippage
            limitSqrtPrice: 0,
            swapType: DataTypes.SwapType.Default
        });

        vault.quickswapExactOutputSingle(params);

        uint256 balanceAfter = token0.balanceOf(address(vault));
        assertEq(balanceBefore - balanceAfter, expectedAmountIn, "Incorrect swap amount");

        vm.stopPrank();
    }

    function test_MultiHopSwapUniV2() public {
        vm.startPrank(ALICE);

        uint256 amountIn = 100e18;
        uint256 expectedAmountOut = 600e18; // 100 -> 200 -> 600 based on prices

        uint256 balanceBefore = token2.balanceOf(address(vault));

        address[] memory path = new address[](3);
        path[0] = address(token0);
        path[1] = address(token1);
        path[2] = address(token2);

        vault.swapExactTokensForTokens(
            address(uniswapV2),
            amountIn,
            expectedAmountOut * 95 / 100, // 5% slippage
            path,
            block.timestamp
        );

        uint256 balanceAfter = token2.balanceOf(address(vault));
        assertEq(balanceAfter - balanceBefore, expectedAmountOut, "Incorrect swap amount");

        vm.stopPrank();
    }

    function test_MultiHopSwapUniV3() public {
        vm.startPrank(ALICE);

        uint256 amountIn = 100e18;
        uint256 expectedAmountOut = 600e18; // 100 -> 200 -> 600 based on prices

        uint256 balanceBefore = token2.balanceOf(address(vault));

        bytes memory path =
            abi.encodePacked(address(token0), uint24(3000), address(token1), uint24(3000), address(token2));

        DataTypes.DelegateExactInputParams memory params = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3),
            path: path,
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: expectedAmountOut * 95 / 100, // 5% slippage
            swapType: DataTypes.SwapType.Default
        });

        vault.exactInput(params);

        uint256 balanceAfter = token2.balanceOf(address(vault));
        assertEq(balanceAfter - balanceBefore, expectedAmountOut, "Incorrect swap amount");

        vm.stopPrank();
    }

    function test_MultiHopSwapQuickswap() public {
        vm.startPrank(ALICE);

        uint256 amountIn = 100e18;
        uint256 expectedAmountOut = 600e18; // 100 * 6 = 600 based on direct price token0->token2

        uint256 balanceBefore = token2.balanceOf(address(vault));

        bytes memory path = abi.encodePacked(address(token0), uint24(3000), address(token2));

        DataTypes.DelegateQuickswapExactInputParams memory params = DataTypes.DelegateQuickswapExactInputParams({
            router: address(quickswapV3),
            path: path,
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: expectedAmountOut * 95 / 100, // 5% slippage
            swapType: DataTypes.SwapType.Default
        });

        vault.quickswapExactInput(params);

        uint256 balanceAfter = token2.balanceOf(address(vault));
        assertEq(balanceAfter - balanceBefore, expectedAmountOut, "Incorrect swap amount");

        vm.stopPrank();
    }

    function test_MultiHopExactOutputUniV3() public {
        vm.startPrank(ALICE);

        uint256 amountOut = 600e18; // Хотим получить 600 token2
        uint256 expectedAmountIn = 100e18; // Ожидаем потратить 100 token0 (из-за цены 1:6)

        uint256 balanceBefore = token0.balanceOf(address(vault));

        bytes memory path =
            abi.encodePacked(address(token0), uint24(3000), address(token1), uint24(3000), address(token2));

        DataTypes.DelegateExactOutputParams memory params = DataTypes.DelegateExactOutputParams({
            router: address(uniswapV3),
            path: path,
            deadline: block.timestamp,
            amountOut: amountOut,
            amountInMaximum: expectedAmountIn * 105 / 100, // 5% slippage
            swapType: DataTypes.SwapType.Default
        });

        vault.exactOutput(params);

        uint256 balanceAfter = token0.balanceOf(address(vault));
        assertEq(balanceBefore - balanceAfter, expectedAmountIn, "Incorrect input amount");

        vm.stopPrank();
    }

    function test_MultiHopExactOutputQuickswap() public {
        vm.startPrank(ALICE);

        uint256 amountOut = 600e18; // Хотим получить 600 token2
        uint256 expectedAmountIn = 100e18; // Ожидаем потратить 100 token0 (из-за цены 1:6)

        uint256 balanceBefore = token0.balanceOf(address(vault));

        bytes memory path = abi.encodePacked(address(token0), uint24(3000), address(token2));

        DataTypes.DelegateQuickswapExactOutputParams memory params = DataTypes.DelegateQuickswapExactOutputParams({
            router: address(quickswapV3),
            path: path,
            amountOut: amountOut,
            amountInMaximum: expectedAmountIn * 105 / 100, // 5% slippage
            deadline: block.timestamp,
            swapType: DataTypes.SwapType.Default
        });

        vault.quickswapExactOutput(params);

        uint256 balanceAfter = token0.balanceOf(address(vault));
        assertEq(balanceBefore - balanceAfter, expectedAmountIn, "Incorrect input amount");

        vm.stopPrank();
    }
}
