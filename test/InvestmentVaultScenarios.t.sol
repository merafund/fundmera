// // SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 fundmera.com

// https://github.com/merafund
// pragma solidity ^0.8.29;

// import {Test, console} from "forge-std/Test.sol";
// import {InvestmentVault} from "../src/InvestmentVault.sol";
// import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
// import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import {DataTypes, IMainVault} from "../src/utils/DataTypes.sol";
// import {Constants} from "../src/utils/Constants.sol";
// import {UniswapV3Mock} from "../src/mocks/UniswapV3Mock.sol";
// import {QuickswapV3Mock} from "../src/mocks/QuickswapV3Mock.sol";
// import {QuoterV2Mock} from "../src/mocks/QuoterV2Mock.sol";
// import {QuoterQuickswapMock} from "../src/mocks/QuoterQuickswapMock.sol";
// import {UniswapV2Mock} from "../src/mocks/UniswapV2Mock.sol";

// contract MockERC20 is ERC20 {
//     uint8 private _decimals;

//     constructor(string memory name, string memory symbol, uint8 tokenDecimals) ERC20(name, symbol) {
//         _decimals = tokenDecimals;
//         _mint(msg.sender, 1000000 * 10 ** decimals());
//     }

//     function mint(address to, uint256 amount) external {
//         _mint(to, amount);
//     }

//     function decimals() public view override returns (uint8) {
//         return _decimals;
//     }
// }

// contract MockMainVault {
//     bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
//     bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

//     mapping(address => bool) public roles;
//     mapping(address => bool) public availableRouters;
//     mapping(address => bool) public availableTokens;

//     bool public _paused;
//     uint256 public feePercentage;
//     uint256 public profitLockedUntil;
//     address public profitWallet;
//     address public feeWallet;
//     address public currentImplementationOfInvestmentVault;

//     constructor() {
//         roles[msg.sender] = true;
//         feePercentage = 1000;
//         profitWallet = address(0x123);
//         feeWallet = address(0x456);
//         currentImplementationOfInvestmentVault = address(0);
//     }

//     function hasRole(bytes32, /* role */ address account) external view returns (bool) {
//         return roles[account];
//     }

//     function setRole(address account, bool hasRole) external {
//         roles[account] = hasRole;
//     }

//     function paused() external view returns (bool) {
//         return _paused;
//     }

//     function setPaused(bool paused_) external {
//         _paused = paused_;
//     }

//     function setFeePercentage(uint256 _feePercentage) external {
//         feePercentage = _feePercentage;
//     }

//     function setAvailableRouter(address router, bool available) external {
//         availableRouters[router] = available;
//     }

//     function availableRouterByAdmin(address router) external view returns (bool) {
//         return availableRouters[router];
//     }

//     function setAvailableToken(address token, bool available) external {
//         availableTokens[token] = available;
//     }

//     function availableTokensByAdmin(address token) external view returns (bool) {
//         return availableTokens[token];
//     }

//     function availableRouterByInvestor(address router) external view returns (bool) {
//         return availableRouters[router];
//     }

//     function availableTokensByInvestor(address token) external view returns (bool) {
//         return availableTokens[token];
//     }

//     function setProfitLock(uint256 lockUntil) external {
//         profitLockedUntil = lockUntil;
//     }

//     function setCurrentImplementation(address impl) external {
//         currentImplementationOfInvestmentVault = impl;
//     }
// }

// contract InvestmentVaultScenarios is Test {
//     InvestmentVault public implementation;
//     ERC1967Proxy public proxy;
//     InvestmentVault public vault;
//     MockERC20 public usdce;
//     MockERC20 public wbtc;
//     MockERC20 public weth;
//     MockERC20 public wpol;
//     MockMainVault public mainVault;
//     UniswapV3Mock public uniswapV3Router;
//     QuickswapV3Mock public quickswapV3Router;
//     QuoterV2Mock public quoterV2;
//     QuoterQuickswapMock public quoterQuickswap;
//     UniswapV2Mock public uniswapV2Router;

//     uint256 public wbtcWorkingDeposit;
//     uint256 public wethWorkingDeposit;
//     uint256 public wpolWorkingDeposit;
//     uint256 public wbtcAmountOut;
//     uint256 public wethAmountOut;
//     uint256 public wpolAmountOut;
//     uint256 public wbtcAmountOutDrop;
//     uint256 public wethAmountOutDrop;
//     uint256 public wpolAmountOutDrop;
//     uint256 public wbtcSellAmount;
//     uint256 public wethSellAmount;
//     uint256 public wpolSellAmount;

//     uint256 public capital;

