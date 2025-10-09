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

contract SwapTestsSingleToken is Test {
    InvestmentVault public implementation;
    ERC1967Proxy public proxy;
    InvestmentVault public vault;
    MockToken public mainToken; // Single token for both MI and MV
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
    uint256 public constant STEP = 5 * 10 ** 16;

    function setUp() public {
        vm.startPrank(owner);

        // Deploy single main token that will be used as both MI and MV
        mainToken = new MockToken("Main Token", "MAIN", 18);
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
        mainVault.setAvailableRouter(address(uniswapV3Router), true);
        mainVault.setAvailableRouter(address(quickswapV3Router), true);
        mainVault.setAvailableRouter(address(quoterV2), true);
        mainVault.setAvailableRouter(address(quoterQuickswap), true);
        mainVault.setAvailableRouter(address(uniswapV2Router), true);
        mainVault.setAvailableToken(address(mainToken), true);
        mainVault.setAvailableToken(address(assetToken1), true);
        mainVault.setAvailableToken(address(assetToken2), true);

        // Deploy vault implementation
        implementation = new InvestmentVault();
        mainVault.setCurrentImplementation(address(implementation));

        // Setup assets with different strategies
        DataTypes.AssetInitData[] memory assets = new DataTypes.AssetInitData[](2);
        assets[0] = DataTypes.AssetInitData({
            token: IERC20(address(assetToken1)),
            shareMV: 4 * 10 ** 17, // 40% of MV tokens
            step: STEP,
            strategy: DataTypes.Strategy.Zero
        });
        assets[1] = DataTypes.AssetInitData({
            token: IERC20(address(assetToken2)),
            shareMV: 3 * 10 ** 17, // 30% of MV tokens
            step: STEP, // 5% step for first strategy
            strategy: DataTypes.Strategy.First
        });

        // Initialize vault with same token for both MI and MV
        DataTypes.InvestmentVaultInitData memory initData = DataTypes.InvestmentVaultInitData({
            mainVault: IMainVault(address(mainVault)),
            tokenMI: IERC20(address(mainToken)), // Same token as MV
            tokenMV: IERC20(address(mainToken)), // Same token as MI
            capitalOfMi: INITIAL_BALANCE,
            shareMI: 10 ** 18,
            step: STEP,
            assets: assets
        });

        bytes memory encodedInitData = abi.encodeWithSelector(InvestmentVault.initialize.selector, initData);
        proxy = new ERC1967Proxy(address(implementation), encodedInitData);
        vault = InvestmentVault(address(proxy));

        // Transfer tokens to vault and routers
        mainToken.transfer(address(vault), INITIAL_BALANCE);
        mainToken.mint(address(uniswapV3Router), INITIAL_BALANCE * 100000);
        mainToken.mint(address(quickswapV3Router), INITIAL_BALANCE * 100000);
        assetToken1.mint(address(uniswapV3Router), INITIAL_BALANCE * 100000);
        assetToken1.mint(address(quickswapV3Router), INITIAL_BALANCE * 100000);
        assetToken2.mint(address(uniswapV3Router), 1000000 * 10 ** 18);
        assetToken2.mint(address(quickswapV3Router), 1000000 * 10 ** 18);
        assetToken2.mint(address(uniswapV2Router), 1000000 * 10 ** 18);

        // Set prices in mocks - since MI and MV are same token, price should be 1:1

        uniswapV3Router.setPrice(address(assetToken1), address(mainToken), 5 * 10 ** 17);
        uniswapV3Router.setPrice(address(assetToken2), address(mainToken), 5 * 10 ** 17);

        quoterV2.setPrice(address(assetToken1), address(mainToken), 5 * 10 ** 17);
        quoterV2.setPrice(address(assetToken2), address(mainToken), 5 * 10 ** 17);

        quickswapV3Router.setPrice(address(assetToken1), address(mainToken), 5 * 10 ** 17);
        quickswapV3Router.setPrice(address(assetToken2), address(mainToken), 5 * 10 ** 17);

        quoterQuickswap.setPrice(address(assetToken1), address(mainToken), 5 * 10 ** 17);
        quoterQuickswap.setPrice(address(assetToken2), address(mainToken), 5 * 10 ** 17);

        // Approve tokens for routers
        vm.stopPrank();
        vm.startPrank(address(vault));
        mainToken.approve(address(uniswapV3Router), type(uint256).max);
        mainToken.approve(address(quickswapV3Router), type(uint256).max);
        mainToken.approve(address(uniswapV2Router), type(uint256).max);
        assetToken1.approve(address(uniswapV3Router), type(uint256).max);
        assetToken2.approve(address(uniswapV3Router), type(uint256).max);
        assetToken1.approve(address(quickswapV3Router), type(uint256).max);
        assetToken2.approve(address(quickswapV3Router), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(owner);

        // Wait for initialization pause to end
        (,, uint256 pauseToTimestamp,) = vault.vaultState();
        vm.warp(pauseToTimestamp + 1);

        // Initialize MV to Tokens swaps
        DataTypes.InitSwapsData[] memory mvToTokenPaths = new DataTypes.InitSwapsData[](2);
        uint256 totalMVBalanceForAssetSwaps = mainToken.balanceOf(address(vault));

        // Setup swap path for Asset1
        bytes memory pathBytesAsset1 = abi.encodePacked(address(mainToken), uint24(3000), address(assetToken1));
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
        mvToTokenPaths[0].path[0] = address(mainToken);
        mvToTokenPaths[0].path[1] = address(assetToken1);

        // Setup swap path for Asset2
        bytes memory pathBytesAsset2 = abi.encodePacked(address(mainToken), uint24(3000), address(assetToken2));
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
        mvToTokenPaths[1].path[0] = address(mainToken);
        mvToTokenPaths[1].path[1] = address(assetToken2);

        vault.initMvToTokensSwaps(mvToTokenPaths, block.timestamp + 1);

        // Add more main tokens to vault
        mainToken.transfer(address(vault), SWAP_AMOUNT);

        // Set manager role
        mainVault.setRole(manager, true);

        vm.stopPrank();
    }

    function testSuccessfulAsset1PurchaseWithUniswapV2() public {
        vm.startPrank(manager);
        vm.warp(block.timestamp + 31 days);
        // Set price for the swap in V2 router
        uniswapV2Router.setPrice(address(mainToken), address(assetToken1), 3 * 10 ** 18);

        uint256 amountIn = mainToken.balanceOf(address(vault)) / 400;
        address[] memory path = new address[](2);
        path[0] = address(mainToken);
        path[1] = address(assetToken1);

        // Mint tokens to router for the swap
        vm.stopPrank();
        vm.startPrank(owner);
        assetToken1.mint(address(uniswapV2Router), amountIn * 3);
        vm.stopPrank();
        vm.startPrank(manager);

        uint256 initialAssetBalance = assetToken1.balanceOf(address(vault));

        uint256[] memory amounts = vault.swapExactTokensForTokens(
            address(uniswapV2Router),
            amountIn,
            0, // amountOutMin
            path,
            block.timestamp + 1
        );

        uint256 finalAssetBalance = assetToken1.balanceOf(address(vault));

        assertEq(amounts[0], amountIn, "Input amount should be correct");
        assertEq(amounts[1], amountIn * 3, "Output amount should be correct");
        assertEq(finalAssetBalance - initialAssetBalance, amounts[1], "Asset1 balance should increase correctly");

        vm.stopPrank();
    }

    function testPurchasesAndSalesZeroStrategy() public {
        // DataTypes.AssetData memory asset1DataBefore = vault.assetsData(address(assetToken1));
        // DataTypes.TokenData memory asset1TokenDataBefore = vault.tokenData();
        vm.warp(block.timestamp + 31 days);

        vm.startPrank(manager);

        bytes memory pathBytesAsset1Buy = abi.encodePacked(address(mainToken), uint24(3000), address(assetToken1));

        uint256 amountInAsset1 = mainToken.balanceOf(address(vault)) / 400;
        uint256 newPrice = 4 * 10 ** 17;
        uniswapV3Router.setPrice(address(assetToken1), address(mainToken), newPrice);

        DataTypes.DelegateExactInputParams memory paramsAsset1Buy = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytesAsset1Buy,
            deadline: block.timestamp + 1,
            amountIn: amountInAsset1,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        uint256 asset1Bought = vault.exactInput(paramsAsset1Buy);

        // DataTypes.AssetData memory asset1DataAfterBuy = vault.assetsData(address(assetToken1));
        // assertEq(asset1DataAfterBuy.tokenBought - asset1DataBefore.tokenBought, amountInAsset1, "Asset1 bought should be correct");
        // assertEq(asset1DataAfterBuy.deposit - asset1DataBefore.deposit, int256(amountInAsset1 * newPrice) / 10**18, "Asset1 deposit should be correct");

        uniswapV3Router.setPrice(address(assetToken1), address(mainToken), 7 * 10 ** 17);

        bytes memory pathBytesAsset1Sell = abi.encodePacked(address(assetToken1), uint24(3000), address(mainToken));

        uint256 amountInAsset1Sell = assetToken1.balanceOf(address(vault)) / 5;

        DataTypes.DelegateExactInputParams memory paramsAsset1Sell = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytesAsset1Sell,
            deadline: block.timestamp + 1,
            amountIn: amountInAsset1Sell,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        vault.exactInput(paramsAsset1Sell);

        uniswapV3Router.setPrice(address(assetToken1), address(mainToken), 90 * 10 ** 17);

        bytes memory pathBytesAsset1Sell2 = abi.encodePacked(address(assetToken1), uint24(3000), address(mainToken));

        uint256 amountInAsset1Sell2 = assetToken1.balanceOf(address(vault)) / 5;

        DataTypes.DelegateExactInputParams memory paramsAsset1Sell2 = DataTypes.DelegateExactInputParams({
            router: address(uniswapV3Router),
            path: pathBytesAsset1Sell,
            deadline: block.timestamp + 1,
            amountIn: amountInAsset1Sell,
            amountOutMinimum: 0,
            swapType: DataTypes.SwapType.Default
        });

        vault.exactInput(paramsAsset1Sell2);
        // DataTypes.AssetData memory asset1DataAfterSell = vault.assetsData(address(assetToken1));
        // assertEq(asset1DataAfterSell.tokenBought - asset1DataBefore.tokenBought, amountInAsset1, "Asset1 bought should be correct");
        // assertEq(asset1DataAfterSell.deposit - asset1DataBefore.deposit, int256(amountInAsset1 * 4 * 10**17) / 10**18, "Asset1 deposit should be correct");

        vm.stopPrank();
    }

    function testSingleTokenSwapValidation() public {
        vm.startPrank(manager);

        // Since MI and MV are the same token, direct swaps between them should be invalid
        bytes memory pathBytes = abi.encodePacked(
            address(mainToken),
            uint24(3000),
            address(mainToken) // Same token
        );

        uint256 amountIn = mainToken.balanceOf(address(vault)) / 800;

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
}
