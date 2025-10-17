// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 fundmera.com

// https://github.com/merafund
pragma solidity 0.8.29;

import {Test, console} from "forge-std/Test.sol";
import {InvestmentVault} from "../src/InvestmentVault.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DataTypes, IMainVault} from "../src/utils/DataTypes.sol";
import {Constants} from "../src/utils/Constants.sol";
import {MockToken} from "../src/mocks/MockToken.sol";
import {MockMainVault} from "../src/mocks/MockMainVault.sol";
import {MockMeraPriceOracle} from "../src/mocks/MockMeraPriceOracle.sol";
import {UniswapV3Mock} from "../src/mocks/UniswapV3Mock.sol";
import {QuoterV2Mock} from "../src/mocks/QuoterV2Mock.sol";

contract PriceValidationTest is Test {
    InvestmentVault public implementation;
    ERC1967Proxy public proxy;
    InvestmentVault public vault;
    MockToken public tokenMI;
    MockToken public tokenMV;
    MockToken public tokenUSDC;
    MockToken public tokenWETH;
    MockMainVault public mainVault;
    MockMeraPriceOracle public oracle;
    UniswapV3Mock public router;
    QuoterV2Mock public quoter;

    address public owner = address(1);
    uint256 public constant INITIAL_BALANCE = 10000 * 10 ** 18;

    function setUp() public {
        vm.startPrank(owner);

        // Deploy tokens with different decimals
        tokenMI = new MockToken("MI Token", "MI", 18);
        tokenMV = new MockToken("MV Token", "MV", 18);
        tokenUSDC = new MockToken("USDC", "USDC", 6);
        tokenWETH = new MockToken("WETH", "WETH", 18);

        // Deploy mocks
        mainVault = new MockMainVault();
        oracle = new MockMeraPriceOracle();
        router = new UniswapV3Mock();
        quoter = new QuoterV2Mock();

        tokenMI.mint(address(router), 1e40);
        tokenMV.mint(address(router), 1e40);
        tokenUSDC.mint(address(router), 1e40);
        tokenWETH.mint(address(router), 1e40);

        // Setup MainVault
        mainVault.setAvailableToken(address(tokenMI), true);
        mainVault.setAvailableToken(address(tokenMV), true);
        mainVault.setAvailableToken(address(tokenUSDC), true);
        mainVault.setAvailableToken(address(tokenWETH), true);
        mainVault.setMeraPriceOracle(address(oracle));
        mainVault.setIsCanceledOracleCheck(false);

        // Set up router-quoter pairs
        DataTypes.RouterQuoterPair[] memory pairs = new DataTypes.RouterQuoterPair[](1);
        pairs[0] = DataTypes.RouterQuoterPair({router: address(router), quoter: address(quoter)});
        mainVault.setRouterQuoterPairAvailabilityByInvestor(pairs);
        mainVault.setRouterQuoterPairAvailabilityByAdmin(pairs);

        // Deploy and setup vault
        implementation = new InvestmentVault();
        mainVault.setCurrentImplementation(address(implementation));

        DataTypes.AssetInitData[] memory assets = new DataTypes.AssetInitData[](2);
        assets[0] = DataTypes.AssetInitData({
            token: IERC20(address(tokenUSDC)),
            shareToken: 5 * 10 ** 17,
            step: 5 * 10 ** 16,
            strategy: DataTypes.Strategy.Zero
        });
        assets[1] = DataTypes.AssetInitData({
            token: IERC20(address(tokenWETH)),
            shareToken: 5 * 10 ** 17,
            step: 5 * 10 ** 16,
            strategy: DataTypes.Strategy.First
        });

        DataTypes.InvestmentVaultInitData memory initData = DataTypes.InvestmentVaultInitData({
            mainVault: IMainVault(address(mainVault)),
            tokenMI: IERC20(address(tokenMI)),
            tokenMV: IERC20(address(tokenMV)),
            capitalOfMi: INITIAL_BALANCE,
            shareMV: 7 * 10 ** 17,
            step: 5 * 10 ** 16,
            assets: assets
        });

        bytes memory encodedInitData = abi.encodeWithSelector(InvestmentVault.initialize.selector, initData);
        proxy = new ERC1967Proxy(address(implementation), encodedInitData);
        vault = InvestmentVault(address(proxy));

        // Fund accounts with large balances
        tokenMI.transfer(address(vault), INITIAL_BALANCE);
        tokenMV.mint(address(router), INITIAL_BALANCE * 100); // Значительно увеличиваем баланс для свопов
        tokenUSDC.mint(address(router), 10000000 * 10 ** 6); // 10M USDC
        tokenWETH.mint(address(router), 10000 * 10 ** 18); // 10000 WETH

        // Setup approvals
        vm.stopPrank();
        vm.startPrank(address(vault));
        tokenMI.approve(address(router), type(uint256).max);
        tokenMV.approve(address(router), type(uint256).max);
        tokenUSDC.approve(address(router), type(uint256).max);
        tokenWETH.approve(address(router), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(owner);

        // Wait for initialization pause to end
        (,, uint256 pauseToTimestamp,) = vault.vaultState();
        vm.warp(pauseToTimestamp + 1);
    }

    function test_InitMiToMvSwap_WithinPriceDeviation() public {
        // Set prices in oracle
        // 1 MI = 1 USD
        oracle.setAssetPrice(address(tokenMI), 1 * 10 ** 6, 6); // Price in USD with 6 decimals
        // 1 MV = 1 USD
        oracle.setAssetPrice(address(tokenMV), 1 * 10 ** 6, 6); // Price in USD with 6 decimals

        // Set router price: 1 MI = 0.98 MV (2% deviation)
        router.setPrice(address(tokenMI), address(tokenMV), 98 * 10 ** 16); // 0.98 with 18 decimals
        quoter.setPrice(address(tokenMI), address(tokenMV), 98 * 10 ** 16);

        bytes memory pathBytes = abi.encodePacked(address(tokenMI), uint24(3000), address(tokenMV));

        DataTypes.InitSwapsData memory data = DataTypes.InitSwapsData({
            quouter: address(quoter),
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytes,
            amountOutMin: 0,
            capital: INITIAL_BALANCE,
            routerType: DataTypes.Router.UniswapV3
        });
        data.path[0] = address(tokenMI);
        data.path[1] = address(tokenMV);

        // Should not revert as price deviation is within limits
        vault.initMiToMvSwap(data, block.timestamp + 1);
    }

    function test_InitMiToMvSwap_ExceedsPriceDeviation() public {
        // Set prices in oracle
        // 1 MI = 1 USD (with 6 decimals)
        oracle.setAssetPrice(address(tokenMI), 1 * 10 ** 6, 6);
        // 1 MV = 1 USD (with 6 decimals)
        oracle.setAssetPrice(address(tokenMV), 1 * 10 ** 6, 6);

        // Set router price: 1 MI = 0.94 MV (6% deviation)
        // Both tokens have 18 decimals, so no adjustment needed
        router.setPrice(address(tokenMI), address(tokenMV), 94 * 10 ** 16); // 0.94 with 18 decimals
        quoter.setPrice(address(tokenMI), address(tokenMV), 94 * 10 ** 16);

        bytes memory pathBytes = abi.encodePacked(address(tokenMI), uint24(3000), address(tokenMV));

        DataTypes.InitSwapsData memory data = DataTypes.InitSwapsData({
            quouter: address(quoter),
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytes,
            amountOutMin: 0,
            capital: INITIAL_BALANCE,
            routerType: DataTypes.Router.UniswapV3
        });
        data.path[0] = address(tokenMI);
        data.path[1] = address(tokenMV);

        // Should revert due to price deviation > 5%
        vm.expectRevert(InvestmentVault.BigDeviationOracle.selector);
        vault.initMiToMvSwap(data, block.timestamp + 1);
    }

    function test_InitMvToTokensSwaps_WithinPriceDeviation() public {
        // First do MI to MV swap
        oracle.setAssetPrice(address(tokenMI), 1 * 10 ** 6, 6);
        oracle.setAssetPrice(address(tokenMV), 1 * 10 ** 6, 6);
        router.setPrice(address(tokenMI), address(tokenMV), 98 * 10 ** 16);
        quoter.setPrice(address(tokenMI), address(tokenMV), 98 * 10 ** 16);

        bytes memory pathBytesMiMv = abi.encodePacked(address(tokenMI), uint24(3000), address(tokenMV));
        DataTypes.InitSwapsData memory miToMvData = DataTypes.InitSwapsData({
            quouter: address(quoter),
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytesMiMv,
            amountOutMin: 0,
            capital: INITIAL_BALANCE,
            routerType: DataTypes.Router.UniswapV3
        });
        miToMvData.path[0] = address(tokenMI);
        miToMvData.path[1] = address(tokenMV);

        uint256 mvBought = vault.initMiToMvSwap(miToMvData, block.timestamp + 1);

        // Now setup MV to tokens prices
        // MV price: 1 MV = 1 USD (with 6 decimals)
        oracle.setAssetPrice(address(tokenMV), 1 * 10 ** 6, 6);
        // USDC price: 1 USDC = 1 USD (with 6 decimals)
        oracle.setAssetPrice(address(tokenUSDC), 1 * 10 ** 6, 6);
        // WETH price: 1 WETH = 2000 USD (with 6 decimals)
        oracle.setAssetPrice(address(tokenWETH), 2000 * 10 ** 6, 6);

        // Set router prices with 2% deviation
        // MV (18 decimals) to USDC (6 decimals)
        // 1 MV = 0.98 USDC
        router.setPrice(address(tokenMV), address(tokenUSDC), 98 * 10 ** (16 - 12)); // Adjust for 18 decimals
        quoter.setPrice(address(tokenMV), address(tokenUSDC), 98 * 10 ** (16 - 12));

        // MV (18 decimals) to WETH (18 decimals)
        // 1 MV = 0.00049 WETH (≈$0.98 at $2000/WETH)
        router.setPrice(address(tokenWETH), address(tokenMV), 2000 * 10 ** 18);
        quoter.setPrice(address(tokenWETH), address(tokenMV), 2000 * 10 ** 18);

        DataTypes.InitSwapsData[] memory mvToTokenPaths = new DataTypes.InitSwapsData[](2);

        // MV -> USDC path
        bytes memory pathBytesUSDC = abi.encodePacked(address(tokenMV), uint24(3000), address(tokenUSDC));
        mvToTokenPaths[0] = DataTypes.InitSwapsData({
            quouter: address(quoter),
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytesUSDC,
            amountOutMin: 0,
            capital: mvBought / 2,
            routerType: DataTypes.Router.UniswapV3
        });
        mvToTokenPaths[0].path[0] = address(tokenMV);
        mvToTokenPaths[0].path[1] = address(tokenUSDC);

        // MV -> WETH path
        bytes memory pathBytesWETH = abi.encodePacked(address(tokenMV), uint24(3000), address(tokenWETH));
        mvToTokenPaths[1] = DataTypes.InitSwapsData({
            quouter: address(quoter),
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytesWETH,
            amountOutMin: 0,
            capital: mvBought / 2,
            routerType: DataTypes.Router.UniswapV3
        });
        mvToTokenPaths[1].path[0] = address(tokenMV);
        mvToTokenPaths[1].path[1] = address(tokenWETH);

        // Should not revert as price deviations are within limits
        vault.initMvToTokensSwaps(mvToTokenPaths, block.timestamp + 1);
    }

    function test_InitMvToTokensSwaps_ExceedsPriceDeviation() public {
        // First do MI to MV swap
        oracle.setAssetPrice(address(tokenMI), 1 * 10 ** 6, 6);
        oracle.setAssetPrice(address(tokenMV), 1 * 10 ** 6, 6);
        router.setPrice(address(tokenMI), address(tokenMV), 98 * 10 ** 16);
        quoter.setPrice(address(tokenMI), address(tokenMV), 98 * 10 ** 16);

        bytes memory pathBytesMiMv = abi.encodePacked(address(tokenMI), uint24(3000), address(tokenMV));
        DataTypes.InitSwapsData memory miToMvData = DataTypes.InitSwapsData({
            quouter: address(quoter),
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytesMiMv,
            amountOutMin: 0,
            capital: INITIAL_BALANCE,
            routerType: DataTypes.Router.UniswapV3
        });
        miToMvData.path[0] = address(tokenMI);
        miToMvData.path[1] = address(tokenMV);

        uint256 mvBought = vault.initMiToMvSwap(miToMvData, block.timestamp + 1);

        // Now setup MV to tokens prices with big deviation
        // MV price: 1 MV = 1 USD (with 6 decimals)
        oracle.setAssetPrice(address(tokenMV), 1 * 10 ** 6, 6);
        // USDC price: 1 USDC = 1 USD (with 6 decimals)
        oracle.setAssetPrice(address(tokenUSDC), 1 * 10 ** 6, 6);
        // WETH price: 1 WETH = 2000 USD (with 6 decimals)
        oracle.setAssetPrice(address(tokenWETH), 2000 * 10 ** 6, 6);

        // Set router price with 6% deviation
        // MV (18 decimals) to USDC (6 decimals)
        // 1 MV = 0.94 USDC
        router.setPrice(address(tokenMV), address(tokenUSDC), 94 * 10 ** (16 - 12)); // 0.94 with 18 decimals
        quoter.setPrice(address(tokenMV), address(tokenUSDC), 94 * 10 ** (16 - 12));

        // MV (18 decimals) to WETH (18 decimals)
        // 1 MV = 0.00049 WETH (≈$0.98 at $2000/WETH)
        router.setPrice(address(tokenWETH), address(tokenMV), 49 * 10 ** 13);
        quoter.setPrice(address(tokenWETH), address(tokenMV), 49 * 10 ** 13);

        DataTypes.InitSwapsData[] memory mvToTokenPaths = new DataTypes.InitSwapsData[](2);

        // MV -> USDC path (with big deviation)
        bytes memory pathBytesUSDC = abi.encodePacked(address(tokenMV), uint24(3000), address(tokenUSDC));
        mvToTokenPaths[0] = DataTypes.InitSwapsData({
            quouter: address(quoter),
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytesUSDC,
            amountOutMin: 0,
            capital: mvBought / 2,
            routerType: DataTypes.Router.UniswapV3
        });
        mvToTokenPaths[0].path[0] = address(tokenMV);
        mvToTokenPaths[0].path[1] = address(tokenUSDC);

        // MV -> WETH path
        bytes memory pathBytesWETH = abi.encodePacked(address(tokenMV), uint24(3000), address(tokenWETH));
        mvToTokenPaths[1] = DataTypes.InitSwapsData({
            quouter: address(quoter),
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytesWETH,
            amountOutMin: 0,
            capital: mvBought / 2,
            routerType: DataTypes.Router.UniswapV3
        });
        mvToTokenPaths[1].path[0] = address(tokenMV);
        mvToTokenPaths[1].path[1] = address(tokenWETH);

        // Should revert due to price deviation > 5%
        vm.expectRevert(InvestmentVault.BigDeviationOracle.selector);
        vault.initMvToTokensSwaps(mvToTokenPaths, block.timestamp + 1);
    }

    function test_DifferentDecimals_WithinPriceDeviation() public {
        // First do MI to MV swap to initialize state
        oracle.setAssetPrice(address(tokenMI), 1 * 10 ** 6, 6);
        oracle.setAssetPrice(address(tokenMV), 1 * 10 ** 6, 6);
        router.setPrice(address(tokenMI), address(tokenMV), 98 * 10 ** 16);
        quoter.setPrice(address(tokenMI), address(tokenMV), 98 * 10 ** 16);

        bytes memory pathBytesMiMv = abi.encodePacked(address(tokenMI), uint24(3000), address(tokenMV));
        DataTypes.InitSwapsData memory miToMvData = DataTypes.InitSwapsData({
            quouter: address(quoter),
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytesMiMv,
            amountOutMin: 0,
            capital: INITIAL_BALANCE,
            routerType: DataTypes.Router.UniswapV3
        });
        miToMvData.path[0] = address(tokenMI);
        miToMvData.path[1] = address(tokenMV);

        uint256 mvBought = vault.initMiToMvSwap(miToMvData, block.timestamp + 1);

        // Set prices in oracle with different decimals
        // MV price: 1 MV = 1 USD (with 6 decimals)
        oracle.setAssetPrice(address(tokenMV), 1 * 10 ** 6, 6);
        // USDC price: 1 USDC = 1 USD (with 6 decimals)
        oracle.setAssetPrice(address(tokenUSDC), 1 * 10 ** 6, 6);
        // WETH price: 1 WETH = 2000 USD (with 6 decimals)
        oracle.setAssetPrice(address(tokenWETH), 2000 * 10 ** 6, 6);

        // Set router prices with 2% deviation
        // MV (18 decimals) to USDC (6 decimals)
        // 1 MV = 0.98 USDC
        router.setPrice(address(tokenMV), address(tokenUSDC), 98 * 10 ** (16 - 12)); // Adjust for 18 decimals
        quoter.setPrice(address(tokenMV), address(tokenUSDC), 98 * 10 ** (16 - 12));

        // MV (18 decimals) to WETH (18 decimals)
        // 1 MV = 0.00049 WETH (≈$0.98 at $2000/WETH)
        router.setPrice(address(tokenWETH), address(tokenMV), 2000 * 10 ** 18);
        quoter.setPrice(address(tokenWETH), address(tokenMV), 2000 * 10 ** 18);

        DataTypes.InitSwapsData[] memory mvToTokenPaths = new DataTypes.InitSwapsData[](2);

        // MV -> USDC path
        bytes memory pathBytesUSDC = abi.encodePacked(address(tokenMV), uint24(3000), address(tokenUSDC));
        mvToTokenPaths[0] = DataTypes.InitSwapsData({
            quouter: address(quoter),
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytesUSDC,
            amountOutMin: 0,
            capital: mvBought / 2,
            routerType: DataTypes.Router.UniswapV3
        });
        mvToTokenPaths[0].path[0] = address(tokenMV);
        mvToTokenPaths[0].path[1] = address(tokenUSDC);

        // MV -> WETH path
        bytes memory pathBytesWETH = abi.encodePacked(address(tokenMV), uint24(3000), address(tokenWETH));
        mvToTokenPaths[1] = DataTypes.InitSwapsData({
            quouter: address(quoter),
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytesWETH,
            amountOutMin: 0,
            capital: mvBought / 2,
            routerType: DataTypes.Router.UniswapV3
        });
        mvToTokenPaths[1].path[0] = address(tokenMV);
        mvToTokenPaths[1].path[1] = address(tokenWETH);

        // Should not revert as price deviation is within limits
        vault.initMvToTokensSwaps(mvToTokenPaths, block.timestamp + 1);
    }
}