//     address public owner = address(1);
//     address public manager = address(2);
//     address public user = address(3);

//     // Constants for the scenario
//     uint256 public constant INITIAL_CAPITAL = 100 * 10**18; // 100 tokens
//     uint256 public constant WBTC_INITIAL_PRICE = 100000 * 10**18; // $100,000
//     uint256 public constant WETH_INITIAL_PRICE = 1000 * 10**18; // $1,000
//     uint256 public constant WPOL_INITIAL_PRICE = 1 * 10**18; // $1
//     uint256 public constant STEP = 1 * 10**17; // 10%

//     function setUp() public {
//         vm.startPrank(owner);

//         // Deploy tokens with correct decimals
//         usdce = new MockERC20("USDC.e", "USDC.e", 6); // USDC.e has 6 decimals
//         wbtc = new MockERC20("Wrapped BTC", "WBTC", 8);
//         weth = new MockERC20("Wrapped ETH", "WETH", 18);
//         wpol = new MockERC20("Wrapped POL", "WPOL", 18);

//         // Deploy routers and quoters
//         uniswapV3Router = new UniswapV3Mock();
//         quickswapV3Router = new QuickswapV3Mock();
//         quoterV2 = new QuoterV2Mock();
//         quoterQuickswap = new QuoterQuickswapMock();
//         uniswapV2Router = new UniswapV2Mock();

//         // Mint tokens for routers
//         usdce.mint(address(uniswapV3Router), 10000000 * 10**6);
//         wbtc.mint(address(uniswapV3Router), 10000000 * 10**8);
//         weth.mint(address(uniswapV3Router), 10000000 * 10**18);
//         wpol.mint(address(uniswapV3Router), 10000000 * 10**18);

//         usdce.mint(address(quickswapV3Router), 10000000 * 10**6);
//         wbtc.mint(address(quickswapV3Router), 10000000 * 10**8);
//         weth.mint(address(quickswapV3Router), 10000000 * 10**18);
//         wpol.mint(address(quickswapV3Router), 10000000 * 10**18);

//         usdce.mint(address(uniswapV2Router), 10000000 * 10**6);
//         wbtc.mint(address(uniswapV2Router), 10000 * 10**8);
//         weth.mint(address(uniswapV2Router), 100000 * 10**18);
//         wpol.mint(address(uniswapV2Router), 10000000 * 10**18);

//         // Deploy main vault
//         mainVault = new MockMainVault();
//         mainVault.setAvailableRouter(address(uniswapV3Router), true);
//         mainVault.setAvailableRouter(address(quickswapV3Router), true);
//         mainVault.setAvailableRouter(address(quoterV2), true);
//         mainVault.setAvailableRouter(address(quoterQuickswap), true);
//         mainVault.setAvailableRouter(address(uniswapV2Router), true);
//         mainVault.setAvailableToken(address(usdce), true);
//         mainVault.setAvailableToken(address(wbtc), true);
//         mainVault.setAvailableToken(address(weth), true);
//         mainVault.setAvailableToken(address(wpol), true);

//         // Deploy vault
//         implementation = new InvestmentVault();
//         mainVault.setCurrentImplementation(address(implementation));

//         // Initialize assets with zero initial deposit
//         DataTypes.AssetInitData[] memory assets = new DataTypes.AssetInitData[](3);
//         assets[0] = DataTypes.AssetInitData({
//             token: IERC20(address(wbtc)),
//             shareMV: 5 * 10**17, // 50%
//             step: STEP,
//             strategy: DataTypes.Strategy.First
//         });
//         assets[1] = DataTypes.AssetInitData({
//             token: IERC20(address(weth)),
//             shareMV: 3 * 10**17, // 30%
//             step: STEP,
//             strategy: DataTypes.Strategy.First
//         });
//         assets[2] = DataTypes.AssetInitData({
//             token: IERC20(address(wpol)),
//             shareMV: 2 * 10**17, // 20%
//             step: STEP,
//             strategy: DataTypes.Strategy.First
//         });

//         DataTypes.InvestmentVaultInitData memory initData = DataTypes.InvestmentVaultInitData({
//             mainVault: IMainVault(address(mainVault)),
//             tokenMI: IERC20(address(usdce)),
//             tokenMV: IERC20(address(usdce)),
//             initDeposit: INITIAL_CAPITAL,
//             shareMI: 10**18, // 100%
//             assets: assets
//         });

//         bytes memory encodedInitData = abi.encodeWithSelector(InvestmentVault.initialize.selector, initData);
//         proxy = new ERC1967Proxy(address(implementation), encodedInitData);
//         vault = InvestmentVault(address(proxy));

