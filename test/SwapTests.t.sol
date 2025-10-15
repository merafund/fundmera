// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 fundmera.com

// https://github.com/merafund
pragma solidity ^0.8.29;

import {Test, console} from "forge-std/Test.sol";
import {InvestmentVault} from "../src/InvestmentVault.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DataTypes, IMainVault} from "../src/utils/DataTypes.sol";
import {Constants} from "../src/utils/Constants.sol";
import {UniswapV3Mock} from "../src/mocks/UniswapV3Mock.sol";
import {QuickswapV3Mock} from "../src/mocks/QuickswapV3Mock.sol";
import {QuoterV2Mock} from "../src/mocks/QuoterV2Mock.sol";
import {QuoterQuickswapMock} from "../src/mocks/QuoterQuickswapMock.sol";
import {UniswapV2Mock} from "../src/mocks/UniswapV2Mock.sol";
import {SwapLibrary} from "../src/utils/SwapLibrary.sol";
import {MockMainVault} from "../src/mocks/MockMainVault.sol";
import {MockToken} from "../src/mocks/MockToken.sol";

contract SwapTests is Test {
    InvestmentVault public implementation;
    ERC1967Proxy public proxy;
    InvestmentVault public vault;
    MockToken public tokenMI;
    MockToken public tokenMV;
    MockToken public assetToken1;
    MockToken public assetToken2;
    MockMainVault public mainVault;
    UniswapV3Mock public uniswapV3Router;
    QuickswapV3Mock public quickswapV3Router;
    QuoterV2Mock public quoterV2;
    QuoterQuickswapMock public quoterQuickswap;
    UniswapV2Mock public uniswapV2Router;

    address public owner = address(1);
    address public manager = address(2);
    address public user = address(3);

    uint256 public constant INITIAL_BALANCE = 10000 * 10 ** 18;
    uint256 public constant SWAP_AMOUNT = 1000 * 10 ** 18;

    // Helper function to set up router-quoter pairs
    function _setupRouterQuoterPairs(address router, address quoter) internal {
        DataTypes.RouterQuoterPair[] memory pairs = new DataTypes.RouterQuoterPair[](1);
        pairs[0] = DataTypes.RouterQuoterPair({router: router, quoter: quoter});
        mainVault.setRouterQuoterPairAvailabilityByInvestor(pairs);
        mainVault.setRouterQuoterPairAvailabilityByAdmin(pairs);
    }

    function setUp() public {
        vm.startPrank(owner);

        // Deploy tokens
        tokenMI = new MockToken("MI Token", "MI", 18);
        tokenMV = new MockToken("MV Token", "MV", 18);
        assetToken1 = new MockToken("Asset Token 1", "AT1", 18);
        assetToken2 = new MockToken("Asset Token 2", "AT2", 6);

        // Deploy routers and quoters
        uniswapV3Router = new UniswapV3Mock();
        quickswapV3Router = new QuickswapV3Mock();
        quoterV2 = new QuoterV2Mock();
        quoterQuickswap = new QuoterQuickswapMock();
        uniswapV2Router = new UniswapV2Mock();

        // Deploy main vault
        mainVault = new MockMainVault();
        mainVault.setAvailableToken(address(tokenMI), true);
        mainVault.setAvailableToken(address(tokenMV), true);
        mainVault.setAvailableToken(address(assetToken1), true);
        mainVault.setAvailableToken(address(assetToken2), true);

        // Set up router-quoter pairs
        _setupRouterQuoterPairs(address(uniswapV3Router), address(quoterV2));
        _setupRouterQuoterPairs(address(quickswapV3Router), address(quoterQuickswap));
        _setupRouterQuoterPairs(address(uniswapV2Router), address(uniswapV2Router));

        // Deploy vault
        implementation = new InvestmentVault();
        mainVault.setCurrentImplementation(address(implementation));

        DataTypes.AssetInitData[] memory assets = new DataTypes.AssetInitData[](2);
        assets[0] = DataTypes.AssetInitData({
            token: IERC20(address(assetToken1)),
            shareMV: 4 * 10 ** 17,
            step: 5 * 10 ** 16,
            strategy: DataTypes.Strategy.Zero
        });
        assets[1] = DataTypes.AssetInitData({
            token: IERC20(address(assetToken2)),
            shareMV: 3 * 10 ** 17,
            step: 5 * 10 ** 16,
            strategy: DataTypes.Strategy.First
        });

        DataTypes.InvestmentVaultInitData memory initData = DataTypes.InvestmentVaultInitData({
            mainVault: IMainVault(address(mainVault)),
            tokenMI: IERC20(address(tokenMI)),
            tokenMV: IERC20(address(tokenMV)),
            capitalOfMi: INITIAL_BALANCE,
            shareMI: 7 * 10 ** 17,
            step: 5 * 10 ** 16,
            assets: assets
        });

        bytes memory encodedInitData = abi.encodeWithSelector(InvestmentVault.initialize.selector, initData);
        proxy = new ERC1967Proxy(address(implementation), encodedInitData);
        vault = InvestmentVault(address(proxy));

        // Transfer tokens
        tokenMI.transfer(address(vault), INITIAL_BALANCE);
        tokenMV.mint(address(uniswapV3Router), INITIAL_BALANCE * 10000000000000);
        tokenMV.mint(address(quickswapV3Router), INITIAL_BALANCE * 10000000000000);
        assetToken1.mint(address(uniswapV3Router), INITIAL_BALANCE * 10000000000);
        assetToken1.mint(address(quickswapV3Router), INITIAL_BALANCE * 10000000000);
        assetToken2.mint(address(uniswapV3Router), 1000000000000 * 10 ** 18);
        assetToken2.mint(address(quickswapV3Router), 1000000000000 * 10 ** 18);
        assetToken2.mint(address(uniswapV2Router), 1000000000000 * 10 ** 18);

        // Set prices in mocks
        uniswapV3Router.setPrice(address(tokenMI), address(tokenMV), 5 * 10 ** 17);
        uniswapV3Router.setPrice(address(tokenMV), address(assetToken1), 2 * 10 ** 18);
        uniswapV3Router.setPrice(address(tokenMV), address(assetToken2), 2 * 10 ** 18);
        quoterV2.setPrice(address(tokenMI), address(tokenMV), 5 * 10 ** 17);
        quoterV2.setPrice(address(tokenMV), address(assetToken1), 2 * 10 ** 18);
        quoterV2.setPrice(address(tokenMV), address(assetToken2), 2 * 10 ** 18);

        quickswapV3Router.setPrice(address(tokenMI), address(tokenMV), 5 * 10 ** 17);
        quickswapV3Router.setPrice(address(tokenMV), address(assetToken1), 2 * 10 ** 18);
        quickswapV3Router.setPrice(address(tokenMV), address(assetToken2), 2 * 10 ** 18);
        quoterQuickswap.setPrice(address(tokenMI), address(tokenMV), 5 * 10 ** 17);
        quoterQuickswap.setPrice(address(tokenMV), address(assetToken1), 2 * 10 ** 18);
        quoterQuickswap.setPrice(address(tokenMV), address(assetToken2), 2 * 10 ** 18);

        // Initialize swaps
        bytes memory pathBytesMiMv = abi.encodePacked(address(tokenMI), uint24(3000), address(tokenMV));

        DataTypes.InitSwapsData memory miToMvData = DataTypes.InitSwapsData({
            quouter: address(quoterV2),
            router: address(uniswapV3Router),
            path: new address[](2),
            pathBytes: pathBytesMiMv,
            amountOutMin: 0,
            capital: INITIAL_BALANCE,
            routerType: DataTypes.Router.UniswapV3
        });
        miToMvData.path[0] = address(tokenMI);
        miToMvData.path[1] = address(tokenMV);

        // Approve tokens
        vm.stopPrank();
        vm.startPrank(address(vault));
        tokenMI.approve(address(uniswapV3Router), type(uint256).max);
        tokenMV.approve(address(uniswapV3Router), type(uint256).max);
        tokenMI.approve(address(quickswapV3Router), type(uint256).max);
        tokenMV.approve(address(quickswapV3Router), type(uint256).max);
        tokenMV.approve(address(uniswapV2Router), type(uint256).max);
        assetToken1.approve(address(uniswapV3Router), type(uint256).max);
        assetToken2.approve(address(uniswapV3Router), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(owner);

        // Wait for initialization pause to end
        (,, uint256 pauseToTimestamp,) = vault.vaultState();
        vm.warp(pauseToTimestamp + 1);

        // Initialize MI to MV swap
        vault.initMiToMvSwap(miToMvData, block.timestamp + 1);

        // Initialize MV to Tokens swaps
        DataTypes.InitSwapsData[] memory mvToTokenPaths = new DataTypes.InitSwapsData[](2);
        uint256 totalMVBalanceForAssetSwaps = tokenMV.balanceOf(address(vault));

        bytes memory pathBytesAsset1 = abi.encodePacked(address(tokenMV), uint24(3000), address(assetToken1));
        uint256 capitalForAsset1 = (totalMVBalanceForAssetSwaps * initData.assets[0].shareMV) / (10 ** 18);

        mvToTokenPaths[0] = DataTypes.InitSwapsData({
            quouter: address(quoterV2),
            router: address(uniswapV3Router),
            path: new address[](2),
            pathBytes: pathBytesAsset1,
            amountOutMin: 0,
            capital: capitalForAsset1,
            routerType: DataTypes.Router.UniswapV3
        });
        mvToTokenPaths[0].path[0] = address(tokenMV);
        mvToTokenPaths[0].path[1] = address(assetToken1);

        bytes memory pathBytesAsset2 = abi.encodePacked(address(tokenMV), uint24(3000), address(assetToken2));
        uint256 capitalForAsset2 = (totalMVBalanceForAssetSwaps * initData.assets[1].shareMV) / (10 ** 18);

        mvToTokenPaths[1] = DataTypes.InitSwapsData({
            quouter: address(quoterV2),
            router: address(uniswapV3Router),
            path: new address[](2),
            pathBytes: pathBytesAsset2,
            amountOutMin: 0,
            capital: capitalForAsset2,
            routerType: DataTypes.Router.UniswapV3
        });
        mvToTokenPaths[1].path[0] = address(tokenMV);
        mvToTokenPaths[1].path[1] = address(assetToken2);

        vault.initMvToTokensSwaps(mvToTokenPaths, block.timestamp + 1);

        // tokenMV.transfer(address(vault), SWAP_AMOUNT);

        // Set manager role
        mainVault.setRole(manager, true);

        vm.stopPrank();
    }

    function testExactInputSingle() public {
        vm.startPrank(manager);
        vm.warp(block.timestamp + 31 days);

        bytes memory pathBytes = abi.encodePacked(address(tokenMV), uint24(3000), address(assetToken1));

        uniswapV3Router.setPrice(address(tokenMV), address(assetToken1), 4 * 10 ** 18);

        uint256 amountIn = tokenMV.balanceOf(address(vault)) / 400;

        DataTypes.DelegateExactInputSingleParams memory params = DataTypes.DelegateExactInputSingleParams({
            router: address(uniswapV3Router),
            tokenIn: address(tokenMV),
            tokenOut: address(assetToken1),
            fee: 3000,
            deadline: block.timestamp + 1,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0,
            swapType: DataTypes.SwapType.Default
        });

        uint256 amountOut = vault.exactInputSingle(params);
        assertEq(amountOut, amountIn * 4, "Amount out should be correct");

        vm.stopPrank();
    }

    function testExactInput() public {
        vm.startPrank(manager);
        vm.warp(block.timestamp + 31 days);
        bytes memory pathBytes = abi.encodePacked(address(tokenMV), uint24(3000), address(assetToken1));
        uniswapV3Router.setPrice(address(tokenMV), address(assetToken1), 4 * 10 ** 18);

        uint256 amountIn = tokenMV.balanceOf(address(vault)) / 400;

        DataTypes.DelegateExactInputParams memory params = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytes,
            deadline: block.timestamp + 1,
            amountIn: amountIn,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        uint256 amountOut = vault.exactInput(params);
        assertEq(amountOut, amountIn * 4, "Amount out should be correct");

        vm.stopPrank();
    }

    function testExactInputInBothRouters() public {
        vm.startPrank(manager);
        vm.warp(block.timestamp + 31 days);

        bytes memory pathBytes = abi.encodePacked(address(tokenMV), uint24(3000), address(assetToken1));

        bytes memory pathBytes2 = abi.encodePacked(address(assetToken1), uint24(3000), address(tokenMV));
        uniswapV3Router.setPrice(address(tokenMV), address(assetToken1), 4 * 10 ** 18);

        uint256 amountIn = tokenMV.balanceOf(address(vault)) / 400;

        DataTypes.DelegateExactInputParams memory params = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytes,
            deadline: block.timestamp + 1,
            amountIn: amountIn,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });
        uint256 amountOut = vault.exactInput(params);

        uniswapV3Router.setPrice(address(assetToken1), address(tokenMV), 2 * 10 ** 18);
        uint256 amountIn2 = assetToken1.balanceOf(address(vault)) / 10;

        DataTypes.DelegateExactInputParams memory params2 = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytes2,
            deadline: block.timestamp + 1,
            amountIn: amountIn2,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });
        uint256 amountOut2 = vault.exactInput(params2);

        assertEq(amountOut, amountIn * 4, "Amount out should be correct");
        assertEq(amountOut2, amountIn2 * 2, "Amount out should be correct");
        vm.stopPrank();
    }

    function testExactInputInBothRoutersFirstStrategy() public {
        vm.startPrank(manager);
        vm.warp(block.timestamp + 31 days);

        bytes memory pathBytes = abi.encodePacked(address(tokenMV), uint24(3000), address(assetToken2));

        bytes memory pathBytes2 = abi.encodePacked(address(assetToken2), uint24(3000), address(tokenMV));
        uniswapV3Router.setPrice(address(tokenMV), address(assetToken2), 8 * 10 ** 18);

        uint256 amountIn = tokenMV.balanceOf(address(vault)) / 400;

        DataTypes.DelegateExactInputParams memory params = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytes,
            deadline: block.timestamp + 1,
            amountIn: amountIn,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });
        uint256 amountOut = vault.exactInput(params);

        uniswapV3Router.setPrice(address(assetToken2), address(tokenMV), 2 * 10 ** 18);
        uint256 amountIn2 = assetToken1.balanceOf(address(vault)) / 100;

        DataTypes.DelegateExactInputParams memory params2 = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytes2,
            deadline: block.timestamp + 1,
            amountIn: amountIn2,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });
        uint256 amountOut2 = vault.exactInput(params2);

        assertEq(amountOut, amountIn * 8, "Amount out should be correct");
        assertEq(amountOut2, amountIn2 * 2, "Amount out should be correct");
        vm.stopPrank();
    }

    function testExactInputInBothRoutersFirstStrategy_PriceDidNotIncreaseEnough() public {
        vm.startPrank(manager);

        bytes memory pathBytes = abi.encodePacked(address(tokenMV), uint24(3000), address(assetToken2));

        bytes memory pathBytes2 = abi.encodePacked(address(assetToken2), uint24(3000), address(tokenMV));
        uniswapV3Router.setPrice(address(tokenMV), address(assetToken2), 8 * 10 ** 18);

        uint256 amountIn = tokenMV.balanceOf(address(vault)) / 400;

        DataTypes.DelegateExactInputParams memory params = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytes,
            deadline: block.timestamp + 1,
            amountIn: amountIn,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });
        uint256 amountOut = vault.exactInput(params);

        // Устанавливаем низкую цену, чтобы сработал revert
        uniswapV3Router.setPrice(address(assetToken2), address(tokenMV), 1 * 10 ** 17);
        uint256 amountIn2 = assetToken2.balanceOf(address(vault)) / 100;

        DataTypes.DelegateExactInputParams memory params2 = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytes2,
            deadline: block.timestamp + 1,
            amountIn: amountIn2,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(SwapLibrary.PriceDidNotIncreaseEnough.selector);
        vault.exactInput(params2);

        vm.stopPrank();
    }

    function testExactInputInBothRoutersFirstStrategy_SoldMoreThanExpectedWOB() public {
        vm.startPrank(manager);

        bytes memory pathBytes = abi.encodePacked(address(tokenMV), uint24(3000), address(assetToken2));

        bytes memory pathBytes2 = abi.encodePacked(address(assetToken2), uint24(3000), address(tokenMV));
        uniswapV3Router.setPrice(address(tokenMV), address(assetToken2), 8 * 10 ** 18);

        uint256 amountIn = tokenMV.balanceOf(address(vault)) / 400;

        DataTypes.DelegateExactInputParams memory params = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytes,
            deadline: block.timestamp + 1,
            amountIn: amountIn,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });
        uint256 amountOut = vault.exactInput(params);

        uniswapV3Router.setPrice(address(assetToken2), address(tokenMV), 2 * 10 ** 18);

        uint256 amountIn2 = assetToken2.balanceOf(address(vault)) / 2;

        DataTypes.DelegateExactInputParams memory params2 = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytes2,
            deadline: block.timestamp + 1,
            amountIn: amountIn2,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(SwapLibrary.SoldMoreThanExpectedWOB.selector);
        vault.exactInput(params2);

        vm.stopPrank();
    }

    function testQuickswapExactInputSingle() public {
        vm.startPrank(manager);
        vm.warp(block.timestamp + 31 days);
        bytes memory pathBytes = abi.encodePacked(address(tokenMV), uint24(3000), address(assetToken1));
        quickswapV3Router.setPrice(address(tokenMV), address(assetToken1), 4 * 10 ** 18);

        uint256 amountIn = tokenMV.balanceOf(address(vault)) / 400;

        DataTypes.DelegateQuickswapExactInputSingleParams memory params = DataTypes
            .DelegateQuickswapExactInputSingleParams({
            router: address(quickswapV3Router),
            tokenIn: address(tokenMV),
            tokenOut: address(assetToken1),
            amountIn: amountIn,
            amountOutMinimum: 0,
            limitSqrtPrice: 0,
            deadline: block.timestamp + 1,
            swapType: DataTypes.SwapType.Default
        });

        uint256 amountOut = vault.quickswapExactInputSingle(params);
        assertEq(amountOut, amountIn * 4, "Amount out should be correct");

        vm.stopPrank();
    }

    function testQuickswapExactInput() public {
        vm.startPrank(manager);
        vm.warp(block.timestamp + 31 days);

        bytes memory pathBytes = abi.encodePacked(address(tokenMV), uint24(3000), address(assetToken1));
        quickswapV3Router.setPrice(address(tokenMV), address(assetToken1), 4 * 10 ** 18);

        uint256 amountIn = tokenMV.balanceOf(address(vault)) / 400;

        DataTypes.DelegateQuickswapExactInputParams memory params = DataTypes.DelegateQuickswapExactInputParams({
            router: address(quickswapV3Router),
            path: pathBytes,
            amountIn: amountIn,
            amountOutMinimum: 0,
            deadline: block.timestamp + 1,
            swapType: DataTypes.SwapType.Default
        });

        uint256 amountOut = vault.quickswapExactInput(params);
        assertEq(amountOut, amountIn * 4, "Amount out should be correct");

        vm.stopPrank();
    }

    function testExactInputSingle_OnlyManager() public {
        vm.startPrank(user);

        bytes memory pathBytes = abi.encodePacked(address(tokenMV), uint24(3000), address(assetToken1));

        DataTypes.DelegateExactInputSingleParams memory params = DataTypes.DelegateExactInputSingleParams({
            router: address(uniswapV3Router),
            tokenIn: address(tokenMV),
            tokenOut: address(assetToken1),
            fee: 3000,
            deadline: block.timestamp + 1,
            amountIn: SWAP_AMOUNT,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(InvestmentVault.OnlyManagerError.selector);
        vault.exactInputSingle(params);

        vm.stopPrank();
    }

    function testExactInputSingle_SwapsNotInitialized() public {
        vm.startPrank(owner);

        // Create new vault implementation
        InvestmentVault newImplementation = new InvestmentVault();

        // Prepare minimal initialization data: no initial deposit, no assets.
        // This ensures swaps are not auto-initialized and no pause duration is set.
        DataTypes.AssetInitData[] memory emptyAssets = new DataTypes.AssetInitData[](0);
        DataTypes.InvestmentVaultInitData memory minimalInitData = DataTypes.InvestmentVaultInitData({
            mainVault: IMainVault(address(mainVault)),
            tokenMI: IERC20(address(tokenMI)),
            tokenMV: IERC20(address(tokenMV)),
            capitalOfMi: 0,
            shareMI: 0,
            step: 5 * 10 ** 16,
            assets: emptyAssets
        });
        bytes memory encodedMinimalInitData =
            abi.encodeWithSelector(InvestmentVault.initialize.selector, minimalInitData);

        // Deploy proxy and initialize it
        ERC1967Proxy newProxyInstance = new ERC1967Proxy(address(newImplementation), encodedMinimalInitData);
        InvestmentVault newVaultForTest = InvestmentVault(address(newProxyInstance));
        vm.stopPrank();

        vm.startPrank(manager);

        // Prepare params for the exactInputSingle call
        DataTypes.DelegateExactInputSingleParams memory params = DataTypes.DelegateExactInputSingleParams({
            router: address(uniswapV3Router),
            tokenIn: address(tokenMV),
            tokenOut: address(assetToken1),
            fee: 3000,
            deadline: block.timestamp + 1,
            amountIn: SWAP_AMOUNT,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(InvestmentVault.SwapsNotInitialized.selector);
        newVaultForTest.exactInputSingle(params);

        vm.stopPrank();
    }

    function testExactInputSingle_RouterNotAvailable() public {
        vm.startPrank(manager);

        // Set router as unavailable
        mainVault.setAvailableRouter(address(uniswapV3Router), false);

        DataTypes.DelegateExactInputSingleParams memory params = DataTypes.DelegateExactInputSingleParams({
            router: address(uniswapV3Router),
            tokenIn: address(tokenMV),
            tokenOut: address(assetToken1),
            fee: 3000,
            deadline: block.timestamp + 1,
            amountIn: SWAP_AMOUNT,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(InvestmentVault.RouterNotAvailable.selector);
        vault.exactInputSingle(params);

        vm.stopPrank();
    }

    function testExactInputSingle_TokenNotAvailable() public {
        vm.startPrank(manager);

        // Set token as unavailable
        mainVault.setAvailableToken(address(tokenMV), false);

        bytes memory pathBytes = abi.encodePacked(address(tokenMV), uint24(3000), address(assetToken1));

        DataTypes.DelegateExactInputSingleParams memory params = DataTypes.DelegateExactInputSingleParams({
            router: address(uniswapV3Router),
            tokenIn: address(tokenMV),
            tokenOut: address(assetToken1),
            fee: 3000,
            deadline: block.timestamp + 1,
            amountIn: SWAP_AMOUNT,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(InvestmentVault.TokenNotAvailable.selector);
        vault.exactInputSingle(params);

        vm.stopPrank();
    }

    function testSwapsNotInitialized() public {
        vm.startPrank(owner);

        // Create new vault implementation
        InvestmentVault newVault = new InvestmentVault();
        mainVault.setCurrentImplementation(address(newVault));

        // Prepare minimal initialization data
        DataTypes.AssetInitData[] memory emptyAssets = new DataTypes.AssetInitData[](0);
        DataTypes.InvestmentVaultInitData memory minimalInitData = DataTypes.InvestmentVaultInitData({
            mainVault: IMainVault(address(mainVault)),
            tokenMI: IERC20(address(tokenMI)),
            tokenMV: IERC20(address(tokenMV)),
            capitalOfMi: 0, // No initial deposit to prevent auto-swap initialization
            shareMI: 0,
            step: 5 * 10 ** 16,
            assets: emptyAssets
        });

        bytes memory encodedInitData = abi.encodeWithSelector(InvestmentVault.initialize.selector, minimalInitData);
        ERC1967Proxy newProxy = new ERC1967Proxy(address(newVault), encodedInitData);
        InvestmentVault newVaultProxy = InvestmentVault(address(newProxy));

        vm.stopPrank();
        vm.startPrank(manager);

        // Try to execute swap before initialization
        DataTypes.DelegateExactInputSingleParams memory params = DataTypes.DelegateExactInputSingleParams({
            router: address(uniswapV3Router),
            tokenIn: address(tokenMV),
            tokenOut: address(assetToken1),
            fee: 3000,
            deadline: block.timestamp + 1,
            amountIn: SWAP_AMOUNT,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(InvestmentVault.SwapsNotInitialized.selector);
        newVaultProxy.exactInputSingle(params);

        vm.stopPrank();
    }

    function testOnlyManagerError() public {
        vm.startPrank(user); // Using regular user instead of manager

        DataTypes.DelegateExactInputSingleParams memory params = DataTypes.DelegateExactInputSingleParams({
            router: address(uniswapV3Router),
            tokenIn: address(tokenMV),
            tokenOut: address(assetToken1),
            fee: 3000,
            deadline: block.timestamp + 1,
            amountIn: SWAP_AMOUNT,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(InvestmentVault.OnlyManagerError.selector);
        vault.exactInputSingle(params);

        vm.stopPrank();
    }

    function testSwapExactTokensForTokens() public {
        vm.startPrank(manager);
        vm.warp(block.timestamp + 31 days);

        // Set price for the swap
        uniswapV2Router.setPrice(address(tokenMV), address(assetToken1), 4 * 10 ** 18);

        uint256 amountIn = tokenMV.balanceOf(address(vault)) / 400;
        address[] memory path = new address[](2);
        path[0] = address(tokenMV);
        path[1] = address(assetToken1);

        // Mint tokens to router
        vm.stopPrank();
        vm.startPrank(owner);
        assetToken1.mint(address(uniswapV2Router), amountIn * 4);
        vm.stopPrank();
        vm.startPrank(manager);

        // Approve router to spend tokens
        vm.stopPrank();
        vm.startPrank(address(vault));
        tokenMV.approve(address(uniswapV2Router), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(manager);

        uint256[] memory amounts = vault.swapExactTokensForTokens(
            address(uniswapV2Router),
            amountIn,
            0, // amountOutMin
            path,
            block.timestamp + 1
        );

        assertEq(amounts[0], amountIn, "Amount in should be correct");
        assertEq(amounts[1], amountIn * 4, "Amount out should be correct");

        vm.stopPrank();
    }

    function testSwapExactTokensForTokens_OnlyManager() public {
        vm.startPrank(user);

        address[] memory path = new address[](2);
        path[0] = address(tokenMV);
        path[1] = address(assetToken1);

        vm.expectRevert(InvestmentVault.OnlyManagerError.selector);
        vault.swapExactTokensForTokens(address(uniswapV3Router), SWAP_AMOUNT, 0, path, block.timestamp + 1);

        vm.stopPrank();
    }

    function testSwapExactTokensForTokens_SwapsNotInitialized() public {
        vm.startPrank(owner);

        // Create new vault implementation
        InvestmentVault newImplementation = new InvestmentVault();

        // Prepare minimal initialization data
        DataTypes.AssetInitData[] memory emptyAssets = new DataTypes.AssetInitData[](0);
        DataTypes.InvestmentVaultInitData memory minimalInitData = DataTypes.InvestmentVaultInitData({
            mainVault: IMainVault(address(mainVault)),
            tokenMI: IERC20(address(tokenMI)),
            tokenMV: IERC20(address(tokenMV)),
            capitalOfMi: 0,
            shareMI: 0,
            step: 5 * 10 ** 16,
            assets: emptyAssets
        });
        bytes memory encodedMinimalInitData =
            abi.encodeWithSelector(InvestmentVault.initialize.selector, minimalInitData);

        // Deploy proxy and initialize it
        ERC1967Proxy newProxyInstance = new ERC1967Proxy(address(newImplementation), encodedMinimalInitData);
        InvestmentVault newVaultForTest = InvestmentVault(address(newProxyInstance));
        vm.stopPrank();

        vm.startPrank(manager);

        address[] memory path = new address[](2);
        path[0] = address(tokenMV);
        path[1] = address(assetToken1);

        vm.expectRevert(InvestmentVault.SwapsNotInitialized.selector);
        newVaultForTest.swapExactTokensForTokens(address(uniswapV3Router), SWAP_AMOUNT, 0, path, block.timestamp + 1);

        vm.stopPrank();
    }

    function testSwapExactTokensForTokens_TokenNotAvailable() public {
        vm.startPrank(manager);

        // Set token as unavailable
        mainVault.setAvailableToken(address(tokenMV), false);

        address[] memory path = new address[](2);
        path[0] = address(tokenMV);
        path[1] = address(assetToken1);

        vm.expectRevert(InvestmentVault.TokenNotAvailable.selector);
        vault.swapExactTokensForTokens(address(uniswapV2Router), SWAP_AMOUNT, 0, path, block.timestamp + 1);

        vm.stopPrank();
    }

    function testExactInputSingle_InvalidSwap() public {
        vm.startPrank(manager);

        // Try to swap between MI token and asset token directly
        DataTypes.DelegateExactInputSingleParams memory params = DataTypes.DelegateExactInputSingleParams({
            router: address(uniswapV3Router),
            tokenIn: address(tokenMI), // MI token
            tokenOut: address(assetToken1), // Asset token
            fee: 3000,
            deadline: block.timestamp + 1,
            amountIn: SWAP_AMOUNT,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(SwapLibrary.InvalidSwap.selector);
        vault.exactInputSingle(params);

        vm.stopPrank();
    }

    function testQuickswapExactInput_TokenNotAvailable() public {
        vm.startPrank(manager);

        // Set token as unavailable
        mainVault.setAvailableToken(address(tokenMV), false);

        bytes memory pathBytes = abi.encodePacked(address(tokenMV), uint24(3000), address(assetToken1));

        DataTypes.DelegateQuickswapExactInputParams memory params = DataTypes.DelegateQuickswapExactInputParams({
            router: address(quickswapV3Router),
            path: pathBytes,
            deadline: block.timestamp + 1,
            amountIn: SWAP_AMOUNT,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(InvestmentVault.TokenNotAvailable.selector);
        vault.quickswapExactInput(params);

        vm.stopPrank();
    }

    function testSwapExactTokensForTokensV2_TokenNotAvailable() public {
        vm.startPrank(manager);

        // Set token as unavailable
        mainVault.setAvailableToken(address(tokenMV), false);

        address[] memory path = new address[](2);
        path[0] = address(tokenMV);
        path[1] = address(assetToken1);

        vm.expectRevert(InvestmentVault.TokenNotAvailable.selector);
        vault.swapExactTokensForTokens(address(uniswapV2Router), SWAP_AMOUNT, 0, path, block.timestamp + 1);

        vm.stopPrank();
    }

    function testExactInput_TokenNotAvailable() public {
        vm.startPrank(manager);

        // Set token as unavailable
        mainVault.setAvailableToken(address(tokenMV), false);

        bytes memory pathBytes = abi.encodePacked(address(tokenMV), uint24(3000), address(assetToken1));

        DataTypes.DelegateExactInputParams memory params = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytes,
            deadline: block.timestamp + 1,
            amountIn: SWAP_AMOUNT,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(InvestmentVault.TokenNotAvailable.selector);
        vault.exactInput(params);

        vm.stopPrank();
    }

    function testQuickswapExactInputSingle_TokenNotAvailable() public {
        vm.startPrank(manager);

        // Set token as unavailable
        mainVault.setAvailableToken(address(tokenMV), false);

        DataTypes.DelegateQuickswapExactInputSingleParams memory params = DataTypes
            .DelegateQuickswapExactInputSingleParams({
            router: address(quickswapV3Router),
            tokenIn: address(tokenMV),
            tokenOut: address(assetToken1),
            deadline: block.timestamp + 1,
            amountIn: SWAP_AMOUNT,
            amountOutMinimum: 0,
            limitSqrtPrice: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(InvestmentVault.TokenNotAvailable.selector);
        vault.quickswapExactInputSingle(params);

        vm.stopPrank();
    }

    function testExactInput_RouterNotAvailable() public {
        vm.startPrank(manager);

        // Set router as unavailable
        mainVault.setAvailableRouter(address(uniswapV3Router), false);

        bytes memory pathBytes = abi.encodePacked(address(tokenMV), uint24(3000), address(assetToken1));

        DataTypes.DelegateExactInputParams memory params = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytes,
            deadline: block.timestamp + 1,
            amountIn: SWAP_AMOUNT,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(InvestmentVault.RouterNotAvailable.selector);
        vault.exactInput(params);

        vm.stopPrank();
    }

    function testQuickswapExactInput_RouterNotAvailable() public {
        vm.startPrank(manager);

        // Set router as unavailable
        mainVault.setAvailableRouter(address(quickswapV3Router), false);

        bytes memory pathBytes = abi.encodePacked(address(tokenMV), uint24(3000), address(assetToken1));

        DataTypes.DelegateQuickswapExactInputParams memory params = DataTypes.DelegateQuickswapExactInputParams({
            router: address(quickswapV3Router),
            path: pathBytes,
            deadline: block.timestamp + 1,
            amountIn: SWAP_AMOUNT,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(InvestmentVault.RouterNotAvailable.selector);
        vault.quickswapExactInput(params);

        vm.stopPrank();
    }

    function testSwapExactTokensForTokens_RouterNotAvailable() public {
        vm.startPrank(manager);

        // Set router as unavailable
        mainVault.setAvailableRouter(address(uniswapV2Router), false);

        address[] memory path = new address[](2);
        path[0] = address(tokenMV);
        path[1] = address(assetToken1);

        vm.expectRevert(InvestmentVault.RouterNotAvailable.selector);
        vault.swapExactTokensForTokens(address(uniswapV2Router), SWAP_AMOUNT, 0, path, block.timestamp + 1);

        vm.stopPrank();
    }

    function testQuickswapExactInputSingle_RouterNotAvailable() public {
        vm.startPrank(manager);

        // Set router as unavailable
        mainVault.setAvailableRouter(address(quickswapV3Router), false);

        DataTypes.DelegateQuickswapExactInputSingleParams memory params = DataTypes
            .DelegateQuickswapExactInputSingleParams({
            router: address(quickswapV3Router),
            tokenIn: address(tokenMV),
            tokenOut: address(assetToken1),
            deadline: block.timestamp + 1,
            amountIn: SWAP_AMOUNT,
            amountOutMinimum: 0,
            limitSqrtPrice: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(InvestmentVault.RouterNotAvailable.selector);
        vault.quickswapExactInputSingle(params);

        vm.stopPrank();
    }

    function testExactInputFirstStrategy_ReceivedLessThanExpectedWOB() public {
        vm.startPrank(manager);

        bytes memory pathBytes = abi.encodePacked(address(tokenMV), uint24(3000), address(assetToken2));

        uniswapV3Router.setPrice(address(tokenMV), address(assetToken2), 1 * 10 ** 17);

        uint256 amountIn = tokenMV.balanceOf(address(vault)) / 400;

        DataTypes.DelegateExactInputParams memory params = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytes,
            deadline: block.timestamp + 1,
            amountIn: amountIn,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        uniswapV3Router.setPrice(address(tokenMV), address(assetToken2), 8 * 10 ** 18);
        vault.exactInput(params);

        uniswapV3Router.setPrice(address(tokenMV), address(assetToken2), 1 * 10 ** 17);

        vm.expectRevert(SwapLibrary.ReceivedLessThanExpectedWOB.selector);
        vault.exactInput(params);

        vm.stopPrank();
    }

    function testExactInputFirstStrategy_SpentMoreThanExpectedWOD() public {
        vm.startPrank(manager);

        bytes memory pathBytes = abi.encodePacked(address(tokenMV), uint24(3000), address(assetToken2));

        uniswapV3Router.setPrice(address(tokenMV), address(assetToken2), 8 * 10 ** 18);

        uint256 amountIn = tokenMV.balanceOf(address(vault)) / 400;

        DataTypes.DelegateExactInputParams memory params = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytes,
            deadline: block.timestamp + 1,
            amountIn: amountIn,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        vault.exactInput(params);

        uint256 largeAmountIn = tokenMV.balanceOf(address(vault)) / 2;

        DataTypes.DelegateExactInputParams memory params2 = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytes,
            deadline: block.timestamp + 1,
            amountIn: largeAmountIn,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(SwapLibrary.SpentMoreThanExpectedWOD.selector);
        vault.exactInput(params2);

        vm.stopPrank();
    }

    function testExactInputFirstStrategy_NoTokensReceived() public {
        vm.startPrank(manager);

        bytes memory pathBytes = abi.encodePacked(address(tokenMV), uint24(3000), address(assetToken2));

        uniswapV3Router.setPrice(address(tokenMV), address(assetToken2), 0);

        uint256 amountIn = tokenMV.balanceOf(address(vault)) / 400;

        DataTypes.DelegateExactInputParams memory params = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytes,
            deadline: block.timestamp + 1,
            amountIn: amountIn,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(SwapLibrary.NoTokensReceived.selector);
        vault.exactInput(params);

        vm.stopPrank();
    }

    function testExactInputFirstStrategySell_NoTokensReceived() public {
        vm.startPrank(manager);

        bytes memory pathBytes = abi.encodePacked(address(tokenMV), uint24(3000), address(assetToken2));

        uniswapV3Router.setPrice(address(tokenMV), address(assetToken2), 8 * 10 ** 18);

        uint256 amountIn = tokenMV.balanceOf(address(vault)) / 400;

        DataTypes.DelegateExactInputParams memory params = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytes,
            deadline: block.timestamp + 1,
            amountIn: amountIn,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        vault.exactInput(params);

        bytes memory pathBytes2 = abi.encodePacked(address(assetToken2), uint24(3000), address(tokenMV));
        uniswapV3Router.setPrice(address(assetToken2), address(tokenMV), 0);

        uint256 amountIn2 = assetToken2.balanceOf(address(vault)) / 100;

        DataTypes.DelegateExactInputParams memory params2 = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytes2,
            deadline: block.timestamp + 1,
            amountIn: amountIn2,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(SwapLibrary.NoTokensReceived.selector);
        vault.exactInput(params2);

        vm.stopPrank();
    }

    function testHandleMvToMiSwap_NoTokensReceived() public {
        vm.startPrank(manager);

        bytes memory pathBytes2 = abi.encodePacked(address(tokenMI), uint24(3000), address(tokenMV));
        uniswapV3Router.setPrice(address(tokenMI), address(tokenMV), 0);

        uint256 amountIn2 = tokenMI.balanceOf(address(vault)) / 100;

        DataTypes.DelegateExactInputParams memory params2 = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytes2,
            deadline: block.timestamp + 1,
            amountIn: amountIn2,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(SwapLibrary.NoTokensReceived.selector);
        vault.exactInput(params2);

        vm.stopPrank();
    }

    function testHandleMiToMvSwap_NonAdvantageousPurchasePrice() public {
        vm.startPrank(manager);

        bytes memory pathBytes = abi.encodePacked(address(tokenMI), uint24(3000), address(tokenMV));

        uniswapV3Router.setPrice(address(tokenMI), address(tokenMV), 5 * 10 ** 17);

        uint256 amountIn = tokenMI.balanceOf(address(vault)) / 800;

        DataTypes.DelegateExactInputParams memory params = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytes,
            deadline: block.timestamp + 1,
            amountIn: amountIn,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(SwapLibrary.NonAdvantageousPurchasePrice.selector);
        vault.exactInput(params);

        vm.stopPrank();
    }

    function testMiToMvSwap_Success() public {
        vm.startPrank(manager);
        vm.warp(block.timestamp + 31 days);

        bytes memory pathBytes = abi.encodePacked(address(tokenMI), uint24(3000), address(tokenMV));

        uniswapV3Router.setPrice(address(tokenMI), address(tokenMV), 5 * 10 ** 18);

        uint256 amountIn = tokenMI.balanceOf(address(vault)) / 800;

        DataTypes.DelegateExactInputParams memory params = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytes,
            deadline: block.timestamp + 1,
            amountIn: amountIn,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        uint256 amountOut = vault.exactInput(params);

        vm.stopPrank();
    }

    function testMvToMiSwap_Success() public {
        vm.startPrank(manager);

        bytes memory pathBytes = abi.encodePacked(address(tokenMV), uint24(3000), address(tokenMI));

        uniswapV3Router.setPrice(address(tokenMV), address(tokenMI), 5 * 10 ** 18);

        uint256 amountIn = tokenMV.balanceOf(address(vault)) / 800;

        DataTypes.DelegateExactInputParams memory params = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytes,
            deadline: block.timestamp + 1,
            amountIn: amountIn,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        uint256 amountOut = vault.exactInput(params);

        vm.stopPrank();
    }

    function testMiToMvSwap_NonAdvantageousPurchasePrice() public {
        vm.startPrank(manager);

        bytes memory pathBytes = abi.encodePacked(address(tokenMI), uint24(3000), address(tokenMV));

        uniswapV3Router.setPrice(address(tokenMI), address(tokenMV), 5 * 10 ** 17);

        uint256 amountIn = tokenMI.balanceOf(address(vault)) / 800;

        DataTypes.DelegateExactInputParams memory params = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytes,
            deadline: block.timestamp + 1,
            amountIn: amountIn,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });
        vm.expectRevert(SwapLibrary.NonAdvantageousPurchasePrice.selector);

        vault.exactInput(params);

        vm.stopPrank();
    }

    function testMiToMvSwap_NoTokensReceived() public {
        vm.startPrank(manager);

        bytes memory pathBytes = abi.encodePacked(address(tokenMI), uint24(3000), address(tokenMV));

        uniswapV3Router.setPrice(address(tokenMI), address(tokenMV), 0);

        uint256 amountIn = tokenMI.balanceOf(address(vault)) / 800;

        DataTypes.DelegateExactInputParams memory params = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytes,
            deadline: block.timestamp + 1,
            amountIn: amountIn,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(SwapLibrary.NoTokensReceived.selector);
        vault.exactInput(params);

        vm.stopPrank();
    }

    function testInvalidTokensInSwap() public {
        vm.startPrank(manager);

        bytes memory pathBytes = abi.encodePacked(
            address(tokenMI),
            uint24(3000),
            address(tokenMI) // Attempting to swap the same token
        );

        uint256 amountIn = tokenMI.balanceOf(address(vault)) / 800;

        DataTypes.DelegateExactInputParams memory params = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytes,
            deadline: block.timestamp + 1,
            amountIn: amountIn,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(SwapLibrary.InvalidTokensInSwap.selector);
        vault.exactInput(params);

        vm.stopPrank();
    }

    function testSellAllAssetsAndMiThenBuyMv() public {
        vm.startPrank(manager);
        vm.warp(block.timestamp + 31 days);
        bytes memory pathBytesBuy = abi.encodePacked(address(tokenMV), uint24(3000), address(tokenMI));

        uniswapV3Router.setPrice(address(tokenMV), address(tokenMI), 6 * 10 ** 18);
        tokenMI.mint(address(uniswapV3Router), 1000000 * 10 ** 18);

        uint256 amountInBuy = tokenMV.balanceOf(address(vault)) / 400;

        DataTypes.DelegateExactInputParams memory paramsBuy = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytesBuy,
            deadline: block.timestamp + 1,
            amountIn: amountInBuy,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        uint256 amountOut = vault.exactInput(paramsBuy);
        assert(amountOut > 0);

        vm.stopPrank();

        vm.startPrank(owner);

        vault.setShareMi(0);
        uint256[] memory assetShares = new uint256[](1);
        assetShares[0] = 0;
        // assetShares[1] = 0;
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(assetToken1);
        // assets[1] = IERC20(assetToken2);
        vault.setAssetShares(assets, assetShares);

        vm.stopPrank();

        vm.startPrank(manager);

        bytes memory pathBytesAsset1 = abi.encodePacked(address(assetToken1), uint24(3000), address(tokenMV));

        uniswapV3Router.setPrice(address(assetToken1), address(tokenMV), 2 * 10 ** 18);

        uint256 amountInAsset1 = assetToken1.balanceOf(address(vault));

        DataTypes.DelegateExactInputParams memory paramsAsset1 = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytesAsset1,
            deadline: block.timestamp + 1,
            amountIn: amountInAsset1,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        vault.exactInput(paramsAsset1);

        bytes memory pathBytesAsset2 = abi.encodePacked(address(assetToken2), uint24(3000), address(tokenMV));

        uniswapV3Router.setPrice(address(assetToken2), address(tokenMV), 2 * 10 ** 18);

        uint256 amountInAsset2 = assetToken2.balanceOf(address(vault));

        DataTypes.DelegateExactInputParams memory paramsAsset2 = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytesAsset2,
            deadline: block.timestamp + 1,
            amountIn: amountInAsset2,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        vault.exactInput(paramsAsset2);

        bytes memory pathBytesMi = abi.encodePacked(address(tokenMI), uint24(3000), address(tokenMV));

        uniswapV3Router.setPrice(address(tokenMI), address(tokenMV), 5 * 10 ** 18);

        uint256 amountInMi = tokenMI.balanceOf(address(vault)) / 400;

        DataTypes.DelegateExactInputParams memory paramsMi = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytesMi,
            deadline: block.timestamp + 1,
            amountIn: amountInMi,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        vault.exactInput(paramsMi);

        bytes memory pathBytesBuy2 = abi.encodePacked(address(tokenMV), uint24(3000), address(tokenMI));

        uniswapV3Router.setPrice(address(tokenMV), address(tokenMI), 3 * 10 ** 18);

        (uint256 profitMV,,,,,) = vault.profitData();

        uint256 amountInBuy2 = tokenMV.balanceOf(address(vault)) - profitMV;

        DataTypes.DelegateExactInputParams memory paramsBuy2Profit = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytesBuy2,
            deadline: block.timestamp + 1,
            amountIn: profitMV,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.ProfitMvToProfitMi
        });

        vault.exactInput(paramsBuy2Profit);

        DataTypes.DelegateExactInputParams memory paramsBuy2 = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytesBuy2,
            deadline: block.timestamp + 1,
            amountIn: amountInBuy2,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        uint256 amountOut2 = vault.exactInput(paramsBuy2);
        assert(amountOut2 > 0);

        vm.stopPrank();
    }

    function testSellAllAssetsAndMvThenRevertIfBuy_Asset1() public {
        vm.startPrank(owner);

        vault.setShareMi(0);
        uint256[] memory assetShares = new uint256[](1);
        assetShares[0] = 0;
        // assetShares[1] = 0;
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(assetToken1);
        // assets[1] = IERC20(assetToken2);
        vault.setAssetShares(assets, assetShares);

        vm.stopPrank();

        vm.startPrank(manager);

        bytes memory pathBytesAsset1 = abi.encodePacked(address(assetToken1), uint24(3000), address(tokenMV));

        uniswapV3Router.setPrice(address(assetToken1), address(tokenMV), 2 * 10 ** 18);

        uint256 amountInAsset1 = assetToken1.balanceOf(address(vault));

        DataTypes.DelegateExactInputParams memory paramsAsset1 = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytesAsset1,
            deadline: block.timestamp + 1,
            amountIn: amountInAsset1,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        vault.exactInput(paramsAsset1);

        bytes memory pathBytesAsset1Buy = abi.encodePacked(address(tokenMV), uint24(3000), address(assetToken1));

        uniswapV3Router.setPrice(address(tokenMV), address(assetToken1), 2 * 10 ** 18);

        assetToken1.balanceOf(address(vault));

        DataTypes.DelegateExactInputParams memory paramsAsset1Buy = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytesAsset1Buy,
            deadline: block.timestamp + 1,
            amountIn: amountInAsset1,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });
        vm.expectRevert(SwapLibrary.PositionNotOpened.selector);
        vault.exactInput(paramsAsset1Buy);

        vm.stopPrank();
    }

    function testSellAllAssetsAndMvThenRevertIfBuy_Asset2() public {
        vm.startPrank(owner);

        vault.setShareMi(0);
        uint256[] memory assetShares = new uint256[](1);
        assetShares[0] = 0;
        // assetShares[1] = 0;
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(assetToken1);
        // assets[1] = IERC20(assetToken2);
        vault.setAssetShares(assets, assetShares);

        vm.stopPrank();

        vm.startPrank(manager);

        bytes memory pathBytesAsset2 = abi.encodePacked(address(assetToken2), uint24(3000), address(tokenMV));

        uniswapV3Router.setPrice(address(assetToken2), address(tokenMV), 2 * 10 ** 18);

        uint256 amountInAsset2 = assetToken2.balanceOf(address(vault));

        DataTypes.DelegateExactInputParams memory paramsAsset2 = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytesAsset2,
            deadline: block.timestamp + 1,
            amountIn: amountInAsset2,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        vault.exactInput(paramsAsset2);

        bytes memory pathBytesAsset2Buy = abi.encodePacked(address(tokenMV), uint24(3000), address(assetToken2));

        uniswapV3Router.setPrice(address(tokenMV), address(assetToken2), 2 * 10 ** 18);

        uint256 amountInAsset2Buy = tokenMV.balanceOf(address(vault));

        DataTypes.DelegateExactInputParams memory paramsAsset2Buy = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytesAsset2Buy,
            deadline: block.timestamp + 1,
            amountIn: amountInAsset2Buy,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });
        vm.expectRevert(SwapLibrary.PositionNotOpened.selector);
        vault.exactInput(paramsAsset2Buy);

        vm.stopPrank();
    }

    function testSellAllAssetsAndMvThenRevertIfBuy_MiToMv() public {
        vm.startPrank(owner);

        vault.setShareMi(0);
        uint256[] memory assetShares = new uint256[](1);
        assetShares[0] = 0;
        // assetShares[1] = 0;
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(assetToken1);
        // assets[1] = IERC20(assetToken2);
        vault.setAssetShares(assets, assetShares);

        vm.stopPrank();

        vm.startPrank(manager);

        // Sell assetToken1
        bytes memory pathBytesAsset1 = abi.encodePacked(address(assetToken1), uint24(3000), address(tokenMV));
        uniswapV3Router.setPrice(address(assetToken1), address(tokenMV), 2 * 10 ** 18);
        uint256 amountInAsset1 = assetToken1.balanceOf(address(vault));
        DataTypes.DelegateExactInputParams memory paramsAsset1 = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytesAsset1,
            deadline: block.timestamp + 1,
            amountIn: amountInAsset1,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });
        vault.exactInput(paramsAsset1);

        // Sell assetToken2
        bytes memory pathBytesAsset2 = abi.encodePacked(address(assetToken2), uint24(3000), address(tokenMV));
        uniswapV3Router.setPrice(address(assetToken2), address(tokenMV), 2 * 10 ** 18);
        uint256 amountInAsset2 = assetToken2.balanceOf(address(vault));
        DataTypes.DelegateExactInputParams memory paramsAsset2 = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytesAsset2,
            deadline: block.timestamp + 1,
            amountIn: amountInAsset2,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });
        vault.exactInput(paramsAsset2);

        tokenMV.mint(address(uniswapV3Router), 10000000000000 * 10 ** 18);
        tokenMI.mint(address(uniswapV3Router), 10000000000000 * 10 ** 18);

        // Sell tokenMV
        bytes memory pathBytesMv = abi.encodePacked(address(tokenMV), uint24(3000), address(tokenMI));
        uniswapV3Router.setPrice(address(tokenMV), address(tokenMI), 5 * 10 ** 18);
        console.log("tokenMV.balanceOf(address(vault))", tokenMV.balanceOf(address(vault)));
        console.log("assetToken1.balanceOf(address(vault))", assetToken1.balanceOf(address(vault)));
        console.log("assetToken2.balanceOf(address(vault))", assetToken2.balanceOf(address(vault)));
        (uint256 profitMV,,,,,) = vault.profitData();
        uint256 amountInMv = tokenMV.balanceOf(address(vault)) - profitMV;
        DataTypes.DelegateExactInputParams memory paramsMv = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytesMv,
            deadline: block.timestamp + 1,
            amountIn: amountInMv,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });
        vm.expectRevert(SwapLibrary.ProfitNotZero.selector);
        vault.exactInput(paramsMv);

        DataTypes.DelegateExactInputParams memory paramsMvProfit = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytesMv,
            deadline: block.timestamp + 1,
            amountIn: profitMV,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.ProfitMvToProfitMi
        });
        vault.exactInput(paramsMvProfit);

        vault.exactInput(paramsMv);

        // Attempt to buy MV with MI
        bytes memory pathBytesMiToMv = abi.encodePacked(address(tokenMI), uint24(3000), address(tokenMV));
        uniswapV3Router.setPrice(address(tokenMI), address(tokenMV), 5 * 10 ** 18);
        uint256 amountInMiToMv = tokenMI.balanceOf(address(vault));
        DataTypes.DelegateExactInputParams memory paramsMiToMv = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytesMiToMv,
            deadline: block.timestamp + 1,
            amountIn: amountInMiToMv,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(SwapLibrary.PositionNotOpened.selector);
        vault.exactInput(paramsMiToMv);

        vm.stopPrank();
    }

    function testNoTokensReceived() public {
        vm.startPrank(manager);

        bytes memory pathBytes = abi.encodePacked(address(tokenMV), uint24(3000), address(tokenMI));

        uniswapV3Router.setPrice(address(tokenMI), address(tokenMV), 0);
        uniswapV3Router.setPrice(address(tokenMV), address(tokenMI), 0);

        uint256 amountIn = tokenMV.balanceOf(address(vault)) / 800;

        DataTypes.DelegateExactInputParams memory params = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytes,
            deadline: block.timestamp + 1,
            amountIn: amountIn,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(SwapLibrary.NoTokensReceived.selector);
        vault.exactInput(params);

        vm.stopPrank();
    }

    function testHandleZeroStrategySell_NoTokensReceived() public {
        vm.startPrank(manager);

        bytes memory pathBytes = abi.encodePacked(address(tokenMV), uint24(3000), address(assetToken1));

        uniswapV3Router.setPrice(address(tokenMV), address(assetToken1), 0);

        uint256 amountIn = tokenMV.balanceOf(address(vault)) / 800;

        DataTypes.DelegateExactInputParams memory params = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytes,
            deadline: block.timestamp + 1,
            amountIn: amountIn,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(SwapLibrary.NoTokensReceived.selector);
        vault.exactInput(params);

        vm.stopPrank();
    }

    function testHandleZeroStrategyBuy_NoTokensReceived() public {
        vm.startPrank(manager);

        bytes memory pathBytes = abi.encodePacked(address(assetToken1), uint24(3000), address(tokenMV));

        uniswapV3Router.setPrice(address(assetToken1), address(tokenMV), 0);

        uint256 amountIn = assetToken1.balanceOf(address(vault)) / 800;

        DataTypes.DelegateExactInputParams memory params = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytes,
            deadline: block.timestamp + 1,
            amountIn: amountIn,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        // Ожидаем реверта NoTokensReceived
        vm.expectRevert(SwapLibrary.NoTokensReceived.selector);
        vault.exactInput(params);

        vm.stopPrank();
    }

    function testNoProfitOnSell() public {
        vm.startPrank(manager);

        bytes memory pathBytes = abi.encodePacked(address(assetToken2), uint24(3000), address(tokenMV));

        uniswapV3Router.setPrice(address(assetToken2), address(tokenMV), 1 * 10 ** 17);

        uint256 amountIn = assetToken2.balanceOf(address(vault));

        DataTypes.DelegateExactInputParams memory params = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytes,
            deadline: block.timestamp + 1,
            amountIn: amountIn,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(SwapLibrary.NoProfit.selector);
        vault.exactInput(params);

        vm.stopPrank();
    }

    function testPriceDidNotIncreaseEnough() public {
        vm.startPrank(manager);

        bytes memory pathBytes = abi.encodePacked(address(assetToken1), uint24(3000), address(tokenMV));

        uniswapV3Router.setPrice(address(assetToken1), address(tokenMV), 1 * 10 ** 17);

        uint256 amountIn = assetToken1.balanceOf(address(vault));

        DataTypes.DelegateExactInputParams memory params = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytes,
            deadline: block.timestamp + 1,
            amountIn: amountIn,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(SwapLibrary.PriceDidNotIncreaseEnough.selector);
        vault.exactInput(params);

        vm.stopPrank();
    }

    function testNonAdvantageousPurchasePrice() public {
        vm.startPrank(manager);
        vm.warp(block.timestamp + 31 days);

        bytes memory pathBytes = abi.encodePacked(address(tokenMV), uint24(3000), address(assetToken1));

        uniswapV3Router.setPrice(address(assetToken1), address(tokenMV), 8 * 10 ** 17);

        uint256 amountIn = tokenMV.balanceOf(address(vault)) / 400;

        DataTypes.DelegateExactInputParams memory params = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytes,
            deadline: block.timestamp + 1,
            amountIn: amountIn,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(SwapLibrary.NonAdvantageousPurchasePrice.selector);
        vault.exactInput(params);

        vm.stopPrank();
    }

    function testDepositIsGreaterThanCapital() public {
        vm.startPrank(manager);
        vm.warp(block.timestamp + 31 days);

        bytes memory pathBytes = abi.encodePacked(address(tokenMV), uint24(3000), address(assetToken1));

        (
            uint256 shareMV,
            uint256 step,
            DataTypes.Strategy strategy,
            int256 currentDeposit,
            uint256 currentCapital,
            uint256 tokenBought,
            uint8 decimals,
            uint256 lastBuyPrice,
            uint256 lastBuyTimestamp
        ) = vault.assetsData(IERC20(address(assetToken1)));
        console.log("Current deposit for assetToken1:", uint256(currentDeposit));
        console.log("Current capital for assetToken1:", currentCapital);

        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(address(assetToken1));
        uint256[] memory capitals = new uint256[](1);
        capitals[0] = uint256(currentDeposit) + 1000; // Капитал = депозит + 1000 wei
        console.log("Setting capital to:", capitals[0]);
        vault.setAssetCapital(tokens, capitals);

        uniswapV3Router.setPrice(address(assetToken1), address(tokenMV), 1 * 10 ** 6);

        uint256 amountIn = 2000; // 2000 wei MV - это должно превысить капитал
        console.log("Using amountIn:", amountIn);

        DataTypes.DelegateExactInputParams memory params = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytes,
            deadline: block.timestamp + 1,
            amountIn: amountIn,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        console.log("About to call exactInput with expected DepositIsGreaterThanCapital revert");
        vm.expectRevert(SwapLibrary.DepositIsGreaterThanCapital.selector);
        vault.exactInput(params);

        vm.stopPrank();
    }

    function testPriceDidNotIncreaseEnoughFirstLayer() public {
        vm.startPrank(manager);

        bytes memory pathBytes = abi.encodePacked(address(tokenMV), uint24(3000), address(tokenMI));

        uniswapV3Router.setPrice(address(tokenMV), address(tokenMI), 1 * 10 ** 17);

        uint256 amountIn = tokenMV.balanceOf(address(vault));

        DataTypes.DelegateExactInputParams memory params = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytes,
            deadline: block.timestamp + 1,
            amountIn: amountIn,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(SwapLibrary.PriceDidNotIncreaseEnough.selector);
        vault.exactInput(params);

        vm.stopPrank();
    }

    function testInsufficientTokensRemaining() public {
        vm.startPrank(manager);

        bytes memory pathBytes = abi.encodePacked(address(assetToken1), uint24(3000), address(tokenMV));

        uniswapV3Router.setPrice(address(assetToken1), address(tokenMV), 2 * 10 ** 18);

        assetToken1.mint(address(uniswapV3Router), 10000000000000 * 10 ** 18);

        uint256 amountIn = assetToken1.balanceOf(address(vault));

        DataTypes.DelegateExactInputParams memory params = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytes,
            deadline: block.timestamp + 1,
            amountIn: amountIn,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(SwapLibrary.InsufficientTokensRemaining.selector);
        vault.exactInput(params);

        vm.stopPrank();
    }

    function testInsufficientTokensRemainingAfterSellingAssets() public {
        console.log("0-tokenMV.balanceOf(address(vault))", tokenMV.balanceOf(address(vault)));

        vm.startPrank(owner);
        uint256[] memory assetShares = new uint256[](1);
        assetShares[0] = 0;
        // assetShares[1] = 0;
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(assetToken1);
        // assets[1] = IERC20(assetToken2);?
        vault.setAssetShares(assets, assetShares);
        vm.stopPrank();

        vm.startPrank(manager);
        (uint256 profitMV1,,,,,) = vault.profitData();

        bytes memory pathBytesAsset1 = abi.encodePacked(address(assetToken1), uint24(3000), address(tokenMV));
        uniswapV3Router.setPrice(address(assetToken1), address(tokenMV), 2 * 10 ** 18);
        uint256 amountInAsset1 = assetToken1.balanceOf(address(vault));
        DataTypes.DelegateExactInputParams memory paramsAsset1 = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytesAsset1,
            deadline: block.timestamp + 1,
            amountIn: amountInAsset1,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });
        vault.exactInput(paramsAsset1);
        (uint256 profitMV2,,,,,) = vault.profitData();

        bytes memory pathBytesAsset2 = abi.encodePacked(address(assetToken2), uint24(3000), address(tokenMV));
        uniswapV3Router.setPrice(address(assetToken2), address(tokenMV), 2 * 10 ** 18);
        uint256 amountInAsset2 = assetToken2.balanceOf(address(vault));
        DataTypes.DelegateExactInputParams memory paramsAsset2 = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytesAsset2,
            deadline: block.timestamp + 1,
            amountIn: amountInAsset2,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });
        vault.exactInput(paramsAsset2);
        bytes memory pathBytes = abi.encodePacked(address(tokenMV), uint24(3000), address(tokenMI));
        uniswapV3Router.setPrice(address(tokenMV), address(tokenMI), 7 * 10 ** 18);
        tokenMI.mint(address(uniswapV3Router), 10000000000000 * 10 ** 18);

        (uint256 profitMV3,,,,,) = vault.profitData();

        uint256 amountIn = tokenMV.balanceOf(address(vault)) - profitMV3 - 1;
        DataTypes.DelegateExactInputParams memory params = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytes,
            deadline: block.timestamp + 1,
            amountIn: amountIn,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(SwapLibrary.InsufficientTokensRemaining.selector);
        vault.exactInput(params);

        vm.stopPrank();
    }

    function testSpentMoreThanExpected() public {
        vm.startPrank(manager);
        vm.warp(block.timestamp + 31 days);

        // First, sell asset1 at a profitable price
        bytes memory pathBytesAsset1 = abi.encodePacked(address(assetToken1), uint24(3000), address(tokenMV));
        uniswapV3Router.setPrice(address(assetToken1), address(tokenMV), 8 * 10 ** 18); // Profitable price
        uint256 amountInAsset1 = assetToken1.balanceOf(address(vault)) / 10; // Sell only 10% of asset1
        DataTypes.DelegateExactInputParams memory paramsAsset1 = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytesAsset1,
            deadline: block.timestamp + 1,
            amountIn: amountInAsset1,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });
        vault.exactInput(paramsAsset1);

        // Reduce MI share
        vm.stopPrank();
        vm.startPrank(owner);
        vault.setShareMi(1 * 10 ** 17); // Set to 10%
        vm.stopPrank();
        vm.startPrank(manager);

        // Get current profit MV
        (uint256 profitMV,,,,,) = vault.profitData();

        // Add more tokens to router for swaps
        vm.stopPrank();
        vm.startPrank(owner);
        tokenMI.mint(address(uniswapV3Router), 1000000 * 10 ** 18);
        vm.stopPrank();
        vm.startPrank(manager);

        // Sell MV to MI, leaving just profitMV + small amount
        bytes memory pathBytesMvToMi = abi.encodePacked(address(tokenMV), uint24(3000), address(tokenMI));
        uniswapV3Router.setPrice(address(tokenMV), address(tokenMI), 5 * 10 ** 18);
        uint256 mvBalance = tokenMV.balanceOf(address(vault));
        uint256 amountToSell = mvBalance - profitMV - 100; // Leave profitMV + 100 wei

        DataTypes.DelegateExactInputParams memory paramsMvToMi = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytesMvToMi,
            deadline: block.timestamp + 1,
            amountIn: amountToSell,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });
        vault.exactInput(paramsMvToMi);

        // Try to swap more than remaining balance minus profit
        bytes memory pathBytesMvToMi2 = abi.encodePacked(address(tokenMV), uint24(3000), address(tokenMI));
        uint256 remainingBalance = tokenMV.balanceOf(address(vault));

        DataTypes.DelegateExactInputParams memory paramsMvToMi2 = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytesMvToMi2,
            deadline: block.timestamp + 1,
            amountIn: remainingBalance - 10, // Try to spend almost all remaining balance
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(SwapLibrary.SpentMoreThanExpected.selector);
        vault.exactInput(paramsMvToMi2);

        vm.stopPrank();
    }

    function testSpentMoreThanExpected_SecondCheck() public {
        vm.startPrank(manager);
        vm.warp(block.timestamp + 31 days);

        // First, sell asset1 at a profitable price
        bytes memory pathBytesAsset1 = abi.encodePacked(address(assetToken1), uint24(3000), address(tokenMV));
        uniswapV3Router.setPrice(address(assetToken1), address(tokenMV), 8 * 10 ** 18); // Profitable price
        uint256 amountInAsset1 = assetToken1.balanceOf(address(vault)) / 10; // Sell only 10% of asset1
        DataTypes.DelegateExactInputParams memory paramsAsset1 = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytesAsset1,
            deadline: block.timestamp + 1,
            amountIn: amountInAsset1,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });
        vault.exactInput(paramsAsset1);

        // Reduce MI share
        vm.stopPrank();
        vm.startPrank(owner);
        vault.setShareMi(1 * 10 ** 17); // Set to 10%
        vm.stopPrank();
        vm.startPrank(manager);

        // Get current profit MV
        (uint256 profitMV,,,,,) = vault.profitData();

        // Add more tokens to router for swaps
        vm.stopPrank();
        vm.startPrank(owner);
        assetToken1.mint(address(uniswapV3Router), 1000000 * 10 ** 18);
        vm.stopPrank();
        vm.startPrank(manager);

        // Try to swap MV to asset1 with amount that would leave less than profitMV
        bytes memory pathMvToAsset1 = abi.encodePacked(address(tokenMV), uint24(3000), address(assetToken1));
        uniswapV3Router.setPrice(address(tokenMV), address(assetToken1), 2 * 10 ** 18);
        uint256 mvBalance = tokenMV.balanceOf(address(vault));
        uint256 amountToSell = mvBalance - (profitMV / 2); // Try to sell amount that would leave less than profitMV

        DataTypes.DelegateExactInputParams memory paramsMvToAsset1 = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathMvToAsset1,
            deadline: block.timestamp + 1,
            amountIn: amountToSell,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(SwapLibrary.SpentMoreThanExpected.selector);
        vault.exactInput(paramsMvToAsset1);

        vm.stopPrank();
    }

    function testSpentMoreThanExpected_Asset2_SecondCheck() public {
        vm.startPrank(manager);
        vm.warp(block.timestamp + 31 days);

        // First reduce MI share and asset2 share
        vm.stopPrank();
        vm.startPrank(owner);
        vault.setShareMi(1 * 10 ** 17); // Set to 10%
        uint256[] memory assetShares = new uint256[](1);
        assetShares[0] = 4 * 10 ** 17; // Keep asset1 share
        // assetShares[1] = 1 * 10 ** 17; // Reduce asset2 share to 10%
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(assetToken1);
        // assets[1] = IERC20(assetToken2);
        vault.setAssetShares(assets, assetShares);
        vm.stopPrank();
        vm.startPrank(manager);

        // Then sell asset2 at a profitable price
        bytes memory pathBytesAsset2 = abi.encodePacked(address(assetToken2), uint24(3000), address(tokenMV));
        uniswapV3Router.setPrice(address(assetToken2), address(tokenMV), 8 * 10 ** 18); // Profitable price
        uint256 amountInAsset2 = assetToken2.balanceOf(address(vault)) / 100; // Sell only 1% of asset2
        DataTypes.DelegateExactInputParams memory paramsAsset2 = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytesAsset2,
            deadline: block.timestamp + 1,
            amountIn: amountInAsset2,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });
        vault.exactInput(paramsAsset2);

        // Get current profit MV
        (uint256 profitMV,,,,,) = vault.profitData();

        // Add more tokens to router for swaps
        vm.stopPrank();
        vm.startPrank(owner);
        tokenMI.mint(address(uniswapV3Router), 1000000 * 10 ** 18);
        vm.stopPrank();
        vm.startPrank(manager);

        // Sell MV to MI, leaving just profitMV + small amount
        bytes memory pathBytesMvToMi = abi.encodePacked(address(tokenMV), uint24(3000), address(tokenMI));
        uniswapV3Router.setPrice(address(tokenMV), address(tokenMI), 5 * 10 ** 18);
        uint256 mvBalance = tokenMV.balanceOf(address(vault));
        uint256 amountToSell = mvBalance - profitMV - 100; // Leave profitMV + 100 wei

        DataTypes.DelegateExactInputParams memory paramsMvToMi = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytesMvToMi,
            deadline: block.timestamp + 1,
            amountIn: amountToSell,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });
        vault.exactInput(paramsMvToMi);

        // Try to swap MV to asset2 with remaining balance
        bytes memory pathMvToAsset2 = abi.encodePacked(address(tokenMV), uint24(3000), address(assetToken2));
        uniswapV3Router.setPrice(address(tokenMV), address(assetToken2), 2 * 10 ** 18);
        uint256 remainingBalance = tokenMV.balanceOf(address(vault));

        DataTypes.DelegateExactInputParams memory paramsMvToAsset2 = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathMvToAsset2,
            deadline: block.timestamp + 1,
            amountIn: remainingBalance - 10, // Try to spend almost all remaining balance
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(SwapLibrary.SpentMoreThanExpected.selector);
        vault.exactInput(paramsMvToAsset2);

        vm.stopPrank();
    }

    function testInvalidTokensInSwap_MvToMi() public {
        vm.startPrank(manager);
        vm.warp(block.timestamp + 31 days);

        // First reduce MI share and asset2 share
        vm.stopPrank();
        vm.startPrank(owner);
        vault.setShareMi(1 * 10 ** 17); // Set to 10%
        vm.stopPrank();
        vm.startPrank(manager);

        // Try to swap with incorrect token order (MI to MV instead of MV to MI)
        bytes memory pathBytes = abi.encodePacked(address(tokenMI), uint24(3000), address(tokenMV));
        uniswapV3Router.setPrice(address(tokenMI), address(tokenMV), 5 * 10 ** 18);

        uint256 amountIn = tokenMI.balanceOf(address(vault)) / 10;

        DataTypes.DelegateExactInputParams memory params = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytes,
            deadline: block.timestamp + 1,
            amountIn: amountIn,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.ProfitMvToProfitMi // Пытаемся использовать ProfitMvToProfitMi с неправильными токенами
        });

        vm.expectRevert(SwapLibrary.InvalidTokensInSwap.selector);
        vault.exactInput(params);

        vm.stopPrank();
    }

    function testNoTokensReceived_MvToMi() public {
        vm.startPrank(manager);
        vm.warp(block.timestamp + 31 days);

        // First reduce MI share
        vm.stopPrank();
        vm.startPrank(owner);
        vault.setShareMi(1 * 10 ** 17); // Set to 10%
        vm.stopPrank();
        vm.startPrank(manager);

        // Get current profit MV
        (uint256 profitMV,,,,,) = vault.profitData();

        // Try to swap MV to MI with zero price (will result in zero MI tokens received)
        bytes memory pathBytes = abi.encodePacked(address(tokenMV), uint24(3000), address(tokenMI));
        uniswapV3Router.setPrice(address(tokenMV), address(tokenMI), 0); // Set price to 0 to get zero tokens

        uint256 amountIn = tokenMV.balanceOf(address(vault)) / 10;

        DataTypes.DelegateExactInputParams memory params = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytes,
            deadline: block.timestamp + 1,
            amountIn: amountIn,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.ProfitMvToProfitMi
        });

        vm.expectRevert(SwapLibrary.NoTokensReceived.selector);
        vault.exactInput(params);

        vm.stopPrank();
    }

    function testNonAdvantageousPurchasePrice_ProfitMvToMi() public {
        vm.startPrank(manager);
        vm.warp(block.timestamp + 31 days);

        // First reduce MI share and sell some asset2 to generate profit
        vm.stopPrank();
        vm.startPrank(owner);
        vault.setShareMi(1 * 10 ** 17); // Set to 10%
        uint256[] memory assetShares = new uint256[](1);
        assetShares[0] = 4 * 10 ** 17;
        // assetShares[1] = 1 * 10 ** 17; // Reduce asset2 share to 10%
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(assetToken1);
        // assets[1] = IERC20(assetToken2);
        vault.setAssetShares(assets, assetShares);
        vm.stopPrank();
        vm.startPrank(manager);

        // Generate profit by selling asset2
        bytes memory pathBytesAsset2 = abi.encodePacked(address(assetToken2), uint24(3000), address(tokenMV));
        uniswapV3Router.setPrice(address(assetToken2), address(tokenMV), 8 * 10 ** 18); // Profitable price
        uint256 amountInAsset2 = assetToken2.balanceOf(address(vault)) / 100; // Sell only 1% of asset2
        DataTypes.DelegateExactInputParams memory paramsAsset2 = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytesAsset2,
            deadline: block.timestamp + 1,
            amountIn: amountInAsset2,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });
        vault.exactInput(paramsAsset2);

        // Get current profit MV
        (uint256 profitMV,,,,,) = vault.profitData();

        // Try to swap profitMV to MI with disadvantageous price
        bytes memory pathBytes = abi.encodePacked(address(tokenMV), uint24(3000), address(tokenMI));
        uniswapV3Router.setPrice(address(tokenMV), address(tokenMI), 1 * 10 ** 17); // Set disadvantageous price

        DataTypes.DelegateExactInputParams memory params = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytes,
            deadline: block.timestamp + 1,
            amountIn: profitMV,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.ProfitMvToProfitMi
        });

        vm.expectRevert(SwapLibrary.NonAdvantageousPurchasePrice.selector);
        vault.exactInput(params);

        vm.stopPrank();
    }

    function testBadPriceAndTimeBetweenBuys() public {
        vm.startPrank(manager);
        vm.warp(block.timestamp + 31 days);

        bytes memory pathBytesMvMi = abi.encodePacked(address(tokenMI), uint24(3000), address(tokenMV));
        uniswapV3Router.setPrice(address(tokenMV), address(tokenMI), 1.9 * 10 ** 18); // Higher price (worse)

        uint256 balance = tokenMV.balanceOf(address(vault));

        DataTypes.DelegateExactInputParams memory paramsBuy = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytesMvMi,
            deadline: block.timestamp + 1,
            amountIn: balance / 400,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        vault.exactInput(paramsBuy);

        uniswapV3Router.setPrice(address(tokenMV), address(tokenMI), 1.9 * 10 ** 18); // Keep bad price

        vm.expectRevert(SwapLibrary.BadPriceAndTimeBetweenBuys.selector);
        vault.exactInput(paramsBuy);

        vm.stopPrank();
    }

    function testBadPriceAndTimeBetweenBuys_MvToAsset1() public {
        vm.startPrank(manager);
        vm.warp(block.timestamp + 31 days);

        // Setup path and price for MV to Asset1 swap
        bytes memory pathBytesMvAsset1 = abi.encodePacked(address(tokenMV), uint24(3000), address(assetToken1));
        uniswapV3Router.setPrice(address(tokenMV), address(assetToken1), 2.1 * 10 ** 18); // Set initial price

        uint256 balance = tokenMV.balanceOf(address(vault));

        DataTypes.DelegateExactInputParams memory paramsBuy = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytesMvAsset1,
            deadline: block.timestamp + 1,
            amountIn: balance / 400,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        // First buy should succeed
        vault.exactInput(paramsBuy);

        // Keep the same (bad) price for the second attempt
        uniswapV3Router.setPrice(address(tokenMV), address(assetToken1), 2.1 * 10 ** 18);

        // Second buy should fail due to time and price constraints
        vm.expectRevert(SwapLibrary.BadPriceAndTimeBetweenBuys.selector);
        vault.exactInput(paramsBuy);

        vm.stopPrank();
    }

    function testAssetBoughtTooMuch() public {
        vm.startPrank(manager);
        vm.warp(block.timestamp + 31 days);

        // Setup path and advantageous price for MV to Asset1 swap
        bytes memory pathBytesMvAsset1 = abi.encodePacked(address(tokenMV), uint24(3000), address(assetToken1));
        uniswapV3Router.setPrice(address(tokenMV), address(assetToken1), 10 * 10 ** 18); // Set good price

        uint256 balance = tokenMV.balanceOf(address(vault));

        // Try to buy too much asset1
        DataTypes.DelegateExactInputParams memory paramsBuy = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytesMvAsset1,
            deadline: block.timestamp + 1,
            amountIn: balance / 10, // Try to spend half of MV balance to buy too much asset1
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(SwapLibrary.AssetBoughtTooMuch.selector);
        vault.exactInput(paramsBuy);

        vm.stopPrank();
    }

    function testAssetBoughtTooMuchForMiToMv() public {
        vm.startPrank(manager);
        vm.warp(block.timestamp + 31 days);

        // Setup path and advantageous price for MV to Asset1 swap
        bytes memory pathBytesMiToMv = abi.encodePacked(address(tokenMI), uint24(3000), address(tokenMV));
        uniswapV3Router.setPrice(address(tokenMI), address(tokenMV), 10 * 10 ** 18); // Set good price

        uint256 balance = tokenMV.balanceOf(address(vault));

        // Try to buy too much asset1
        DataTypes.DelegateExactInputParams memory paramsBuy = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytesMiToMv,
            deadline: block.timestamp + 1,
            amountIn: balance / 10,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(SwapLibrary.AssetBoughtTooMuch.selector);
        vault.exactInput(paramsBuy);

        vm.stopPrank();
    }

    function testSuccessfulAssetDeposit() public {
        vm.startPrank(manager);
        vm.warp(block.timestamp + 31 days);

        // Get initial deposit for asset1
        (,,, int256 initialDeposit,,,,,) = vault.assetsData(IERC20(assetToken1));

        // Setup path and reasonable price for MV to Asset1 swap
        bytes memory pathBytesMvAsset1 = abi.encodePacked(address(tokenMV), uint24(3000), address(assetToken1));
        uniswapV3Router.setPrice(address(tokenMV), address(assetToken1), 2.1 * 10 ** 18); // Set reasonable price

        uint256 balance = tokenMV.balanceOf(address(vault));
        uint256 amountIn = balance / 100; // Small enough amount to not trigger AssetBoughtTooMuch

        DataTypes.DelegateExactInputParams memory paramsBuy = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytesMvAsset1,
            deadline: block.timestamp + 31 days * 45,
            amountIn: amountIn,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });
        vault.exactInput(paramsBuy);
        vm.warp(block.timestamp + 31 days * 2);
        vault.exactInput(paramsBuy);
        vm.warp(block.timestamp + 31 days * 3);
        vault.exactInput(paramsBuy);

        // Setup path and reasonable price for MV to Asset1 swap
        bytes memory pathBytesAsset1MV = abi.encodePacked(address(assetToken1), uint24(3000), address(tokenMV));
        uniswapV3Router.setPrice(address(tokenMV), address(assetToken1), 1.99 * 10 ** 18); // Set reasonable price

        uint256 balance2 = assetToken1.balanceOf(address(vault));
        uint256 amountIn2 = balance2 / 400; // Small enough amount to not trigger AssetBoughtTooMuch

        DataTypes.DelegateExactInputParams memory paramsSell = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytesAsset1MV,
            deadline: block.timestamp + 31 days * 45,
            amountIn: amountIn2,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        // Execute swap
        vault.exactInput(paramsSell);

        // Check that deposit was updated
        (,,, int256 newDeposit,,,,,) = vault.assetsData(IERC20(assetToken1));

        // New deposit should be greater than initial deposit
        assert(newDeposit > initialDeposit);

        vm.stopPrank();
    }

    function testSuccessfulMiDeposit() public {
        vm.startPrank(manager);
        vm.warp(block.timestamp + 31 days);

        // Get initial deposit for MI
        (,,,,, uint256 initialDeposit,,,,,) = vault.tokenData();

        // Setup path and reasonable price for MV to MI swap
        bytes memory pathBytesMvMi = abi.encodePacked(address(tokenMI), uint24(3000), address(tokenMV));
        uniswapV3Router.setPrice(address(tokenMI), address(tokenMV), 6 * 10 ** 17);

        uint256 balance = tokenMV.balanceOf(address(vault));
        uint256 amountIn = balance / 100; // Small enough amount to not trigger AssetBoughtTooMuch

        DataTypes.DelegateExactInputParams memory paramsBuy = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytesMvMi,
            deadline: block.timestamp + 31 days * 45,
            amountIn: amountIn,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });
        vault.exactInput(paramsBuy);
        console.log("block.timestamp", block.timestamp);
        vm.warp(block.timestamp + 31 days * 2);
        vault.exactInput(paramsBuy);
        console.log("block.timestamp", block.timestamp);
        vm.warp(block.timestamp + 31 days * 3);
        vault.exactInput(paramsBuy);
        console.log("block.timestamp", block.timestamp);

        // Setup path and reasonable price for MI to MV swap
        bytes memory pathBytesMiMv = abi.encodePacked(address(tokenMV), uint24(3000), address(tokenMI));
        uniswapV3Router.setPrice(address(tokenMI), address(tokenMV), 4 * 10 ** 17); // Set reasonable price

        uint256 balance2 = tokenMI.balanceOf(address(vault));
        uint256 amountIn2 = balance2 / 400; // Small enough amount to not trigger AssetBoughtTooMuch

        DataTypes.DelegateExactInputParams memory paramsSell = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytesMiMv,
            deadline: block.timestamp + 31 days * 45,
            amountIn: amountIn2,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        // Execute swap
        vault.exactInput(paramsSell);

        // Check that deposit was updated
        (,,,,, uint256 newDeposit,,,,,) = vault.tokenData();

        // New deposit should be greater than initial deposit
        assert(newDeposit > initialDeposit);

        vm.stopPrank();
    }

    function testLastBuyPriceDecrease() public {
        vm.startPrank(manager);
        vm.warp(block.timestamp + 31 days);

        // First do normal swap to set initial lastBuyPrice
        bytes memory pathBytesMvMi = abi.encodePacked(address(tokenMI), uint24(3000), address(tokenMV));
        uniswapV3Router.setPrice(address(tokenMV), address(tokenMI), 2 * 10 ** 17);

        uint256 balance = tokenMV.balanceOf(address(vault));
        uint256 amountIn = balance / 100000;

        DataTypes.DelegateExactInputParams memory paramsBuy = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytesMvMi,
            deadline: block.timestamp + 31 days * 45,
            amountIn: amountIn,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });
        vault.exactInput(paramsBuy);

        // Get initial lastBuyPrice
        (,,,,,,,,, uint256 initialLastBuyPrice,) = vault.tokenData();

        // Wait some time and set very low price
        vm.warp(block.timestamp + 31 days * 2);
        uniswapV3Router.setPrice(address(tokenMV), address(tokenMI), 1 * 10 ** 16); // Very low price

        // Try to swap with very low price
        vault.exactInput(paramsBuy);

        // Get new lastBuyPrice
        (,,,,,,,,, uint256 newLastBuyPrice,) = vault.tokenData();

        // Calculate expected lastBuyPrice
        uint256 step = 5 * 10 ** 16; // From setUp()
        uint256 expectedLastBuyPrice =
            initialLastBuyPrice * (Constants.SHARE_DENOMINATOR - step) / Constants.SHARE_DENOMINATOR;

        // Check that lastBuyPrice decreased correctly
        assertEq(newLastBuyPrice, expectedLastBuyPrice, "LastBuyPrice should decrease by step");

        vm.stopPrank();
    }

    // ============ Admin Restriction Tests ============

    function testExactInputSingle_RouterNotAvailableByAdmin() public {
        vm.startPrank(manager);

        // Set router as available for investor but not for admin
        mainVault.setAvailableRouter(address(uniswapV3Router), true);
        mainVault.setAvailableRouter(address(uniswapV3Router), false); // Disable for admin

        DataTypes.DelegateExactInputSingleParams memory params = DataTypes.DelegateExactInputSingleParams({
            router: address(uniswapV3Router),
            tokenIn: address(tokenMV),
            tokenOut: address(assetToken1),
            fee: 3000,
            deadline: block.timestamp + 1,
            amountIn: SWAP_AMOUNT,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(InvestmentVault.RouterNotAvailable.selector);
        vault.exactInputSingle(params);

        vm.stopPrank();
    }

    function testExactInputSingle_TokenNotAvailableByAdmin() public {
        vm.startPrank(manager);

        // Set tokens as available for investor but not for admin
        mainVault.setAvailableToken(address(tokenMV), true);
        mainVault.setAvailableToken(address(assetToken1), true);
        mainVault.setAvailableToken(address(tokenMV), false); // Disable MV for admin
        mainVault.setAvailableToken(address(assetToken1), false); // Disable Asset1 for admin

        DataTypes.DelegateExactInputSingleParams memory params = DataTypes.DelegateExactInputSingleParams({
            router: address(uniswapV3Router),
            tokenIn: address(tokenMV),
            tokenOut: address(assetToken1),
            fee: 3000,
            deadline: block.timestamp + 1,
            amountIn: SWAP_AMOUNT,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(InvestmentVault.TokenNotAvailable.selector);
        vault.exactInputSingle(params);

        vm.stopPrank();
    }

    function testExactInput_RouterNotAvailableByAdmin() public {
        vm.startPrank(manager);

        // Set router as available for investor but not for admin
        mainVault.setAvailableRouter(address(uniswapV3Router), true);
        mainVault.setAvailableRouter(address(uniswapV3Router), false); // Disable for admin

        bytes memory pathBytes = abi.encodePacked(address(tokenMV), uint24(3000), address(assetToken1));

        DataTypes.DelegateExactInputParams memory params = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytes,
            deadline: block.timestamp + 1,
            amountIn: SWAP_AMOUNT,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(InvestmentVault.RouterNotAvailable.selector);
        vault.exactInput(params);

        vm.stopPrank();
    }

    function testExactInput_TokenNotAvailableByAdmin() public {
        vm.startPrank(manager);

        // Set tokens as available for investor but not for admin
        mainVault.setAvailableToken(address(tokenMV), true);
        mainVault.setAvailableToken(address(assetToken1), true);
        mainVault.setAvailableToken(address(tokenMV), false); // Disable MV for admin
        mainVault.setAvailableToken(address(assetToken1), false); // Disable Asset1 for admin

        bytes memory pathBytes = abi.encodePacked(address(tokenMV), uint24(3000), address(assetToken1));

        DataTypes.DelegateExactInputParams memory params = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytes,
            deadline: block.timestamp + 1,
            amountIn: SWAP_AMOUNT,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(InvestmentVault.TokenNotAvailable.selector);
        vault.exactInput(params);

        vm.stopPrank();
    }

    function testSwapExactTokensForTokens_RouterNotAvailableByAdmin() public {
        vm.startPrank(manager);

        // Set router as available for investor but not for admin
        mainVault.setAvailableRouter(address(uniswapV2Router), true);
        mainVault.setAvailableRouter(address(uniswapV2Router), false); // Disable for admin

        address[] memory path = new address[](2);
        path[0] = address(tokenMV);
        path[1] = address(assetToken1);

        vm.expectRevert(InvestmentVault.RouterNotAvailable.selector);
        vault.swapExactTokensForTokens(address(uniswapV2Router), SWAP_AMOUNT, 0, path, block.timestamp + 1);

        vm.stopPrank();
    }

    function testSwapExactTokensForTokens_TokenNotAvailableByAdmin() public {
        vm.startPrank(manager);

        // Set tokens as available for investor but not for admin
        mainVault.setAvailableToken(address(tokenMV), true);
        mainVault.setAvailableToken(address(assetToken1), true);
        mainVault.setAvailableToken(address(tokenMV), false); // Disable MV for admin
        mainVault.setAvailableToken(address(assetToken1), false); // Disable Asset1 for admin

        address[] memory path = new address[](2);
        path[0] = address(tokenMV);
        path[1] = address(assetToken1);

        vm.expectRevert(InvestmentVault.TokenNotAvailable.selector);
        vault.swapExactTokensForTokens(address(uniswapV2Router), SWAP_AMOUNT, 0, path, block.timestamp + 1);

        vm.stopPrank();
    }

    function testQuickswapExactInputSingle_RouterNotAvailableByAdmin() public {
        vm.startPrank(manager);

        // Set router as available for investor but not for admin
        mainVault.setAvailableRouter(address(quickswapV3Router), true);
        mainVault.setAvailableRouter(address(quickswapV3Router), false); // Disable for admin

        DataTypes.DelegateQuickswapExactInputSingleParams memory params = DataTypes
            .DelegateQuickswapExactInputSingleParams({
            router: address(quickswapV3Router),
            tokenIn: address(tokenMV),
            tokenOut: address(assetToken1),
            deadline: block.timestamp + 1,
            amountIn: SWAP_AMOUNT,
            amountOutMinimum: 0,
            limitSqrtPrice: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(InvestmentVault.RouterNotAvailable.selector);
        vault.quickswapExactInputSingle(params);

        vm.stopPrank();
    }

    function testQuickswapExactInputSingle_TokenNotAvailableByAdmin() public {
        vm.startPrank(manager);

        // Set tokens as available for investor but not for admin
        mainVault.setAvailableToken(address(tokenMV), true);
        mainVault.setAvailableToken(address(assetToken1), true);
        mainVault.setAvailableToken(address(tokenMV), false); // Disable MV for admin
        mainVault.setAvailableToken(address(assetToken1), false); // Disable Asset1 for admin

        DataTypes.DelegateQuickswapExactInputSingleParams memory params = DataTypes
            .DelegateQuickswapExactInputSingleParams({
            router: address(quickswapV3Router),
            tokenIn: address(tokenMV),
            tokenOut: address(assetToken1),
            deadline: block.timestamp + 1,
            amountIn: SWAP_AMOUNT,
            amountOutMinimum: 0,
            limitSqrtPrice: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(InvestmentVault.TokenNotAvailable.selector);
        vault.quickswapExactInputSingle(params);

        vm.stopPrank();
    }

    function testQuickswapExactInput_RouterNotAvailableByAdmin() public {
        vm.startPrank(manager);

        // Set router as available for investor but not for admin
        mainVault.setAvailableRouter(address(quickswapV3Router), true);
        mainVault.setAvailableRouter(address(quickswapV3Router), false); // Disable for admin

        bytes memory pathBytes = abi.encodePacked(address(tokenMV), uint24(3000), address(assetToken1));

        DataTypes.DelegateQuickswapExactInputParams memory params = DataTypes.DelegateQuickswapExactInputParams({
            router: address(quickswapV3Router),
            path: pathBytes,
            deadline: block.timestamp + 1,
            amountIn: SWAP_AMOUNT,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(InvestmentVault.RouterNotAvailable.selector);
        vault.quickswapExactInput(params);

        vm.stopPrank();
    }

    function testQuickswapExactInput_TokenNotAvailableByAdmin() public {
        vm.startPrank(manager);

        // Set tokens as available for investor but not for admin
        mainVault.setAvailableToken(address(tokenMV), true);
        mainVault.setAvailableToken(address(assetToken1), true);
        mainVault.setAvailableToken(address(tokenMV), false); // Disable MV for admin
        mainVault.setAvailableToken(address(assetToken1), false); // Disable Asset1 for admin

        bytes memory pathBytes = abi.encodePacked(address(tokenMV), uint24(3000), address(assetToken1));

        DataTypes.DelegateQuickswapExactInputParams memory params = DataTypes.DelegateQuickswapExactInputParams({
            router: address(quickswapV3Router),
            path: pathBytes,
            deadline: block.timestamp + 1,
            amountIn: SWAP_AMOUNT,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(InvestmentVault.TokenNotAvailable.selector);
        vault.quickswapExactInput(params);

        vm.stopPrank();
    }

    function testInvalidStrategy_Asset2ToMiSwap() public {
        vm.startPrank(manager);
        vm.warp(block.timestamp + 31 days);

        // Mint some assetToken2 to vault to simulate having it
        vm.stopPrank();
        vm.startPrank(owner);
        assetToken2.mint(address(vault), 1000 * 10 ** 6); // 1000 tokens with 6 decimals
        vm.stopPrank();
        vm.startPrank(manager);

        // Try to sell assetToken2 directly to MI (should fail with InvalidStrategy)
        // This should trigger Case 5 in SwapLibrary: Asset to MI swap for First strategy
        // Since tokenMI != tokenMV, this should go to Case 5, not Case 4
        bytes memory pathBytesSell = abi.encodePacked(address(assetToken2), uint24(3000), address(tokenMI));
        uniswapV3Router.setPrice(address(assetToken2), address(tokenMI), 2 * 10 ** 18);

        uint256 amountInSell = 100 * 10 ** 6; // 100 tokens
        DataTypes.DelegateExactInputParams memory paramsSell = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytesSell,
            deadline: block.timestamp + 1,
            amountIn: amountInSell,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(SwapLibrary.InvalidStrategy.selector);
        vault.exactInput(paramsSell);

        vm.stopPrank();
    }

    function testInvalidStrategy_Asset2ToMiSwap_ExactInputSingle() public {
        vm.startPrank(manager);
        vm.warp(block.timestamp + 31 days);

        // Mint some assetToken2 to vault to simulate having it
        vm.stopPrank();
        vm.startPrank(owner);
        assetToken2.mint(address(vault), 1000 * 10 ** 6); // 1000 tokens with 6 decimals
        vm.stopPrank();
        vm.startPrank(manager);

        // Try to sell assetToken2 directly to MI using exactInputSingle (should fail with InvalidStrategy)
        uniswapV3Router.setPrice(address(assetToken2), address(tokenMI), 2 * 10 ** 18);

        uint256 amountInSell = 100 * 10 ** 6; // 100 tokens
        DataTypes.DelegateExactInputSingleParams memory paramsSell = DataTypes.DelegateExactInputSingleParams({
            router: address(uniswapV3Router),
            tokenIn: address(assetToken2),
            tokenOut: address(tokenMI),
            fee: 3000,
            deadline: block.timestamp + 1,
            amountIn: amountInSell,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(SwapLibrary.InvalidStrategy.selector);
        vault.exactInputSingle(paramsSell);

        vm.stopPrank();
    }

    function testInvalidStrategy_Asset2ToMiSwap_Quickswap() public {
        vm.startPrank(manager);
        vm.warp(block.timestamp + 31 days);

        // Mint some assetToken2 to vault to simulate having it
        vm.stopPrank();
        vm.startPrank(owner);
        assetToken2.mint(address(vault), 1000 * 10 ** 6); // 1000 tokens with 6 decimals
        // Mint tokens to router for the swap
        tokenMI.mint(address(quickswapV3Router), 10000 * 10 ** 18);
        vm.stopPrank();
        vm.startPrank(address(vault));
        assetToken2.approve(address(quickswapV3Router), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(manager);

        // Try to sell assetToken2 directly to MI using quickswap (should fail with InvalidStrategy)
        quickswapV3Router.setPrice(address(assetToken2), address(tokenMI), 2 * 10 ** 18);

        uint256 amountInSell = 100 * 10 ** 6; // 100 tokens
        DataTypes.DelegateQuickswapExactInputParams memory paramsSell = DataTypes.DelegateQuickswapExactInputParams({
            router: address(quickswapV3Router),
            path: abi.encodePacked(address(assetToken2), uint24(3000), address(tokenMI)),
            deadline: block.timestamp + 1,
            amountIn: amountInSell,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(SwapLibrary.InvalidStrategy.selector);
        vault.quickswapExactInput(paramsSell);

        vm.stopPrank();
    }

    function testInvalidStrategy_Asset2ToMiSwap_QuickswapSingle() public {
        vm.startPrank(manager);
        vm.warp(block.timestamp + 31 days);

        // Mint some assetToken2 to vault to simulate having it
        vm.stopPrank();
        vm.startPrank(owner);
        assetToken2.mint(address(vault), 1000 * 10 ** 6); // 1000 tokens with 6 decimals
        // Mint tokens to router for the swap
        tokenMI.mint(address(quickswapV3Router), 10000 * 10 ** 18);
        vm.stopPrank();
        vm.startPrank(address(vault));
        assetToken2.approve(address(quickswapV3Router), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(manager);

        // Try to sell assetToken2 directly to MI using quickswapExactInputSingle (should fail with InvalidStrategy)
        quickswapV3Router.setPrice(address(assetToken2), address(tokenMI), 2 * 10 ** 18);

        uint256 amountInSell = 100 * 10 ** 6; // 100 tokens
        DataTypes.DelegateQuickswapExactInputSingleParams memory paramsSell = DataTypes
            .DelegateQuickswapExactInputSingleParams({
            router: address(quickswapV3Router),
            tokenIn: address(assetToken2),
            tokenOut: address(tokenMI),
            amountIn: amountInSell,
            amountOutMinimum: 0,
            limitSqrtPrice: 0,
            deadline: block.timestamp + 1,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(SwapLibrary.InvalidStrategy.selector);
        vault.quickswapExactInputSingle(paramsSell);

        vm.stopPrank();
    }

    function testInvalidStrategy_Asset2ToMiSwap_UniswapV2() public {
        vm.startPrank(manager);
        vm.warp(block.timestamp + 31 days);

        // Mint some assetToken2 to vault to simulate having it
        vm.stopPrank();
        vm.startPrank(owner);
        assetToken2.mint(address(vault), 1000 * 10 ** 6); // 1000 tokens with 6 decimals
        // Mint tokens to router for the swap
        tokenMI.mint(address(uniswapV2Router), 10000 * 10 ** 18);
        vm.stopPrank();
        vm.startPrank(address(vault));
        assetToken2.approve(address(uniswapV2Router), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(manager);

        // Try to sell assetToken2 directly to MI using UniswapV2 (should fail with InvalidStrategy)
        uniswapV2Router.setPrice(address(assetToken2), address(tokenMI), 2 * 10 ** 18);

        address[] memory path = new address[](2);
        path[0] = address(assetToken2);
        path[1] = address(tokenMI);

        uint256 amountInSell = 100 * 10 ** 6; // 100 tokens

        vm.expectRevert(SwapLibrary.InvalidStrategy.selector);
        vault.swapExactTokensForTokens(address(uniswapV2Router), amountInSell, 0, path, block.timestamp + 1);

        vm.stopPrank();
    }
}