//         // Set initial prices in mocks (all prices in USDC.e with 6 decimals)
//         uniswapV3Router.setPrice(address(wbtc), address(usdce), 100000 * 10**6); // 100,000 USDC.e per WBTC
//         uniswapV3Router.setPrice(address(weth), address(usdce), 1000 * 10**6);   // 1,000 USDC.e per WETH
//         uniswapV3Router.setPrice(address(wpol), address(usdce), 1 * 10**6);      // 1 USDC.e per WPOL

//         // Set prices in quoters
//         quoterV2.setPrice(address(usdce), address(usdce), 1 * 10**6); // 1:1 ratio
//         quoterV2.setPrice(address(wbtc), address(usdce), 100000 * 10**6);
//         quoterV2.setPrice(address(weth), address(usdce), 1000 * 10**6);
//         quoterV2.setPrice(address(wpol), address(usdce), 1 * 10**6);

//         quoterQuickswap.setPrice(address(usdce), address(usdce), 1 * 10**6); // 1:1 ratio
//         quoterQuickswap.setPrice(address(wbtc), address(usdce), 100000 * 10**6);
//         quoterQuickswap.setPrice(address(weth), address(usdce), 1000 * 10**6);
//         quoterQuickswap.setPrice(address(wpol), address(usdce), 1 * 10**6);

//         // Set manager role
//         mainVault.setRole(manager, true);

//         vm.stopPrank();

//         vm.startPrank(owner);
//         usdce.mint(address(vault), INITIAL_CAPITAL);
//         capital = INITIAL_CAPITAL / 2;
//         vm.stopPrank();
//     }

//     function testCompleteInvestmentScenario() public {
//         vm.startPrank(manager);

//         // Step 1: Initial setup verification
//         verifyInitialSetup();

//         // Step 2: First purchase with working deposit and balance
//         // executeInitialPurchases();

//         // Step 3: Price drop by 10% and purchase
//         executeDropPurchases();

//         // Step 4: Price increase by 10% and sell
//         executeSells();

//         // Step 5: Portfolio closure verification
//         verifyFinalState();

//         vm.stopPrank();
//     }

//     function verifyInitialSetup() internal {
//         // Set initial timestamp
//         vm.warp(1);

//         // Initialize USDC.e to Tokens swaps
//         DataTypes.InitSwapsData[] memory usdceToTokenPaths = new DataTypes.InitSwapsData[](3);

//         bytes memory pathBytesWbtc = abi.encodePacked(
//             address(usdce),
//             uint24(3000),
//             address(wbtc)
//         );
//         bytes memory pathBytesWeth = abi.encodePacked(
//             address(usdce),
//             uint24(3000),
//             address(weth)
//         );
//         bytes memory pathBytesWpol = abi.encodePacked(
//             address(usdce),
//             uint24(3000),
//             address(wpol)
//         );

//         usdceToTokenPaths[0] = DataTypes.InitSwapsData({
//             quouter: address(quoterV2),
//             router: address(uniswapV3Router),
//             path: new address[](2),
//             pathBytes: pathBytesWbtc,
//             amountOutMin: 0,
//             capital: capital,
//             routerType: DataTypes.Router.UniswapV3
//         });
//         usdceToTokenPaths[0].path[0] = address(usdce);
//         usdceToTokenPaths[0].path[1] = address(wbtc);

//         usdceToTokenPaths[1] = DataTypes.InitSwapsData({
//             quouter: address(quoterV2),
//             router: address(uniswapV3Router),
//             path: new address[](2),
//             pathBytes: pathBytesWeth,
//             amountOutMin: 0,
//             capital: capital,
//             routerType: DataTypes.Router.UniswapV3
//         });
//         usdceToTokenPaths[1].path[0] = address(usdce);
//         usdceToTokenPaths[1].path[1] = address(weth);

//         usdceToTokenPaths[2] = DataTypes.InitSwapsData({
//             quouter: address(quoterV2),
//             router: address(uniswapV3Router),
//             path: new address[](2),
//             pathBytes: pathBytesWpol,
//             amountOutMin: 0,
//             capital: capital,
//             routerType: DataTypes.Router.UniswapV3
//         });
//         usdceToTokenPaths[2].path[0] = address(usdce);
//         usdceToTokenPaths[2].path[1] = address(wpol);
//         vm.warp(block.timestamp + 24 hours + 1);

//         vault.increaseRouterAllowance(IERC20(address(usdce)), address(uniswapV3Router), type(uint256).max);
//         vault.increaseRouterAllowance(IERC20(address(wbtc)), address(uniswapV3Router), type(uint256).max);
//         vault.increaseRouterAllowance(IERC20(address(weth)), address(uniswapV3Router), type(uint256).max);
//         vault.increaseRouterAllowance(IERC20(address(wpol)), address(uniswapV3Router), type(uint256).max);
//         vault.initMvToTokensSwaps(usdceToTokenPaths, block.timestamp + 1);

//         vm.stopPrank();

//     }

//     function executeDropPurchases() internal {
//         vm.startPrank(manager);
//         // Update prices to simulate 10% drop (in USDC.e with 6 decimals)
//         uniswapV3Router.setPrice(address(wbtc), address(usdce), 90000 * 10**6);  // 90,000 USDC.e per WBTC
//         uniswapV3Router.setPrice(address(weth), address(usdce), 900 * 10**6);    // 900 USDC.e per WETH
//         uniswapV3Router.setPrice(address(wpol), address(usdce), 9 * 10**5);      // 0.9 USDC.e per WPOL

//         // Calculate working deposit volumes according to strategy 1
//         // Working deposit = (capital * target share * step) / (1 + step)
//         uint256 wbtcWorkingDepositDrop = (capital * 5 * 10**17 * STEP) / ((1e18 + STEP) * 1e18); // 10% step
//         uint256 wethWorkingDepositDrop = (capital * 3 * 10**17 * STEP) / ((1e18 + STEP) * 1e18);
//         uint256 wpolWorkingDepositDrop = (capital * 2 * 10**17 * STEP) / ((1e18 + STEP) * 1e18);

//         // Execute purchases at lower prices
//         bytes memory pathBytesWbtc = abi.encodePacked(
//             address(usdce),
//             uint24(3000),
//             address(wbtc)
//         );
//         bytes memory pathBytesWeth = abi.encodePacked(
//             address(usdce),
//             uint24(3000),
//             address(weth)
//         );
//         bytes memory pathBytesWpol = abi.encodePacked(
//             address(usdce),
//             uint24(3000),
//             address(wpol)
//         );

//         DataTypes.DelegateExactInputParams memory wbtcParams = DataTypes.DelegateExactInputParams({
//             router: address(uniswapV3Router),
//             path: pathBytesWbtc,
//             deadline: block.timestamp + 1,
//             amountIn: wbtcWorkingDepositDrop,
//             amountOutMinimum: 0
//         });
//         wbtcAmountOutDrop = vault.exactInput(wbtcParams);

//         DataTypes.DelegateExactInputParams memory wethParams = DataTypes.DelegateExactInputParams({
//             router: address(uniswapV3Router),
//             path: pathBytesWeth,
//             deadline: block.timestamp + 1,
//             amountIn: wethWorkingDepositDrop,
//             amountOutMinimum: 0
//         });
//         wethAmountOutDrop = vault.exactInput(wethParams);

//         DataTypes.DelegateExactInputParams memory wpolParams = DataTypes.DelegateExactInputParams({
//             router: address(uniswapV3Router),
//             path: pathBytesWpol,
//             deadline: block.timestamp + 1,
//             amountIn: wpolWorkingDepositDrop,
//             amountOutMinimum: 0
//         });
//         wpolAmountOutDrop = vault.exactInput(wpolParams);
//         vm.stopPrank();
//     }

//     function executeSells() internal {
//         vm.startPrank(manager);
//         // Update prices to simulate 10% increase from initial (in USDC.e with 6 decimals)
//         uniswapV3Router.setPrice(address(wbtc), address(usdce), 110000 * 10**6); // 110,000 USDC.e per WBTC
//         uniswapV3Router.setPrice(address(weth), address(usdce), 1100 * 10**6);   // 1,100 USDC.e per WETH
//         uniswapV3Router.setPrice(address(wpol), address(usdce), 11 * 10**5);     // 1.1 USDC.e per WPOL

//         // Calculate working balance for growth
//         uint256 wbtcWorkingBalanceGrowth = (wbtcAmountOut * STEP) / (10**18 + STEP);
//         uint256 wethWorkingBalanceGrowth = (wethAmountOut * STEP) / (10**18 + STEP);
//         uint256 wpolWorkingBalanceGrowth = (wpolAmountOut * STEP) / (10**18 + STEP);

//         // Prepare reverse paths for selling
//         bytes memory pathBytesWbtcReverse = abi.encodePacked(
//             address(wbtc),
//             uint24(3000),
//             address(usdce)
//         );
//         bytes memory pathBytesWethReverse = abi.encodePacked(
//             address(weth),
//             uint24(3000),
//             address(usdce)
//         );
//         bytes memory pathBytesWpolReverse = abi.encodePacked(
//             address(wpol),
//             uint24(3000),
//             address(usdce)
//         );

//         // Sell working balance for growth
//         DataTypes.DelegateExactInputParams memory wbtcSellParams = DataTypes.DelegateExactInputParams({
//             router: address(uniswapV3Router),
//             path: pathBytesWbtcReverse,
//             deadline: block.timestamp + 1,
//             amountIn: wbtcWorkingBalanceGrowth,
//             amountOutMinimum: 0
//         });
//         wbtcSellAmount = vault.exactInput(wbtcSellParams);

//         DataTypes.DelegateExactInputParams memory wethSellParams = DataTypes.DelegateExactInputParams({
//             router: address(uniswapV3Router),
//             path: pathBytesWethReverse,
//             deadline: block.timestamp + 1,
//             amountIn: wethWorkingBalanceGrowth,
//             amountOutMinimum: 0
//         });
//         wethSellAmount = vault.exactInput(wethSellParams);

//         DataTypes.DelegateExactInputParams memory wpolSellParams = DataTypes.DelegateExactInputParams({
//             router: address(uniswapV3Router),
//             path: pathBytesWpolReverse,
//             deadline: block.timestamp + 1,
//             amountIn: wpolWorkingBalanceGrowth,
//             amountOutMinimum: 0
//         });
//         wpolSellAmount = vault.exactInput(wpolSellParams);
//         vm.stopPrank();
//     }

//     function verifyFinalState() internal {
//         // Update prices to simulate slight increase (in USDC.e with 6 decimals)
//         uniswapV3Router.setPrice(address(wbtc), address(usdce), 99990 * 10**6); // 99,990 USDC.e per WBTC
//         uniswapV3Router.setPrice(address(weth), address(usdce), 9999 * 10**5);  // 999.9 USDC.e per WETH
//         uniswapV3Router.setPrice(address(wpol), address(usdce), 9999 * 10**2);  // 0.9999 USDC.e per WPOL

//         // Sell remaining balances
//         bytes memory pathBytesWbtcReverse = abi.encodePacked(
//             address(wbtc),
//             uint24(3000),
//             address(usdce)
//         );
//         bytes memory pathBytesWethReverse = abi.encodePacked(
//             address(weth),
//             uint24(3000),
//             address(usdce)
//         );
//         bytes memory pathBytesWpolReverse = abi.encodePacked(
//             address(wpol),
//             uint24(3000),
//             address(usdce)
//         );

//         // Sell remaining balances
//         DataTypes.DelegateExactInputParams memory wbtcSellParams = DataTypes.DelegateExactInputParams({
//             router: address(uniswapV3Router),
//             path: pathBytesWbtcReverse,
//             deadline: block.timestamp + 1,
//             amountIn: wbtc.balanceOf(address(vault)),
//             amountOutMinimum: 0
//         });
//         uint256 wbtcFinalSell = vault.exactInput(wbtcSellParams);

//         DataTypes.DelegateExactInputParams memory wethSellParams = DataTypes.DelegateExactInputParams({
//             router: address(uniswapV3Router),
//             path: pathBytesWethReverse,
//             deadline: block.timestamp + 1,
//             amountIn: weth.balanceOf(address(vault)),
//             amountOutMinimum: 0
//         });
//         uint256 wethFinalSell = vault.exactInput(wethSellParams);

//         DataTypes.DelegateExactInputParams memory wpolSellParams = DataTypes.DelegateExactInputParams({
//             router: address(uniswapV3Router),
//             path: pathBytesWpolReverse,
//             deadline: block.timestamp + 1,
//             amountIn: wpol.balanceOf(address(vault)),
//             amountOutMinimum: 0
//         });
//         uint256 wpolFinalSell = vault.exactInput(wpolSellParams);

//         // Verify final state
//         (bool isPaused, uint256 totalDeposit, uint256 totalBalance, DataTypes.SwapInitState swapState) = vault.vaultState();

//         // Calculate expected profits from spreadsheet (multiplied by 10**6 to avoid decimals)
//         uint256 expectedWbtcProfit = 25020455; // 25.02045455 * 10**6
//         uint256 expectedWethProfit = 15012273; // 15.01227273 * 10**6
//         uint256 expectedWpolProfit = 10008182; // 10.00818182 * 10**6

//         uint256 totalExpectedProfit = expectedWbtcProfit + expectedWethProfit + expectedWpolProfit;

//         assertGt(totalBalance, totalDeposit, "Final balance should be greater than total deposit");
//         assertApproxEqAbs(totalBalance - totalDeposit, totalExpectedProfit, 1 * 10**6, "Profit should match expected value");
//     }
// }
