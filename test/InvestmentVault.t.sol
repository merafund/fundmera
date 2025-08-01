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
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {UniswapV3Mock} from "../src/mocks/UniswapV3Mock.sol";
import {QuickswapV3Mock} from "../src/mocks/QuickswapV3Mock.sol";
import {QuoterV2Mock} from "../src/mocks/QuoterV2Mock.sol";
import {QuoterQuickswapMock} from "../src/mocks/QuoterQuickswapMock.sol";
import {MockToken} from "../src/mocks/MockToken.sol";
import {MockMainVault} from "../src/mocks/MockMainVault.sol";

contract MockRouter {
    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        pure
        returns (uint256[] memory amounts)
    {
        require(path.length >= 2, "Invalid path");

        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        amounts[path.length - 1] = amountIn / 2; // 50% output as per mock implementation

        return amounts;
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256, /* amountOutMin */
        address[] calldata path,
        address to,
        uint256 /* deadline */
    ) external returns (uint256[] memory amounts) {
        require(path.length >= 2, "Invalid path");

        uint256 amountOut = amountIn / 2; // 50% output as per mock implementation

        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        IERC20(path[path.length - 1]).transfer(to, amountOut);

        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        amounts[path.length - 1] = amountOut;

        return amounts;
    }
}

contract InvestmentVaultTest is Test {
    InvestmentVault public implementation;
    ERC1967Proxy public proxy;
    InvestmentVault public vault;
    MockToken public tokenMI;
    MockToken public tokenMV;
    MockToken public assetToken1;
    MockToken public assetToken2;
    MockMainVault public mainVault;
    MockRouter public router;

    address public owner = address(1);
    address public user1 = address(2);
    address public user2 = address(3);

    uint256 public constant INITIAL_BALANCE = 10000 * 10 ** 18;
    uint256 public constant INVEST_AMOUNT = 1000 * 10 ** 18;

    event MiToMvSwapInitialized(address router, uint256 amountIn, uint256 amountOut, uint256 timestamp);
    event MvToTokensSwapsInitialized(uint256 tokensCount, uint256 timestamp);
    event PositionClosed(
        uint256 initialDeposit,
        uint256 finalBalance,
        uint256 totalProfit,
        uint256 investorProfit,
        uint256 feeProfit,
        uint256 feePercentage
    );
    event ProfitWithdrawn(
        bool investorProfitWithdrawn, uint256 investorProfitAmount, bool feeProfitWithdrawn, uint256 feeProfitAmount
    );

    event TokenAllowanceIncreased(address token, address router, uint256 amount);
    event TokenAllowanceDecreased(address token, address router, uint256 amount);
    event AssetShareUpdated(address indexed token, uint256 oldShareMV, uint256 newShareMV);
    event AssetCapitalUpdated(address indexed token, uint256 oldCapital, uint256 newCapital);
    event ShareMiUpdated(uint256 oldShareMI, uint256 newShareMI);

    function setUp_SameTokens() public {
        vm.startPrank(owner);

        tokenMI = new MockToken("Same Token", "SAME", 18);
        assetToken1 = new MockToken("Asset Token 1", "AT1", 18);
        assetToken2 = new MockToken("Asset Token 2", "AT2", 6);
        router = new MockRouter();

        mainVault = new MockMainVault();
        mainVault.setAvailableRouter(address(router), true);
        mainVault.setAvailableToken(address(tokenMI), true);
        mainVault.setAvailableToken(address(assetToken1), true);
        mainVault.setAvailableToken(address(assetToken2), true);

        implementation = new InvestmentVault();
        mainVault.setCurrentImplementation(address(implementation));

        DataTypes.AssetInitData[] memory assets = new DataTypes.AssetInitData[](2);

        assets[0] = DataTypes.AssetInitData({
            token: IERC20(address(assetToken1)),
            shareMV: 5 * 10 ** 17,
            step: 5 * 10 ** 16,
            strategy: DataTypes.Strategy.Zero
        });

        assets[1] = DataTypes.AssetInitData({
            token: IERC20(address(assetToken2)),
            shareMV: 5 * 10 ** 17,
            step: 5 * 10 ** 16,
            strategy: DataTypes.Strategy.First
        });

        DataTypes.InvestmentVaultInitData memory initData = DataTypes.InvestmentVaultInitData({
            mainVault: IMainVault(address(mainVault)),
            tokenMI: IERC20(address(tokenMI)),
            tokenMV: IERC20(address(tokenMI)),
            initDeposit: INITIAL_BALANCE,
            shareMI: Constants.SHARE_DENOMINATOR,
            step: 5 * 10 ** 16,
            assets: assets
        });

        bytes memory encodedInitData = abi.encodeWithSelector(InvestmentVault.initialize.selector, initData);

        proxy = new ERC1967Proxy(address(implementation), encodedInitData);

        vault = InvestmentVault(address(proxy));

        tokenMI.transfer(address(vault), INITIAL_BALANCE);

        vm.stopPrank();
    }

    function setUp_DifferentTokens() public {
        vm.startPrank(owner);

        tokenMI = new MockToken("MI Token", "MI", 18);
        tokenMV = new MockToken("MV Token", "MV", 18);
        assetToken1 = new MockToken("Asset Token 1", "AT1", 18);
        assetToken2 = new MockToken("Asset Token 2", "AT2", 6);
        router = new MockRouter();

        mainVault = new MockMainVault();
        mainVault.setAvailableRouter(address(router), true);
        mainVault.setAvailableToken(address(tokenMI), true);
        mainVault.setAvailableToken(address(tokenMV), true);
        mainVault.setAvailableToken(address(assetToken1), true);
        mainVault.setAvailableToken(address(assetToken2), true);

        implementation = new InvestmentVault();
        mainVault.setCurrentImplementation(address(implementation));

        DataTypes.AssetInitData[] memory assets = new DataTypes.AssetInitData[](2);

        assets[0] = DataTypes.AssetInitData({
            token: IERC20(address(assetToken1)),
            shareMV: 5 * 10 ** 17,
            step: 5 * 10 ** 16,
            strategy: DataTypes.Strategy.Zero
        });

        assets[1] = DataTypes.AssetInitData({
            token: IERC20(address(assetToken2)),
            shareMV: 5 * 10 ** 17,
            step: 5 * 10 ** 16,
            strategy: DataTypes.Strategy.First
        });

        DataTypes.InvestmentVaultInitData memory initData = DataTypes.InvestmentVaultInitData({
            mainVault: IMainVault(address(mainVault)),
            tokenMI: IERC20(address(tokenMI)),
            tokenMV: IERC20(address(tokenMV)),
            initDeposit: INITIAL_BALANCE,
            shareMI: 7 * 10 ** 17,
            step: 5 * 10 ** 16,
            assets: assets
        });

        bytes memory encodedInitData = abi.encodeWithSelector(InvestmentVault.initialize.selector, initData);

        proxy = new ERC1967Proxy(address(implementation), encodedInitData);

        vault = InvestmentVault(address(proxy));

        tokenMI.transfer(address(vault), INITIAL_BALANCE);

        tokenMV.transfer(address(router), INITIAL_BALANCE);

        assetToken1.transfer(address(router), INITIAL_BALANCE);
        assetToken2.mint(address(router), 1000000 * 10 ** 18);

        vm.stopPrank();
    }

    function setUp_DifferentTokens_FixedProfit() public {
        vm.startPrank(owner);

        tokenMI = new MockToken("MI Token", "MI", 18);
        tokenMV = new MockToken("MV Token", "MV", 18);
        assetToken1 = new MockToken("Asset Token 1", "AT1", 18);
        assetToken2 = new MockToken("Asset Token 2", "AT2", 6);
        router = new MockRouter();

        mainVault = new MockMainVault();
        mainVault.setProfitType(DataTypes.ProfitType.Fixed);
        mainVault.setAvailableRouter(address(router), true);
        mainVault.setAvailableToken(address(tokenMI), true);
        mainVault.setAvailableToken(address(tokenMV), true);
        mainVault.setAvailableToken(address(assetToken1), true);
        mainVault.setAvailableToken(address(assetToken2), true);

        implementation = new InvestmentVault();
        mainVault.setCurrentImplementation(address(implementation));

        DataTypes.AssetInitData[] memory assets = new DataTypes.AssetInitData[](2);

        assets[0] = DataTypes.AssetInitData({
            token: IERC20(address(assetToken1)),
            shareMV: 5 * 10 ** 17,
            step: 5 * 10 ** 16,
            strategy: DataTypes.Strategy.Zero
        });

        assets[1] = DataTypes.AssetInitData({
            token: IERC20(address(assetToken2)),
            shareMV: 5 * 10 ** 17,
            step: 5 * 10 ** 16,
            strategy: DataTypes.Strategy.First
        });

        DataTypes.InvestmentVaultInitData memory initData = DataTypes.InvestmentVaultInitData({
            mainVault: IMainVault(address(mainVault)),
            tokenMI: IERC20(address(tokenMI)),
            tokenMV: IERC20(address(tokenMV)),
            initDeposit: INITIAL_BALANCE,
            shareMI: 7 * 10 ** 17,
            step: 5 * 10 ** 16,
            assets: assets
        });

        bytes memory encodedInitData = abi.encodeWithSelector(InvestmentVault.initialize.selector, initData);

        proxy = new ERC1967Proxy(address(implementation), encodedInitData);

        vault = InvestmentVault(address(proxy));

        tokenMI.transfer(address(vault), INITIAL_BALANCE);

        tokenMV.transfer(address(router), INITIAL_BALANCE);

        assetToken1.transfer(address(router), INITIAL_BALANCE);
        assetToken2.mint(address(router), 1000000 * 10 ** 18);

        vm.stopPrank();
    }

    function setUp_SameTokens_FixedProfit() public {
        vm.startPrank(owner);

        tokenMI = new MockToken("Same Token", "SAME", 18);
        assetToken1 = new MockToken("Asset Token 1", "AT1", 18);
        assetToken2 = new MockToken("Asset Token 2", "AT2", 6);
        router = new MockRouter();

        mainVault = new MockMainVault();
        mainVault.setProfitType(DataTypes.ProfitType.Fixed);
        mainVault.setAvailableRouter(address(router), true);
        mainVault.setAvailableToken(address(tokenMI), true);
        mainVault.setAvailableToken(address(assetToken1), true);
        mainVault.setAvailableToken(address(assetToken2), true);

        implementation = new InvestmentVault();
        mainVault.setCurrentImplementation(address(implementation));

        DataTypes.AssetInitData[] memory assets = new DataTypes.AssetInitData[](2);

        assets[0] = DataTypes.AssetInitData({
            token: IERC20(address(assetToken1)),
            shareMV: 5 * 10 ** 17,
            step: 5 * 10 ** 16,
            strategy: DataTypes.Strategy.Zero
        });

        assets[1] = DataTypes.AssetInitData({
            token: IERC20(address(assetToken2)),
            shareMV: 5 * 10 ** 17,
            step: 5 * 10 ** 16,
            strategy: DataTypes.Strategy.First
        });

        DataTypes.InvestmentVaultInitData memory initData = DataTypes.InvestmentVaultInitData({
            mainVault: IMainVault(address(mainVault)),
            tokenMI: IERC20(address(tokenMI)),
            tokenMV: IERC20(address(tokenMI)),
            initDeposit: INITIAL_BALANCE,
            shareMI: Constants.SHARE_DENOMINATOR,
            step: 5 * 10 ** 16,
            assets: assets
        });

        bytes memory encodedInitData = abi.encodeWithSelector(InvestmentVault.initialize.selector, initData);

        proxy = new ERC1967Proxy(address(implementation), encodedInitData);

        vault = InvestmentVault(address(proxy));

        tokenMI.transfer(address(vault), INITIAL_BALANCE);

        vm.stopPrank();
    }

    function testInitializationSameTokens() public {
        setUp_SameTokens();

        (IERC20 tMI, IERC20 tMV, uint256 initDeposit, uint256 mvBought, uint256 shareMI,,,,,,) = vault.tokenData();

        assertEq(address(tMI), address(tMV), "MI and MV tokens should be the same");
        assertEq(initDeposit, INITIAL_BALANCE, "Initial deposit should match");
        assertEq(mvBought, INITIAL_BALANCE, "MV bought should equal initial deposit for same tokens");
        assertEq(shareMI, Constants.SHARE_DENOMINATOR, "Share MI should be 100% for same tokens");

        (,,, DataTypes.SwapInitState swapInitState) = vault.vaultState();
        assertEq(
            uint256(swapInitState),
            uint256(DataTypes.SwapInitState.MiToMvInitialized),
            "Swap state should be MiToMvInitialized"
        );
    }

    function testInitializationDifferentTokens() public {
        setUp_DifferentTokens();

        (IERC20 tMI, IERC20 tMV, uint256 initDeposit, uint256 mvBought, uint256 shareMI,,,,,,) = vault.tokenData();

        assertEq(address(tMI), address(tokenMI), "MI token should match");
        assertEq(address(tMV), address(tokenMV), "MV token should match");
        assertEq(initDeposit, INITIAL_BALANCE, "Initial deposit should match");
        assertEq(mvBought, 0, "MV bought should be 0 initially");
        assertEq(shareMI, 7 * 10 ** 17, "Share MI should be 70%");

        (,,, DataTypes.SwapInitState swapInitState) = vault.vaultState();
        assertEq(
            uint256(swapInitState),
            uint256(DataTypes.SwapInitState.NotInitialized),
            "Swap state should be NotInitialized"
        );
    }

    function testClosePositionWithProfit() public {
        setUp_SameTokens();

        vm.startPrank(owner);

        uint256 profit = 500 * 10 ** 18;
        tokenMI.mint(address(vault), profit);

        vault.closePosition();

        (bool closed,,,) = vault.vaultState();
        assertTrue(closed, "Position should be closed");

        (, uint256 earntProfitInvestor, uint256 earntProfitFee, uint256 earntProfitTotal,,) = vault.profitData();

        uint256 expectedFee = profit * mainVault.feePercentage() / Constants.MAX_PERCENT;
        uint256 expectedInvestorProfit = profit - expectedFee;

        assertEq(earntProfitInvestor, expectedInvestorProfit, "Investor profit should be calculated correctly");
        assertEq(earntProfitFee, expectedFee, "Fee profit should be calculated correctly");
        assertEq(earntProfitTotal, profit, "Total profit should match added amount");

        vm.stopPrank();
    }

    function testClosePosition_AlreadyClosed() public {
        setUp_SameTokens();

        vm.startPrank(owner);

        // First close position
        uint256 profit = 500 * 10 ** 18;
        tokenMI.mint(address(vault), profit);
        vault.closePosition();

        // Try to close again
        vm.expectRevert(InvestmentVault.PositionAlreadyClosed.selector);
        vault.closePosition();

        vm.stopPrank();
    }

    function testClosePosition_NoProfit() public {
        setUp_SameTokens();

        vm.startPrank(owner);

        // Withdraw some tokens to ensure no profit
        vm.stopPrank();
        vm.startPrank(address(mainVault));
        vault.withdraw(tokenMI, INITIAL_BALANCE / 2, owner);
        vm.stopPrank();
        vm.startPrank(owner);

        vm.expectRevert(InvestmentVault.NoProfit.selector);
        vault.closePosition();

        vm.stopPrank();
    }

    function testWithdrawProfit() public {
        testClosePositionWithProfit();

        vm.startPrank(owner);

        uint256 currentTime = block.timestamp;
        mainVault.setProfitLock(currentTime - 1);

        (bool investorProfitWithdrawn, uint256 investorProfitAmount, bool feeProfitWithdrawn, uint256 feeProfitAmount) =
            vault.withdrawProfit();

        assertTrue(investorProfitWithdrawn, "Investor profit should be withdrawn");
        assertTrue(feeProfitWithdrawn, "Fee profit should be withdrawn");

        (
            ,
            uint256 earntProfitInvestor,
            uint256 earntProfitFee,
            ,
            uint256 withdrawnProfitInvestor,
            uint256 withdrawnProfitFee
        ) = vault.profitData();

        assertEq(investorProfitAmount, earntProfitInvestor, "Investor profit amount should match");
        assertEq(feeProfitAmount, earntProfitFee, "Fee profit amount should match");
        assertEq(withdrawnProfitInvestor, earntProfitInvestor, "Withdrawn investor profit should match earned");
        assertEq(withdrawnProfitFee, earntProfitFee, "Withdrawn fee profit should match earned");

        vm.stopPrank();
    }

    function testWithdrawProfit_NoProfitToWithdraw() public {
        setUp_SameTokens();
        vm.startPrank(owner);

        vm.expectRevert(InvestmentVault.NoProfitToWithdraw.selector);
        vault.withdrawProfit();

        vm.stopPrank();
    }

    function testIncreaseRouterAllowance() public {
        setUp_SameTokens();
        vm.startPrank(owner);

        uint256 amount = 1000 * 10 ** 18;

        vault.increaseRouterAllowance(IERC20(address(tokenMI)), address(router), amount);

        assertEq(tokenMI.allowance(address(vault), address(router)), amount);

        vm.stopPrank();
    }

    function testIncreaseRouterAllowance_TokenNotAvailable() public {
        setUp_SameTokens();
        vm.startPrank(owner);

        MockToken unavailableToken = new MockToken("Unavailable", "UNAV", 18);

        vm.expectRevert(InvestmentVault.TokenNotAvailable.selector);
        vault.increaseRouterAllowance(IERC20(address(unavailableToken)), address(router), 1000);

        vm.stopPrank();
    }

    function testIncreaseRouterAllowance_RouterNotAvailable() public {
        setUp_SameTokens();
        vm.startPrank(owner);

        address unavailableRouter = address(0x123);

        vm.expectRevert(InvestmentVault.RouterNotAvailable.selector);
        vault.increaseRouterAllowance(IERC20(address(tokenMI)), unavailableRouter, 1000);

        vm.stopPrank();
    }

    function testDecreaseRouterAllowance() public {
        setUp_SameTokens();
        vm.startPrank(owner);

        uint256 initialAmount = 1000 * 10 ** 18;
        uint256 decreaseAmount = 400 * 10 ** 18;

        // First increase allowance
        vault.increaseRouterAllowance(IERC20(address(tokenMI)), address(router), initialAmount);

        // Check initial allowance
        assertEq(tokenMI.allowance(address(vault), address(router)), initialAmount);

        vault.decreaseRouterAllowance(IERC20(address(tokenMI)), address(router), decreaseAmount);

        assertEq(tokenMI.allowance(address(vault), address(router)), initialAmount - decreaseAmount);

        vm.stopPrank();
    }

    function testDecreaseRouterAllowance_MainContractPaused() public {
        setUp_SameTokens();
        vm.startPrank(owner);

        // Set main vault to paused state
        mainVault.setPaused(true);

        vm.expectRevert(InvestmentVault.MainContractIsPaused.selector);
        vault.decreaseRouterAllowance(IERC20(address(tokenMI)), address(router), 1000);

        vm.stopPrank();
    }

    function testIncreaseRouterAllowance_MainContractPaused() public {
        setUp_SameTokens();
        vm.startPrank(owner);

        // Set main vault to paused state
        mainVault.setPaused(true);

        vm.expectRevert(InvestmentVault.MainContractIsPaused.selector);
        vault.increaseRouterAllowance(IERC20(address(tokenMI)), address(router), 1000);

        vm.stopPrank();
    }

    function testSetAssetShares_ArrayLengthMismatch() public {
        setUp_DifferentTokens();
        vm.startPrank(owner);

        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = IERC20(address(assetToken1));
        tokens[1] = IERC20(address(assetToken2));

        uint256[] memory shares = new uint256[](1);
        shares[0] = 6 * 10 ** 17;

        vm.expectRevert(InvestmentVault.ArrayLengthsMustMatch.selector);
        vault.setAssetShares(tokens, shares);

        vm.stopPrank();
    }

    function testSetAssetShares_AssetNotFound() public {
        setUp_DifferentTokens();
        vm.startPrank(owner);

        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(address(0x123)); // Non-existent token

        uint256[] memory shares = new uint256[](1);
        shares[0] = 6 * 10 ** 17;

        vm.expectRevert(InvestmentVault.AssetNotFound.selector);
        vault.setAssetShares(tokens, shares);

        vm.stopPrank();
    }

    function testSetAssetCapital() public {
        setUp_DifferentTokens();
        vm.startPrank(owner);

        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(address(assetToken1));
        // tokens[1] = IERC20(address(assetToken2));

        uint256[] memory capitals = new uint256[](1);
        capitals[0] = 0;
        // capitals[1] = 500 * 10 ** 6;

        // Expect events for both tokens
        vm.expectEmit(true, false, false, true);
        emit AssetCapitalUpdated(address(tokens[0]), 0, capitals[0]);
        // vm.expectEmit(true, false, false, true);
        // emit AssetCapitalUpdated(address(tokens[1]), 0, capitals[1]);

        vault.setAssetCapital(tokens, capitals);

        vm.stopPrank();
    }

    function testSetAssetCapital_ArrayLengthMismatch() public {
        setUp_DifferentTokens();
        vm.startPrank(owner);

        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = IERC20(address(assetToken1));
        tokens[1] = IERC20(address(assetToken2));

        uint256[] memory capitals = new uint256[](1);
        capitals[0] = 1000 * 10 ** 18;

        vm.expectRevert(InvestmentVault.ArrayLengthsMustMatch.selector);
        vault.setAssetCapital(tokens, capitals);

        vm.stopPrank();
    }

    function testSetAssetCapital_AssetNotFound() public {
        setUp_DifferentTokens();
        vm.startPrank(owner);

        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(address(0x123)); // Non-existent token

        uint256[] memory capitals = new uint256[](1);
        capitals[0] = 1000 * 10 ** 18;

        vm.expectRevert(InvestmentVault.AssetNotFound.selector);
        vault.setAssetCapital(tokens, capitals);

        vm.stopPrank();
    }

    function testSetAssetCapital_MainContractPaused() public {
        setUp_DifferentTokens();
        vm.startPrank(owner);

        // Set main vault to paused state
        mainVault.setPaused(true);

        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = IERC20(address(assetToken1));
        tokens[1] = IERC20(address(assetToken2));

        uint256[] memory capitals = new uint256[](2);
        capitals[0] = 1000 * 10 ** 18;
        capitals[1] = 500 * 10 ** 6;

        vm.expectRevert(InvestmentVault.MainContractIsPaused.selector);
        vault.setAssetCapital(tokens, capitals);

        vm.stopPrank();
    }

    function testSetShareMi_ExceedsMaximum() public {
        setUp_DifferentTokens();
        vm.startPrank(owner);

        // Need to initialize swaps first before setting capital
        (,, uint256 pauseToTimestamp,) = vault.vaultState();
        vm.warp(pauseToTimestamp + 1);

        // Approve tokens for router from vault
        vm.stopPrank();
        vm.startPrank(address(vault));
        tokenMI.approve(address(router), type(uint256).max);
        tokenMV.approve(address(router), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(owner);

        // First initialize MI to MV swap
        bytes memory pathBytesMiMv = abi.encodePacked(address(tokenMI), uint24(3000), address(tokenMV));

        DataTypes.InitSwapsData memory miToMvData = DataTypes.InitSwapsData({
            quouter: address(router),
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytesMiMv,
            amountOutMin: 0,
            capital: INITIAL_BALANCE,
            routerType: DataTypes.Router.UniswapV2
        });
        miToMvData.path[0] = address(tokenMI);
        miToMvData.path[1] = address(tokenMV);

        // Initialize MI to MV swap
        vault.initMiToMvSwap(miToMvData, block.timestamp + 1);

        // Now prepare MV to Tokens swaps data
        DataTypes.InitSwapsData[] memory mvToTokenPaths = new DataTypes.InitSwapsData[](2);

        // Path for first asset (MV -> Asset1)
        bytes memory pathBytesAsset1 = abi.encodePacked(address(tokenMV), uint24(3000), address(assetToken1));

        mvToTokenPaths[0] = DataTypes.InitSwapsData({
            quouter: address(router),
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytesAsset1,
            amountOutMin: 0,
            capital: INITIAL_BALANCE / 4,
            routerType: DataTypes.Router.UniswapV2
        });
        mvToTokenPaths[0].path[0] = address(tokenMV);
        mvToTokenPaths[0].path[1] = address(assetToken1);

        // Path for second asset (MV -> Asset2)
        bytes memory pathBytesAsset2 = abi.encodePacked(address(tokenMV), uint24(3000), address(assetToken2));

        mvToTokenPaths[1] = DataTypes.InitSwapsData({
            quouter: address(router),
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytesAsset2,
            amountOutMin: 0,
            capital: INITIAL_BALANCE / 4,
            routerType: DataTypes.Router.UniswapV2
        });
        mvToTokenPaths[1].path[0] = address(tokenMV);
        mvToTokenPaths[1].path[1] = address(assetToken2);

        // Initialize MV to Tokens swaps
        vault.initMvToTokensSwaps(mvToTokenPaths, block.timestamp + 1);

        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(address(assetToken1));
        uint256[] memory capitals = new uint256[](1);
        capitals[0] = 3000 * 10 ** 18; // Set capital less than mvBought (3500 * 10**18)
        vault.setAssetCapital(tokens, capitals);

        uint256[] memory shares = new uint256[](1);

        shares[0] = 1 * 10 ** 18;
        vm.expectRevert(InvestmentVault.ShareMustBeLessThanOrEqualToDeposit.selector);
        vault.setAssetShares(tokens, shares);

        uint256 newShareMI = 1 * 10 ** 18;

        vm.expectRevert(InvestmentVault.ShareMustBeLessThanOrEqualToDeposit.selector);
        vault.setShareMi(newShareMI);

        vm.stopPrank();
    }

    function testSetShareMi_MainContractPaused() public {
        setUp_DifferentTokens();
        vm.startPrank(owner);

        // Set main vault to paused state
        mainVault.setPaused(true);

        vm.expectRevert(InvestmentVault.MainContractIsPaused.selector);
        vault.setShareMi(8 * 10 ** 17);

        vm.stopPrank();
    }

    function testUpgradeImplementation() public {
        setUp_DifferentTokens();
        vm.startPrank(owner);

        address newImplementation = address(new InvestmentVaultV2());
        mainVault.setCurrentImplementation(newImplementation);

        // Upgrade should succeed when implementation matches mainVault's current implementation
        InvestmentVault(address(vault)).upgradeToAndCall(newImplementation, "");

        vm.stopPrank();
    }

    function testUpgradeImplementation_InvalidImplementation() public {
        setUp_DifferentTokens();
        vm.startPrank(owner);

        address newImplementation = address(new InvestmentVaultV2());
        address differentImplementation = address(new InvestmentVaultV2());

        // Set a different implementation in mainVault than what we're trying to upgrade to
        mainVault.setCurrentImplementation(differentImplementation);

        // Should revert because implementation doesn't match mainVault's current implementation
        vm.expectRevert(InvestmentVault.InvalidImplementationAddress.selector);
        InvestmentVault(address(vault)).upgradeToAndCall(newImplementation, "");

        vm.stopPrank();
    }

    function testUpgradeImplementation_OnlyAdmin() public {
        setUp_DifferentTokens();

        address newImplementation = address(new InvestmentVaultV2());
        mainVault.setCurrentImplementation(newImplementation);

        // Try to upgrade from non-admin address
        vm.startPrank(user1);
        vm.expectRevert(InvestmentVault.OnlyAdminError.selector);
        UUPSUpgradeable(address(vault)).upgradeToAndCall(newImplementation, "");
        vm.stopPrank();
    }

    function testInitMiToMvSwap() public {
        setUp_DifferentTokens();

        vm.startPrank(owner);
        (,, uint256 pauseToTimestamp,) = vault.vaultState();
        vm.warp(pauseToTimestamp + 1);

        // Approve tokens for router from vault
        vm.stopPrank();
        vm.startPrank(address(vault));
        tokenMI.approve(address(router), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(owner);

        bytes memory pathBytes = abi.encodePacked(address(tokenMI), uint24(3000), address(tokenMV));

        DataTypes.InitSwapsData memory data = DataTypes.InitSwapsData({
            quouter: address(router),
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytes,
            amountOutMin: 0,
            capital: INITIAL_BALANCE,
            routerType: DataTypes.Router.UniswapV2
        });
        data.path[0] = address(tokenMI);
        data.path[1] = address(tokenMV);

        uint256 amountIn = (INITIAL_BALANCE * 7 * 10 ** 17) / Constants.SHARE_DENOMINATOR;
        uint256 amountOut = amountIn / 2; // From MockRouter implementation

        vm.expectEmit(true, false, false, true);
        emit MiToMvSwapInitialized(address(router), amountIn, amountOut, block.timestamp);

        vault.initMiToMvSwap(data, block.timestamp + 1);
        vm.stopPrank();
    }

    // function testInitMiToMvSwap_SwapAlreadyInitialized() public {
    //     setUp_DifferentTokens();

    //     vm.startPrank(owner);
    //     (,, uint256 pauseToTimestamp,) = vault.vaultState();
    //     vm.warp(pauseToTimestamp + 1);

    //     // Approve tokens for router from vault
    //     vm.stopPrank();
    //     vm.startPrank(address(vault));
    //     tokenMI.approve(address(router), type(uint256).max);
    //     vm.stopPrank();
    //     vm.startPrank(owner);

    //     bytes memory pathBytes = abi.encodePacked(address(tokenMI), uint24(3000), address(tokenMV));

    //     DataTypes.InitSwapsData memory data = DataTypes.InitSwapsData({
    //         quouter: address(router),
    //         router: address(router),
    //         path: new address[](2),
    //         pathBytes: pathBytes,
    //         amountOutMin: 0,
    //         capital: INITIAL_BALANCE,
    //         routerType: DataTypes.Router.UniswapV2
    //     });
    //     data.path[0] = address(tokenMI);
    //     data.path[1] = address(tokenMV);

    //     // First initialization
    //     vault.initMiToMvSwap(data, block.timestamp + 1);

    //     // Try to initialize again - should revert
    //     vm.expectRevert(InvestmentVault.SwapAlreadyInitialized.selector);
    //     vault.initMiToMvSwap(data, block.timestamp + 1);
    //     vm.stopPrank();
    // }

    function testInitMiToMvSwap_NotEnoughBalance() public {
        setUp_DifferentTokens();

        vm.startPrank(owner);
        (,, uint256 pauseToTimestamp,) = vault.vaultState();
        vm.warp(pauseToTimestamp + 1);

        // Approve tokens for router from vault
        vm.stopPrank();
        vm.startPrank(address(vault));
        tokenMI.approve(address(router), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(owner);

        // Withdraw some tokens to create insufficient balance
        vm.stopPrank();
        vm.startPrank(address(mainVault));
        vault.withdraw(tokenMI, INITIAL_BALANCE / 2, owner);
        vm.stopPrank();
        vm.startPrank(owner);

        bytes memory pathBytes = abi.encodePacked(address(tokenMI), uint24(3000), address(tokenMV));

        DataTypes.InitSwapsData memory data = DataTypes.InitSwapsData({
            quouter: address(router),
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytes,
            amountOutMin: 0,
            capital: INITIAL_BALANCE,
            routerType: DataTypes.Router.UniswapV2
        });
        data.path[0] = address(tokenMI);
        data.path[1] = address(tokenMV);

        vm.expectRevert(InvestmentVault.NotEnoughBalance.selector);
        vault.initMiToMvSwap(data, block.timestamp + 1);
        vm.stopPrank();
    }

    function testInitMiToMvSwapUniswapV3() public {
        setUp_DifferentTokens();

        vm.startPrank(owner);
        (,, uint256 pauseToTimestamp,) = vault.vaultState();
        vm.warp(pauseToTimestamp + 1);

        // Deploy UniswapV3 mock and quoter
        UniswapV3Mock uniswapV3Router = new UniswapV3Mock();
        QuoterV2Mock quoterV2 = new QuoterV2Mock();

        // Set price in mocks (1 MI = 0.5 MV)
        uniswapV3Router.setPrice(address(tokenMI), address(tokenMV), 5 * 10 ** 17);
        quoterV2.setPrice(address(tokenMI), address(tokenMV), 5 * 10 ** 17);

        // Transfer MV tokens to router
        tokenMV.transfer(address(uniswapV3Router), INITIAL_BALANCE);

        // Set router and quoter as available in main vault
        mainVault.setAvailableRouter(address(uniswapV3Router), true);
        mainVault.setAvailableRouter(address(quoterV2), true);

        // Approve tokens for router from vault
        vm.stopPrank();
        vm.startPrank(address(vault));
        tokenMI.approve(address(uniswapV3Router), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(owner);

        bytes memory pathBytes = abi.encodePacked(address(tokenMI), uint24(3000), address(tokenMV));

        DataTypes.InitSwapsData memory data = DataTypes.InitSwapsData({
            quouter: address(quoterV2),
            router: address(uniswapV3Router),
            path: new address[](2),
            pathBytes: pathBytes,
            amountOutMin: 0,
            capital: INITIAL_BALANCE,
            routerType: DataTypes.Router.UniswapV3
        });
        data.path[0] = address(tokenMI);
        data.path[1] = address(tokenMV);

        uint256 amountIn = (INITIAL_BALANCE * 7 * 10 ** 17) / Constants.SHARE_DENOMINATOR;
        uint256 amountOut = (amountIn * 5 * 10 ** 17) / 1e18; // Based on mock price

        vm.expectEmit(true, false, false, true);
        emit MiToMvSwapInitialized(address(uniswapV3Router), amountIn, amountOut, block.timestamp);

        vault.initMiToMvSwap(data, block.timestamp + 1);
        vm.stopPrank();
    }

    function testInitMiToMvSwapQuickswapV3() public {
        setUp_DifferentTokens();

        vm.startPrank(owner);
        (,, uint256 pauseToTimestamp,) = vault.vaultState();
        vm.warp(pauseToTimestamp + 1);

        // Deploy QuickswapV3 mock and quoter
        QuickswapV3Mock quickswapV3Router = new QuickswapV3Mock();
        QuoterQuickswapMock quoterQuickswap = new QuoterQuickswapMock();

        // Set price in mocks (1 MI = 0.5 MV)
        quickswapV3Router.setPrice(address(tokenMI), address(tokenMV), 5 * 10 ** 17);
        quoterQuickswap.setPrice(address(tokenMI), address(tokenMV), 5 * 10 ** 17);

        // Transfer MV tokens to router
        tokenMV.transfer(address(quickswapV3Router), INITIAL_BALANCE);

        // Set router and quoter as available in main vault
        mainVault.setAvailableRouter(address(quickswapV3Router), true);
        mainVault.setAvailableRouter(address(quoterQuickswap), true);

        // Approve tokens for router from vault
        vm.stopPrank();
        vm.startPrank(address(vault));
        tokenMI.approve(address(quickswapV3Router), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(owner);

        bytes memory pathBytes = abi.encodePacked(address(tokenMI), uint24(3000), address(tokenMV));

        DataTypes.InitSwapsData memory data = DataTypes.InitSwapsData({
            quouter: address(quoterQuickswap),
            router: address(quickswapV3Router),
            path: new address[](2),
            pathBytes: pathBytes,
            amountOutMin: 0,
            capital: INITIAL_BALANCE,
            routerType: DataTypes.Router.QuickswapV3
        });
        data.path[0] = address(tokenMI);
        data.path[1] = address(tokenMV);

        uint256 amountIn = (INITIAL_BALANCE * 7 * 10 ** 17) / Constants.SHARE_DENOMINATOR;
        uint256 amountOut = (amountIn * 5 * 10 ** 17) / 1e18; // Based on mock price

        vm.expectEmit(true, false, false, true);
        emit MiToMvSwapInitialized(address(quickswapV3Router), amountIn, amountOut, block.timestamp);

        vault.initMiToMvSwap(data, block.timestamp + 1);
        vm.stopPrank();
    }

    function testInitMvToTokensSwaps() public {
        setUp_DifferentTokens();

        vm.startPrank(owner);
        (,, uint256 pauseToTimestamp,) = vault.vaultState();
        vm.warp(pauseToTimestamp + 1);

        // First we need to initialize MI to MV swap
        bytes memory pathBytesMiMv = abi.encodePacked(address(tokenMI), uint24(3000), address(tokenMV));

        DataTypes.InitSwapsData memory miToMvData = DataTypes.InitSwapsData({
            quouter: address(router),
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytesMiMv,
            amountOutMin: 0,
            capital: INITIAL_BALANCE,
            routerType: DataTypes.Router.UniswapV2
        });
        miToMvData.path[0] = address(tokenMI);
        miToMvData.path[1] = address(tokenMV);

        // Approve tokens for router from vault
        vm.stopPrank();
        vm.startPrank(address(vault));
        tokenMI.approve(address(router), type(uint256).max);
        tokenMV.approve(address(router), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(owner);

        // Initialize MI to MV swap first
        uint256 mvBought = vault.initMiToMvSwap(miToMvData, block.timestamp + 1);

        // Now prepare MV to Tokens swaps data
        DataTypes.InitSwapsData[] memory mvToTokenPaths = new DataTypes.InitSwapsData[](2);

        // Path for first asset (MV -> Asset1)
        bytes memory pathBytesAsset1 = abi.encodePacked(address(tokenMV), uint24(3000), address(assetToken1));

        mvToTokenPaths[0] = DataTypes.InitSwapsData({
            quouter: address(router),
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytesAsset1,
            amountOutMin: 0,
            capital: mvBought / 4,
            routerType: DataTypes.Router.UniswapV2
        });
        mvToTokenPaths[0].path[0] = address(tokenMV);
        mvToTokenPaths[0].path[1] = address(assetToken1);

        // Path for second asset (MV -> Asset2)
        bytes memory pathBytesAsset2 = abi.encodePacked(address(tokenMV), uint24(3000), address(assetToken2));

        mvToTokenPaths[1] = DataTypes.InitSwapsData({
            quouter: address(router),
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytesAsset2,
            amountOutMin: 0,
            capital: mvBought / 4,
            routerType: DataTypes.Router.UniswapV2
        });
        mvToTokenPaths[1].path[0] = address(tokenMV);
        mvToTokenPaths[1].path[1] = address(assetToken2);

        vm.expectEmit(true, false, false, true);
        emit MvToTokensSwapsInitialized(mvToTokenPaths.length, block.timestamp);

        vault.initMvToTokensSwaps(mvToTokenPaths, block.timestamp + 1);

        // Verify final state
        (,,, DataTypes.SwapInitState swapInitState) = vault.vaultState();
        assertEq(
            uint256(swapInitState),
            uint256(DataTypes.SwapInitState.FullyInitialized),
            "Swap state should be FullyInitialized"
        );

        vm.stopPrank();
    }

    function testInitMvToTokensSwaps_InvalidSwapState() public {
        setUp_DifferentTokens();

        vm.startPrank(owner);
        (,, uint256 pauseToTimestamp, DataTypes.SwapInitState swapInitState) = vault.vaultState();
        vm.warp(pauseToTimestamp + 1);
        console.log("swapInitState", uint256(swapInitState));

        // Try to initialize MV to Tokens swaps without initializing MI to MV first
        DataTypes.InitSwapsData[] memory mvToTokenPaths = new DataTypes.InitSwapsData[](2);

        vm.expectRevert(InvestmentVault.InvalidSwapState.selector);
        vault.initMvToTokensSwaps(mvToTokenPaths, block.timestamp + 1);

        vm.stopPrank();
    }

    function testInitMvToTokensSwaps_InvalidMvToTokenPaths() public {
        setUp_DifferentTokens();

        vm.startPrank(owner);
        (,, uint256 pauseToTimestamp,) = vault.vaultState();
        vm.warp(pauseToTimestamp + 1);

        // First initialize MI to MV swap
        bytes memory pathBytesMiMv = abi.encodePacked(address(tokenMI), uint24(3000), address(tokenMV));

        DataTypes.InitSwapsData memory miToMvData = DataTypes.InitSwapsData({
            quouter: address(router),
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytesMiMv,
            amountOutMin: 0,
            capital: INITIAL_BALANCE,
            routerType: DataTypes.Router.UniswapV2
        });
        miToMvData.path[0] = address(tokenMI);
        miToMvData.path[1] = address(tokenMV);

        // Approve tokens for router from vault
        vm.stopPrank();
        vm.startPrank(address(vault));
        tokenMI.approve(address(router), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(owner);

        vault.initMiToMvSwap(miToMvData, block.timestamp + 1);

        // Try to initialize with wrong number of paths
        DataTypes.InitSwapsData[] memory mvToTokenPaths = new DataTypes.InitSwapsData[](1); // Should be 2

        vm.expectRevert(InvestmentVault.InvalidMvToTokenPaths.selector);
        vault.initMvToTokensSwaps(mvToTokenPaths, block.timestamp + 1);

        vm.stopPrank();
    }

    function testInitMvToTokensSwaps_RouterNotAvailable() public {
        setUp_DifferentTokens();

        vm.startPrank(owner);
        (,, uint256 pauseToTimestamp,) = vault.vaultState();
        vm.warp(pauseToTimestamp + 1);

        // First initialize MI to MV swap
        bytes memory pathBytesMiMv = abi.encodePacked(address(tokenMI), uint24(3000), address(tokenMV));

        DataTypes.InitSwapsData memory miToMvData = DataTypes.InitSwapsData({
            quouter: address(router),
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytesMiMv,
            amountOutMin: 0,
            capital: INITIAL_BALANCE,
            routerType: DataTypes.Router.UniswapV2
        });
        miToMvData.path[0] = address(tokenMI);
        miToMvData.path[1] = address(tokenMV);

        // Approve tokens for router from vault
        vm.stopPrank();
        vm.startPrank(address(vault));
        tokenMI.approve(address(router), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(owner);

        vault.initMiToMvSwap(miToMvData, block.timestamp + 1);

        // Try to initialize with unavailable router
        DataTypes.InitSwapsData[] memory mvToTokenPaths = new DataTypes.InitSwapsData[](2);
        address unavailableRouter = address(0x123);

        mvToTokenPaths[0] = DataTypes.InitSwapsData({
            quouter: address(router),
            router: unavailableRouter,
            path: new address[](2),
            pathBytes: pathBytesMiMv,
            amountOutMin: 0,
            capital: INITIAL_BALANCE,
            routerType: DataTypes.Router.UniswapV2
        });
        mvToTokenPaths[0].path[0] = address(tokenMV);
        mvToTokenPaths[0].path[1] = address(assetToken1);

        mvToTokenPaths[1] = DataTypes.InitSwapsData({
            quouter: address(router),
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytesMiMv,
            amountOutMin: 0,
            capital: INITIAL_BALANCE,
            routerType: DataTypes.Router.UniswapV2
        });
        mvToTokenPaths[1].path[0] = address(tokenMV);
        mvToTokenPaths[1].path[1] = address(assetToken2);

        vm.expectRevert(InvestmentVault.RouterNotAvailable.selector);
        vault.initMvToTokensSwaps(mvToTokenPaths, block.timestamp + 1);

        vm.stopPrank();
    }

    function testInitMiToMvSwap_InvalidMiInPath() public {
        setUp_DifferentTokens();

        vm.startPrank(owner);
        (,, uint256 pauseToTimestamp,) = vault.vaultState();
        vm.warp(pauseToTimestamp + 1);

        // Approve tokens for router from vault
        vm.stopPrank();
        vm.startPrank(address(vault));
        tokenMI.approve(address(router), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(owner);

        bytes memory pathBytes = abi.encodePacked(
            address(tokenMV), // Wrong token - should be tokenMI
            uint24(3000),
            address(tokenMV)
        );

        DataTypes.InitSwapsData memory data = DataTypes.InitSwapsData({
            quouter: address(router),
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytes,
            amountOutMin: 0,
            capital: INITIAL_BALANCE,
            routerType: DataTypes.Router.UniswapV2
        });
        data.path[0] = address(tokenMV); // Wrong token - should be tokenMI
        data.path[1] = address(tokenMV);

        vm.expectRevert(InvestmentVault.InvalidMiInPath.selector);
        vault.initMiToMvSwap(data, block.timestamp + 1);
        vm.stopPrank();
    }

    function testInitMiToMvSwap_InvalidMvInPath() public {
        setUp_DifferentTokens();

        vm.startPrank(owner);
        (,, uint256 pauseToTimestamp,) = vault.vaultState();
        vm.warp(pauseToTimestamp + 1);

        // Approve tokens for router from vault
        vm.stopPrank();
        vm.startPrank(address(vault));
        tokenMI.approve(address(router), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(owner);

        bytes memory pathBytes = abi.encodePacked(
            address(tokenMI),
            uint24(3000),
            address(tokenMI) // Wrong token - should be tokenMV
        );

        DataTypes.InitSwapsData memory data = DataTypes.InitSwapsData({
            quouter: address(router),
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytes,
            amountOutMin: 0,
            capital: INITIAL_BALANCE,
            routerType: DataTypes.Router.UniswapV2
        });
        data.path[0] = address(tokenMI);
        data.path[1] = address(tokenMI); // Wrong token - should be tokenMV

        vm.expectRevert(InvestmentVault.InvalidMvInPath.selector);
        vault.initMiToMvSwap(data, block.timestamp + 1);
        vm.stopPrank();
    }

    function testInitMiToMvSwap_RouterNotAvailable() public {
        setUp_DifferentTokens();

        vm.startPrank(owner);
        (,, uint256 pauseToTimestamp,) = vault.vaultState();
        vm.warp(pauseToTimestamp + 1);

        // Approve tokens for router from vault
        vm.stopPrank();
        vm.startPrank(address(vault));
        tokenMI.approve(address(router), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(owner);

        // Set router as unavailable
        mainVault.setAvailableRouter(address(router), false);

        bytes memory pathBytes = abi.encodePacked(address(tokenMI), uint24(3000), address(tokenMV));

        DataTypes.InitSwapsData memory data = DataTypes.InitSwapsData({
            quouter: address(router),
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytes,
            amountOutMin: 0,
            capital: INITIAL_BALANCE,
            routerType: DataTypes.Router.UniswapV2
        });
        data.path[0] = address(tokenMI);
        data.path[1] = address(tokenMV);

        vm.expectRevert(InvestmentVault.RouterNotAvailable.selector);
        vault.initMiToMvSwap(data, block.timestamp + 1);
        vm.stopPrank();
    }

    function testInitMiToMvSwap_QuoterNotAvailable() public {
        setUp_DifferentTokens();

        vm.startPrank(owner);
        (,, uint256 pauseToTimestamp,) = vault.vaultState();
        vm.warp(pauseToTimestamp + 1);

        // Approve tokens for router from vault
        vm.stopPrank();
        vm.startPrank(address(vault));
        tokenMI.approve(address(router), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(owner);

        // Set quoter as unavailable
        mainVault.setAvailableRouter(address(router), true); // Ensure router is available
        address unavailableQuoter = address(0x123);
        mainVault.setAvailableRouter(unavailableQuoter, false);

        bytes memory pathBytes = abi.encodePacked(address(tokenMI), uint24(3000), address(tokenMV));

        DataTypes.InitSwapsData memory data = DataTypes.InitSwapsData({
            quouter: unavailableQuoter,
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytes,
            amountOutMin: 0,
            capital: INITIAL_BALANCE,
            routerType: DataTypes.Router.UniswapV2
        });
        data.path[0] = address(tokenMI);
        data.path[1] = address(tokenMV);

        vm.expectRevert(InvestmentVault.QuoterNotAvailable.selector);
        vault.initMiToMvSwap(data, block.timestamp + 1);
        vm.stopPrank();
    }

    function testInitMvToTokensSwaps_QuoterNotAvailable() public {
        setUp_DifferentTokens();

        vm.startPrank(owner);
        (,, uint256 pauseToTimestamp,) = vault.vaultState();
        vm.warp(pauseToTimestamp + 1);

        // First initialize MI to MV swap
        bytes memory pathBytesMiMv = abi.encodePacked(address(tokenMI), uint24(3000), address(tokenMV));

        DataTypes.InitSwapsData memory miToMvData = DataTypes.InitSwapsData({
            quouter: address(router),
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytesMiMv,
            amountOutMin: 0,
            capital: INITIAL_BALANCE,
            routerType: DataTypes.Router.UniswapV2
        });
        miToMvData.path[0] = address(tokenMI);
        miToMvData.path[1] = address(tokenMV);

        // Approve tokens for router from vault
        vm.stopPrank();
        vm.startPrank(address(vault));
        tokenMI.approve(address(router), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(owner);

        vault.initMiToMvSwap(miToMvData, block.timestamp + 1);

        // Set quoter as unavailable
        address unavailableQuoter = address(0x123);
        mainVault.setAvailableRouter(unavailableQuoter, false);

        // Prepare MV to Tokens swaps data
        DataTypes.InitSwapsData[] memory mvToTokenPaths = new DataTypes.InitSwapsData[](2);

        mvToTokenPaths[0] = DataTypes.InitSwapsData({
            quouter: unavailableQuoter,
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytesMiMv,
            amountOutMin: 0,
            capital: INITIAL_BALANCE,
            routerType: DataTypes.Router.UniswapV2
        });
        mvToTokenPaths[0].path[0] = address(tokenMV);
        mvToTokenPaths[0].path[1] = address(assetToken1);

        mvToTokenPaths[1] = DataTypes.InitSwapsData({
            quouter: address(router),
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytesMiMv,
            amountOutMin: 0,
            capital: INITIAL_BALANCE,
            routerType: DataTypes.Router.UniswapV2
        });
        mvToTokenPaths[1].path[0] = address(tokenMV);
        mvToTokenPaths[1].path[1] = address(assetToken2);

        vm.expectRevert(InvestmentVault.QuoterNotAvailable.selector);
        vault.initMvToTokensSwaps(mvToTokenPaths, block.timestamp + 1);
        vm.stopPrank();
    }

    function testInitMvToTokensSwaps_InvalidMVToken() public {
        setUp_DifferentTokens();

        vm.startPrank(owner);
        (,, uint256 pauseToTimestamp,) = vault.vaultState();
        vm.warp(pauseToTimestamp + 1);

        // First initialize MI to MV swap
        bytes memory pathBytesMiMv = abi.encodePacked(address(tokenMI), uint24(3000), address(tokenMV));

        DataTypes.InitSwapsData memory miToMvData = DataTypes.InitSwapsData({
            quouter: address(router),
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytesMiMv,
            amountOutMin: 0,
            capital: INITIAL_BALANCE,
            routerType: DataTypes.Router.UniswapV2
        });
        miToMvData.path[0] = address(tokenMI);
        miToMvData.path[1] = address(tokenMV);

        // Approve tokens for router from vault
        vm.stopPrank();
        vm.startPrank(address(vault));
        tokenMI.approve(address(router), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(owner);

        vault.initMiToMvSwap(miToMvData, block.timestamp + 1);

        // Prepare MV to Tokens swaps data with wrong first token
        DataTypes.InitSwapsData[] memory mvToTokenPaths = new DataTypes.InitSwapsData[](2);

        mvToTokenPaths[0] = DataTypes.InitSwapsData({
            quouter: address(router),
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytesMiMv,
            amountOutMin: 0,
            capital: INITIAL_BALANCE,
            routerType: DataTypes.Router.UniswapV2
        });
        mvToTokenPaths[0].path[0] = address(tokenMI); // Wrong token - should be tokenMV
        mvToTokenPaths[0].path[1] = address(assetToken1);

        mvToTokenPaths[1] = DataTypes.InitSwapsData({
            quouter: address(router),
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytesMiMv,
            amountOutMin: 0,
            capital: INITIAL_BALANCE,
            routerType: DataTypes.Router.UniswapV2
        });
        mvToTokenPaths[1].path[0] = address(tokenMV);
        mvToTokenPaths[1].path[1] = address(assetToken2);

        vm.expectRevert(InvestmentVault.InvalidMVToken.selector);
        vault.initMvToTokensSwaps(mvToTokenPaths, block.timestamp + 1);
        vm.stopPrank();
    }

    function testInitMvToTokensSwaps_InsufficientMvCapital() public {
        setUp_DifferentTokens();

        vm.startPrank(owner);
        (,, uint256 pauseToTimestamp,) = vault.vaultState();
        vm.warp(pauseToTimestamp + 1);

        // First initialize MI to MV swap
        bytes memory pathBytesMiMv = abi.encodePacked(address(tokenMI), uint24(3000), address(tokenMV));

        DataTypes.InitSwapsData memory miToMvData = DataTypes.InitSwapsData({
            quouter: address(router),
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytesMiMv,
            amountOutMin: 0,
            capital: INITIAL_BALANCE,
            routerType: DataTypes.Router.UniswapV2
        });
        miToMvData.path[0] = address(tokenMI);
        miToMvData.path[1] = address(tokenMV);

        // Approve tokens for router from vault
        vm.stopPrank();
        vm.startPrank(address(vault));
        tokenMI.approve(address(router), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(owner);

        vault.initMiToMvSwap(miToMvData, block.timestamp + 1);

        // Prepare MV to Tokens swaps data with too large capital
        DataTypes.InitSwapsData[] memory mvToTokenPaths = new DataTypes.InitSwapsData[](2);

        mvToTokenPaths[0] = DataTypes.InitSwapsData({
            quouter: address(router),
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytesMiMv,
            amountOutMin: 0,
            capital: INITIAL_BALANCE * 2, // Too large capital
            routerType: DataTypes.Router.UniswapV2
        });
        mvToTokenPaths[0].path[0] = address(tokenMV);
        mvToTokenPaths[0].path[1] = address(assetToken1);

        mvToTokenPaths[1] = DataTypes.InitSwapsData({
            quouter: address(router),
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytesMiMv,
            amountOutMin: 0,
            capital: INITIAL_BALANCE * 2, // Too large capital
            routerType: DataTypes.Router.UniswapV2
        });
        mvToTokenPaths[1].path[0] = address(tokenMV);
        mvToTokenPaths[1].path[1] = address(assetToken2);

        vm.expectRevert(InvestmentVault.InsufficientMvCapital.selector);
        vault.initMvToTokensSwaps(mvToTokenPaths, block.timestamp + 1);
        vm.stopPrank();
    }

    function testWithdraw_OnlyMainVault() public {
        setUp_SameTokens();

        // Try to withdraw from non-mainVault address
        vm.startPrank(user1);
        vm.expectRevert(InvestmentVault.OnlyMainVaultError.selector);
        vault.withdraw(tokenMI, 1000, user1);
        vm.stopPrank();
    }

    function testInitMiToMvSwap_InitializePause() public {
        setUp_DifferentTokens();

        vm.startPrank(owner);
        (,, uint256 pauseToTimestamp,) = vault.vaultState();

        // Try to initialize before pause period ends
        vm.warp(pauseToTimestamp - 1);

        bytes memory pathBytes = abi.encodePacked(address(tokenMI), uint24(3000), address(tokenMV));

        DataTypes.InitSwapsData memory data = DataTypes.InitSwapsData({
            quouter: address(router),
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytes,
            amountOutMin: 0,
            capital: INITIAL_BALANCE,
            routerType: DataTypes.Router.UniswapV2
        });
        data.path[0] = address(tokenMI);
        data.path[1] = address(tokenMV);

        vm.expectRevert(InvestmentVault.InitializePause.selector);
        vault.initMiToMvSwap(data, block.timestamp + 1);
        vm.stopPrank();
    }

    function testInitMvToTokensSwaps_InitializePause() public {
        setUp_SameTokens();

        vm.startPrank(owner);
        (,, uint256 pauseToTimestamp,) = vault.vaultState();

        // Try to initialize before pause period ends
        vm.warp(pauseToTimestamp - 1);

        // Prepare MV to Tokens swaps data
        DataTypes.InitSwapsData[] memory mvToTokenPaths = new DataTypes.InitSwapsData[](2);

        // Path for first asset (MV -> Asset1)
        bytes memory pathBytesAsset1 = abi.encodePacked(
            address(tokenMI), // Using tokenMI as it's the same as tokenMV
            uint24(3000),
            address(assetToken1)
        );

        mvToTokenPaths[0] = DataTypes.InitSwapsData({
            quouter: address(router),
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytesAsset1,
            amountOutMin: 0,
            capital: INITIAL_BALANCE / 4,
            routerType: DataTypes.Router.UniswapV2
        });
        mvToTokenPaths[0].path[0] = address(tokenMI); // Using tokenMI as it's the same as tokenMV
        mvToTokenPaths[0].path[1] = address(assetToken1);

        // Path for second asset (MV -> Asset2)
        bytes memory pathBytesAsset2 = abi.encodePacked(
            address(tokenMI), // Using tokenMI as it's the same as tokenMV
            uint24(3000),
            address(assetToken2)
        );

        mvToTokenPaths[1] = DataTypes.InitSwapsData({
            quouter: address(router),
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytesAsset2,
            amountOutMin: 0,
            capital: INITIAL_BALANCE / 4,
            routerType: DataTypes.Router.UniswapV2
        });
        mvToTokenPaths[1].path[0] = address(tokenMI); // Using tokenMI as it's the same as tokenMV
        mvToTokenPaths[1].path[1] = address(assetToken2);

        vm.expectRevert(InvestmentVault.InitializePause.selector);
        vault.initMvToTokensSwaps(mvToTokenPaths, block.timestamp + 1);
        vm.stopPrank();
    }

    function testInitMiToMvSwap_PriceDeviation() public {
        setUp_DifferentTokens();

        vm.startPrank(owner);
        (,, uint256 pauseToTimestamp,) = vault.vaultState();
        vm.warp(pauseToTimestamp + 1);

        // Deploy broken UniswapV3 mock and quoter
        UniswapV3Mock uniswapV3Router = new UniswapV3Mock();
        QuoterV2Mock quoterV2 = new QuoterV2Mock();

        // Set different prices in mocks to cause deviation
        // First quote: 1 MI = 0.5 MV
        uniswapV3Router.setPrice(address(tokenMI), address(tokenMV), 5 * 10 ** 17);
        // Second quote: 1 MI = 0.8 MV (big deviation)
        quoterV2.setPrice(address(tokenMI), address(tokenMV), 8 * 10 ** 17);

        // Transfer MV tokens to router
        tokenMV.transfer(address(uniswapV3Router), INITIAL_BALANCE);

        // Set router and quoter as available in main vault
        mainVault.setAvailableRouter(address(uniswapV3Router), true);
        mainVault.setAvailableRouter(address(quoterV2), true);

        // Approve tokens for router from vault
        vm.stopPrank();
        vm.startPrank(address(vault));
        tokenMI.approve(address(uniswapV3Router), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(owner);

        bytes memory pathBytes = abi.encodePacked(address(tokenMI), uint24(3000), address(tokenMV));

        DataTypes.InitSwapsData memory data = DataTypes.InitSwapsData({
            quouter: address(quoterV2),
            router: address(uniswapV3Router),
            path: new address[](2),
            pathBytes: pathBytes,
            amountOutMin: 0,
            capital: INITIAL_BALANCE,
            routerType: DataTypes.Router.UniswapV3
        });
        data.path[0] = address(tokenMI);
        data.path[1] = address(tokenMV);

        vm.expectRevert(InvestmentVault.BigDeviation.selector);
        vault.initMiToMvSwap(data, block.timestamp + 1);
        vm.stopPrank();
    }

    function testSetShareMV_ExceedsDepositShare() public {
        setUp_DifferentTokens();
        vm.startPrank(owner);

        // Need to initialize swaps first before setting capital
        (,, uint256 pauseToTimestamp,) = vault.vaultState();
        vm.warp(pauseToTimestamp + 1);

        // Approve tokens for router from vault
        vm.stopPrank();
        vm.startPrank(address(vault));
        tokenMI.approve(address(router), type(uint256).max);
        tokenMV.approve(address(router), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(owner);

        // First initialize MI to MV swap
        bytes memory pathBytesMiMv = abi.encodePacked(address(tokenMI), uint24(3000), address(tokenMV));

        DataTypes.InitSwapsData memory miToMvData = DataTypes.InitSwapsData({
            quouter: address(router),
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytesMiMv,
            amountOutMin: 0,
            capital: INITIAL_BALANCE,
            routerType: DataTypes.Router.UniswapV2
        });
        miToMvData.path[0] = address(tokenMI);
        miToMvData.path[1] = address(tokenMV);

        // Initialize MI to MV swap
        vault.initMiToMvSwap(miToMvData, block.timestamp + 1);

        // Now prepare MV to Tokens swaps data
        DataTypes.InitSwapsData[] memory mvToTokenPaths = new DataTypes.InitSwapsData[](2);

        // Path for first asset (MV -> Asset1)
        bytes memory pathBytesAsset1 = abi.encodePacked(address(tokenMV), uint24(3000), address(assetToken1));

        mvToTokenPaths[0] = DataTypes.InitSwapsData({
            quouter: address(router),
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytesAsset1,
            amountOutMin: 0,
            capital: INITIAL_BALANCE / 4,
            routerType: DataTypes.Router.UniswapV2
        });
        mvToTokenPaths[0].path[0] = address(tokenMV);
        mvToTokenPaths[0].path[1] = address(assetToken1);

        // Path for second asset (MV -> Asset2)
        bytes memory pathBytesAsset2 = abi.encodePacked(address(tokenMV), uint24(3000), address(assetToken2));

        mvToTokenPaths[1] = DataTypes.InitSwapsData({
            quouter: address(router),
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytesAsset2,
            amountOutMin: 0,
            capital: INITIAL_BALANCE / 4,
            routerType: DataTypes.Router.UniswapV2
        });
        mvToTokenPaths[1].path[0] = address(tokenMV);
        mvToTokenPaths[1].path[1] = address(assetToken2);

        // Initialize MV to Tokens swaps
        vault.initMvToTokensSwaps(mvToTokenPaths, block.timestamp + 1);

        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(address(assetToken1));
        uint256[] memory capitals = new uint256[](1);
        capitals[0] = 3000 * 10 ** 18; // Set capital less than mvBought (3500 * 10**18)
        vault.setAssetCapital(tokens, capitals);

        uint256[] memory shares = new uint256[](1);

        shares[0] = 1 * 10 ** 18;
        vm.expectRevert(InvestmentVault.ShareMustBeLessThanOrEqualToDeposit.selector);
        vault.setAssetShares(tokens, shares);

        uint256 newShareMI = 1 * 10 ** 18;

        vm.expectRevert(InvestmentVault.ShareMustBeLessThanOrEqualToDeposit.selector);
        vault.setShareMi(newShareMI);

        vm.stopPrank();
    }

    function testAssetAlreadyBought() public {
        setUp_DifferentTokens();
        vm.startPrank(owner);
        UniswapV3Mock v3Mock = new UniswapV3Mock();
        tokenMV.mint(address(v3Mock), 1e20);
        assetToken1.mint(address(v3Mock), 1e20);
        bytes memory pathBytesMiMv = abi.encodePacked(address(tokenMI), uint24(3000), address(tokenMV));

        DataTypes.InitSwapsData memory miToMvData = DataTypes.InitSwapsData({
            quouter: address(router),
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytesMiMv,
            amountOutMin: 0,
            capital: INITIAL_BALANCE,
            routerType: DataTypes.Router.UniswapV2
        });
        miToMvData.path[0] = address(tokenMI);
        miToMvData.path[1] = address(tokenMV);

        vm.stopPrank();
        vm.startPrank(address(vault));
        tokenMI.approve(address(router), type(uint256).max);
        tokenMV.approve(address(router), type(uint256).max);
        tokenMV.approve(address(v3Mock), type(uint256).max);
        assetToken1.approve(address(v3Mock), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(owner);
        vm.warp(block.timestamp + 1 days);
        tokenMV.mint(address(v3Mock), 1e30);
        tokenMI.mint(address(v3Mock), 1e30);

        uint256 mvBought = vault.initMiToMvSwap(miToMvData, block.timestamp + 1);

        DataTypes.InitSwapsData[] memory mvToTokenPaths = new DataTypes.InitSwapsData[](2);

        // Path for first asset (MV -> Asset1)
        bytes memory pathBytesAsset1 = abi.encodePacked(address(tokenMV), uint24(3000), address(assetToken1));

        mvToTokenPaths[0] = DataTypes.InitSwapsData({
            quouter: address(router),
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytesAsset1,
            amountOutMin: 0,
            capital: mvBought / 4,
            routerType: DataTypes.Router.UniswapV2
        });
        mvToTokenPaths[0].path[0] = address(tokenMV);
        mvToTokenPaths[0].path[1] = address(assetToken1);

        // Path for second asset (MV -> Asset2)
        bytes memory pathBytesAsset2 = abi.encodePacked(address(tokenMV), uint24(3000), address(assetToken2));

        mvToTokenPaths[1] = DataTypes.InitSwapsData({
            quouter: address(router),
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytesAsset2,
            amountOutMin: 0,
            capital: mvBought / 4,
            routerType: DataTypes.Router.UniswapV2
        });
        mvToTokenPaths[1].path[0] = address(tokenMV);
        mvToTokenPaths[1].path[1] = address(assetToken2);

        vm.expectEmit(true, false, false, true);
        emit MvToTokensSwapsInitialized(mvToTokenPaths.length, block.timestamp);

        vault.initMvToTokensSwaps(mvToTokenPaths, block.timestamp + 1);

        uint256 balance = assetToken1.balanceOf(address(vault));

        mainVault.setAvailableRouter(address(v3Mock), true);

        v3Mock.setPrice(address(assetToken1), address(tokenMV), 1000 * 10 ** 18);
        v3Mock.setPrice(address(tokenMV), address(tokenMI), 1000 * 10 ** 18);

        uint256 amounOut = vault.exactInputSingle(
            DataTypes.DelegateExactInputSingleParams({
                router: address(v3Mock),
                amountIn: balance / 4,
                amountOutMinimum: 0,
                tokenIn: address(assetToken1),
                tokenOut: address(tokenMV),
                fee: 300,
                sqrtPriceLimitX96: 0,
                deadline: block.timestamp + 1,
                swapType: DataTypes.SwapType.Default
            })
        );

        (uint256 profitMV,,,,,) = vault.profitData();

        uint256 mvBalanceAfter = tokenMV.balanceOf(address(vault));
        console.log("mvBalanceAfter", mvBalanceAfter);
        console.log("profitMV_", profitMV);

        vault.exactInputSingle(
            DataTypes.DelegateExactInputSingleParams({
                router: address(v3Mock),
                amountIn: mvBalanceAfter - profitMV,
                amountOutMinimum: 0,
                tokenIn: address(tokenMV),
                tokenOut: address(tokenMI),
                fee: 300,
                sqrtPriceLimitX96: 0,
                deadline: block.timestamp + 1,
                swapType: DataTypes.SwapType.Default
            })
        );

        vm.expectRevert(InvestmentVault.AssetAlreadyBought.selector);
        vault.initMiToMvSwap(miToMvData, block.timestamp + 1);

        vm.expectRevert(InvestmentVault.AssetAlreadyBought.selector);
        vault.initMvToTokensSwaps(mvToTokenPaths, block.timestamp + 1);

        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(address(assetToken1));

        uint256[] memory shares = new uint256[](1);

        shares[0] = 0 * 10 ** 18;
        vault.setAssetShares(tokens, shares);

        vm.expectRevert(InvestmentVault.InvalidMVToken.selector);
        vault.initMvToTokensSwaps(mvToTokenPaths, block.timestamp + 1);

        vm.stopPrank();
    }

    function testClosePosition_ProfitLessThanFixed() public {
        setUp_SameTokens_FixedProfit();
        (, uint256 earntProfitInvestorBefore, uint256 earntProfitFeeBefore, uint256 earntProfitTotalBefore,,) =
            vault.profitData();
        (,, uint256 initDepositBefore,,,,,,,,) = vault.tokenData();

        vm.startPrank(owner);

        // Move time forward by 365
        vm.warp(block.timestamp + 365 days);

        // Add small profit (less than fixed)
        uint256 profit = initDepositBefore * 10 / 100; // 110% of initDeposit
        tokenMI.mint(address(vault), profit);

        vault.closePosition();

        (bool closed,,,) = vault.vaultState();
        assertTrue(closed, "Position should be closed");

        (, uint256 earntProfitInvestor, uint256 earntProfitFee, uint256 earntProfitTotal,,) = vault.profitData();

        assertEq(earntProfitTotal, earntProfitTotalBefore + profit, "Total profit should match added amount");
        assertEq(
            earntProfitInvestor,
            earntProfitInvestorBefore + profit,
            "All profit should go to investor when below fixed rate"
        );
        assertEq(earntProfitFee, earntProfitFeeBefore, "No fee should be taken when profit is below fixed rate");

        vm.stopPrank();
    }

    function testClosePosition_ProfitMoreThanFixed_HighMustEarntFee() public {
        setUp_SameTokens_FixedProfit();
        (, uint256 earntProfitInvestorBefore, uint256 earntProfitFeeBefore, uint256 earntProfitTotalBefore,,) =
            vault.profitData();
        (,, uint256 initDepositBefore,,,,,,,,) = vault.tokenData();

        vm.startPrank(owner);

        // Move time forward by 365 days
        vm.warp(block.timestamp + 365 days);

        // Add large profit (more than fixed)
        uint256 profit = initDepositBefore * 30 / 100; // 30% of initDeposit
        tokenMI.mint(address(vault), profit);

        vault.closePosition();

        (bool closed,,,) = vault.vaultState();
        assertTrue(closed, "Position should be closed");

        (, uint256 earntProfitInvestor, uint256 earntProfitFee, uint256 earntProfitTotal,,) = vault.profitData();

        // Expected fixed profit for half year = 20% * 0.5 * initDeposit = 10% * initDeposit
        uint256 expectedFixedProfit = INITIAL_BALANCE * 20 / 100;
        uint256 expectedFee = profit - expectedFixedProfit;

        assertEq(earntProfitTotal, earntProfitTotalBefore + profit, "Total profit should match added amount");
        assertEq(
            earntProfitInvestor, earntProfitInvestorBefore + expectedFixedProfit, "Investor should get fixed profit"
        );
        assertEq(earntProfitFee, earntProfitFeeBefore + expectedFee, "Fee should be total minus fixed profit");

        vm.stopPrank();
    }

    function testClosePosition_ProfitMoreThanFixed_LowMustEarntFee() public {
        UniswapV3Mock v3Mock = new UniswapV3Mock();
        setUp_SameTokens_FixedProfit();

        console.log("0--------------------------------");

        tokenMI.mint(address(v3Mock), 1e20);
        assetToken1.mint(address(v3Mock), 1e20);
        bytes memory pathBytesMiMv = abi.encodePacked(address(tokenMI), uint24(3000), address(assetToken1));
        vm.startPrank(owner);
        console.log("1--------------------------------");

        vm.stopPrank();
        vm.startPrank(address(vault));
        tokenMI.approve(address(router), type(uint256).max);
        assetToken1.approve(address(router), type(uint256).max);
        assetToken1.approve(address(v3Mock), type(uint256).max);
        assetToken2.approve(address(router), type(uint256).max);
        assetToken2.approve(address(v3Mock), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(owner);
        vm.warp(block.timestamp + 1 days);
        assetToken1.mint(address(v3Mock), 1e30);
        assetToken1.mint(address(router), 1e30);
        assetToken2.mint(address(router), 1e30);
        tokenMI.mint(address(v3Mock), 1e30);
        tokenMI.mint(address(router), 1e30);
        assetToken2.mint(address(v3Mock), 1e30);
        console.log("2--------------------------------");

        uint256 balanceMi = tokenMI.balanceOf(address(vault));

        DataTypes.InitSwapsData[] memory mvToTokenPaths = new DataTypes.InitSwapsData[](2);

        // Path for first asset (MV -> Asset1)
        bytes memory pathBytesAsset1 = abi.encodePacked(address(tokenMI), uint24(3000), address(assetToken1));

        mvToTokenPaths[0] = DataTypes.InitSwapsData({
            quouter: address(router),
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytesAsset1,
            amountOutMin: 0,
            capital: balanceMi / 4,
            routerType: DataTypes.Router.UniswapV2
        });
        mvToTokenPaths[0].path[0] = address(tokenMI);
        mvToTokenPaths[0].path[1] = address(assetToken1);

        // Path for second asset (MV -> Asset2)
        bytes memory pathBytesAsset2 = abi.encodePacked(address(tokenMI), uint24(3000), address(assetToken2));

        mvToTokenPaths[1] = DataTypes.InitSwapsData({
            quouter: address(router),
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytesAsset2,
            amountOutMin: 0,
            capital: balanceMi / 4,
            routerType: DataTypes.Router.UniswapV2
        });
        mvToTokenPaths[1].path[0] = address(tokenMI);
        mvToTokenPaths[1].path[1] = address(assetToken2);

        vm.expectEmit(true, false, false, true);
        emit MvToTokensSwapsInitialized(mvToTokenPaths.length, block.timestamp);
        console.log("3--------------------------------");

        vault.initMvToTokensSwaps(mvToTokenPaths, block.timestamp + 1);
        console.log("4--------------------------------");

        uint256 balance = assetToken1.balanceOf(address(vault));
        IERC20[] memory tokens1 = new IERC20[](1);
        tokens1[0] = IERC20(address(assetToken1));
        // tokens1[1] = IERC20(address(assetToken2));
        uint256[] memory shares1 = new uint256[](1);
        shares1[0] = 0;
        // shares1[1] = 0;
        mainVault.setAvailableRouter(address(v3Mock), true);

        vault.setAssetShares(tokens1, shares1);

        v3Mock.setPrice(address(assetToken1), address(tokenMI), 1000 * 10 ** 18);
        console.log("5--------------------------------");
        vault.exactInputSingle(
            DataTypes.DelegateExactInputSingleParams({
                router: address(v3Mock),
                amountIn: balance,
                amountOutMinimum: 0,
                tokenIn: address(assetToken1),
                tokenOut: address(tokenMI),
                fee: 300,
                sqrtPriceLimitX96: 0,
                deadline: block.timestamp + 1,
                swapType: DataTypes.SwapType.Default
            })
        );
        console.log("6--------------------------------");
        uint256 balance2 = assetToken2.balanceOf(address(vault));

        v3Mock.setPrice(address(assetToken2), address(tokenMI), 1000 * 10 ** 18);
        console.log("5--------------------------------");
        vault.exactInputSingle(
            DataTypes.DelegateExactInputSingleParams({
                router: address(v3Mock),
                amountIn: balance2,
                amountOutMinimum: 0,
                tokenIn: address(assetToken2),
                tokenOut: address(tokenMI),
                fee: 300,
                sqrtPriceLimitX96: 0,
                deadline: block.timestamp + 1,
                swapType: DataTypes.SwapType.Default
            })
        );
        console.log("6--------------------------------");
        vm.warp(block.timestamp + 365 days);

        uint256 additionalProfit = 1000 * 10 ** 18;
        tokenMI.mint(address(vault), additionalProfit);

        vault.closePosition();

        (, uint256 earntProfitInvestor, uint256 earntProfitFee, uint256 earntProfitTotal,,) = vault.profitData();

        uint256 expectedFixedProfit = INITIAL_BALANCE * 10 / 100;

        vm.stopPrank();
    }

    function testAddProfitMv_MustEarntProfitLessProfit() public {
        UniswapV3Mock v3Mock = new UniswapV3Mock();
        setUp_SameTokens_FixedProfit();

        console.log("0--------------------------------");

        tokenMI.mint(address(v3Mock), 1e20);
        assetToken1.mint(address(v3Mock), 1e20);
        bytes memory pathBytesMiMv = abi.encodePacked(address(tokenMI), uint24(3000), address(assetToken1));
        vm.startPrank(owner);
        console.log("1--------------------------------");

        vm.stopPrank();
        vm.startPrank(address(vault));
        tokenMI.approve(address(router), type(uint256).max);
        assetToken1.approve(address(router), type(uint256).max);
        assetToken1.approve(address(v3Mock), type(uint256).max);
        assetToken2.approve(address(router), type(uint256).max);
        assetToken2.approve(address(v3Mock), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(owner);
        vm.warp(block.timestamp + 1 days);
        assetToken1.mint(address(v3Mock), 1e30);
        assetToken1.mint(address(router), 1e30);
        assetToken2.mint(address(router), 1e30);
        tokenMI.mint(address(v3Mock), 1e30);
        tokenMI.mint(address(router), 1e30);
        assetToken2.mint(address(v3Mock), 1e30);
        console.log("2--------------------------------");

        uint256 balanceMi = tokenMI.balanceOf(address(vault));

        DataTypes.InitSwapsData[] memory mvToTokenPaths = new DataTypes.InitSwapsData[](2);

        // Path for first asset (MV -> Asset1)
        bytes memory pathBytesAsset1 = abi.encodePacked(address(tokenMI), uint24(3000), address(assetToken1));

        mvToTokenPaths[0] = DataTypes.InitSwapsData({
            quouter: address(router),
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytesAsset1,
            amountOutMin: 0,
            capital: balanceMi / 4,
            routerType: DataTypes.Router.UniswapV2
        });
        mvToTokenPaths[0].path[0] = address(tokenMI);
        mvToTokenPaths[0].path[1] = address(assetToken1);

        // Path for second asset (MV -> Asset2)
        bytes memory pathBytesAsset2 = abi.encodePacked(address(tokenMI), uint24(3000), address(assetToken2));

        mvToTokenPaths[1] = DataTypes.InitSwapsData({
            quouter: address(router),
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytesAsset2,
            amountOutMin: 0,
            capital: balanceMi / 4,
            routerType: DataTypes.Router.UniswapV2
        });
        mvToTokenPaths[1].path[0] = address(tokenMI);
        mvToTokenPaths[1].path[1] = address(assetToken2);

        vm.expectEmit(true, false, false, true);
        emit MvToTokensSwapsInitialized(mvToTokenPaths.length, block.timestamp);

        vault.initMvToTokensSwaps(mvToTokenPaths, block.timestamp + 1);

        uint256 balance = assetToken1.balanceOf(address(vault));
        IERC20[] memory tokens1 = new IERC20[](1);
        tokens1[0] = IERC20(address(assetToken1));
        // tokens1[1] = IERC20(address(assetToken2));
        uint256[] memory shares1 = new uint256[](1);
        shares1[0] = 0;
        // shares1[1] = 0;
        mainVault.setAvailableRouter(address(v3Mock), true);

        vault.setAssetShares(tokens1, shares1);

        v3Mock.setPrice(address(assetToken1), address(tokenMI), 1000 * 10 ** 18);
        console.log("5--------------------------------");
        vault.exactInputSingle(
            DataTypes.DelegateExactInputSingleParams({
                router: address(v3Mock),
                amountIn: balance / 3,
                amountOutMinimum: 0,
                tokenIn: address(assetToken1),
                tokenOut: address(tokenMI),
                fee: 300,
                sqrtPriceLimitX96: 0,
                deadline: block.timestamp + 1,
                swapType: DataTypes.SwapType.Default
            })
        );
        v3Mock.setPrice(address(assetToken1), address(tokenMI), 1000 * 10 ** 18);

        vault.exactInputSingle(
            DataTypes.DelegateExactInputSingleParams({
                router: address(v3Mock),
                amountIn: balance / 3,
                amountOutMinimum: 0,
                tokenIn: address(assetToken1),
                tokenOut: address(tokenMI),
                fee: 300,
                sqrtPriceLimitX96: 0,
                deadline: block.timestamp + 1,
                swapType: DataTypes.SwapType.Default
            })
        );
        vm.warp(block.timestamp + 365 days * 180);
        vault.exactInputSingle(
            DataTypes.DelegateExactInputSingleParams({
                router: address(v3Mock),
                amountIn: balance / 3,
                amountOutMinimum: 0,
                tokenIn: address(assetToken1),
                tokenOut: address(tokenMI),
                fee: 300,
                sqrtPriceLimitX96: 0,
                deadline: block.timestamp + 365 days * 1803,
                swapType: DataTypes.SwapType.Default
            })
        );

        vm.stopPrank();
    }

    function testAddProfitMv_ProfitMoreThanFixed_LowMustEarntFee() public {
        UniswapV3Mock v3Mock = new UniswapV3Mock();
        setUp_SameTokens_FixedProfit();

        console.log("0--------------------------------");

        tokenMI.mint(address(v3Mock), 1e20);
        assetToken1.mint(address(v3Mock), 1e20);
        bytes memory pathBytesMiMv = abi.encodePacked(address(tokenMI), uint24(3000), address(assetToken1));
        vm.startPrank(owner);
        console.log("1--------------------------------");

        vm.stopPrank();
        vm.startPrank(address(vault));
        tokenMI.approve(address(router), type(uint256).max);
        assetToken1.approve(address(router), type(uint256).max);
        assetToken1.approve(address(v3Mock), type(uint256).max);
        assetToken2.approve(address(router), type(uint256).max);
        assetToken2.approve(address(v3Mock), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(owner);
        vm.warp(block.timestamp + 1 days);
        assetToken1.mint(address(v3Mock), 1e30);
        assetToken1.mint(address(router), 1e30);
        assetToken2.mint(address(router), 1e30);
        tokenMI.mint(address(v3Mock), 1e30);
        tokenMI.mint(address(router), 1e30);
        assetToken2.mint(address(v3Mock), 1e30);
        console.log("2--------------------------------");

        uint256 balanceMi = tokenMI.balanceOf(address(vault));

        DataTypes.InitSwapsData[] memory mvToTokenPaths = new DataTypes.InitSwapsData[](2);

        // Path for first asset (MV -> Asset1)
        bytes memory pathBytesAsset1 = abi.encodePacked(address(tokenMI), uint24(3000), address(assetToken1));

        mvToTokenPaths[0] = DataTypes.InitSwapsData({
            quouter: address(router),
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytesAsset1,
            amountOutMin: 0,
            capital: balanceMi / 4,
            routerType: DataTypes.Router.UniswapV2
        });
        mvToTokenPaths[0].path[0] = address(tokenMI);
        mvToTokenPaths[0].path[1] = address(assetToken1);

        // Path for second asset (MV -> Asset2)
        bytes memory pathBytesAsset2 = abi.encodePacked(address(tokenMI), uint24(3000), address(assetToken2));

        mvToTokenPaths[1] = DataTypes.InitSwapsData({
            quouter: address(router),
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytesAsset2,
            amountOutMin: 0,
            capital: balanceMi / 4,
            routerType: DataTypes.Router.UniswapV2
        });
        mvToTokenPaths[1].path[0] = address(tokenMI);
        mvToTokenPaths[1].path[1] = address(assetToken2);

        vm.expectEmit(true, false, false, true);
        emit MvToTokensSwapsInitialized(mvToTokenPaths.length, block.timestamp);
        console.log("3--------------------------------");

        vault.initMvToTokensSwaps(mvToTokenPaths, block.timestamp + 1);
        console.log("4--------------------------------");

        uint256 balance = assetToken1.balanceOf(address(vault));
        IERC20[] memory tokens1 = new IERC20[](1);
        tokens1[0] = IERC20(address(assetToken1));
        // tokens1[1] = IERC20(address(assetToken2));
        uint256[] memory shares1 = new uint256[](1);
        shares1[0] = 0;
        // shares1[1] = 0;
        mainVault.setAvailableRouter(address(v3Mock), true);

        vault.setAssetShares(tokens1, shares1);

        v3Mock.setPrice(address(assetToken1), address(tokenMI), 1000 * 10 ** 18);
        console.log("5--------------------------------");
        vault.exactInputSingle(
            DataTypes.DelegateExactInputSingleParams({
                router: address(v3Mock),
                amountIn: balance / 2,
                amountOutMinimum: 0,
                tokenIn: address(assetToken1),
                tokenOut: address(tokenMI),
                fee: 300,
                sqrtPriceLimitX96: 0,
                deadline: block.timestamp + 1,
                swapType: DataTypes.SwapType.Default
            })
        );

        vm.warp(block.timestamp + 1e12);
        console.log("6--------------------------------");
        vault.exactInputSingle(
            DataTypes.DelegateExactInputSingleParams({
                router: address(v3Mock),
                amountIn: balance / 2 / 2,
                amountOutMinimum: 0,
                tokenIn: address(assetToken1),
                tokenOut: address(tokenMI),
                fee: 300,
                sqrtPriceLimitX96: 0,
                deadline: block.timestamp + 1e13,
                swapType: DataTypes.SwapType.Default
            })
        );
        vm.stopPrank();
    }

    function testMV_MI_profit_FixedProfit() public {
        UniswapV3Mock v3Mock = new UniswapV3Mock();
        setUp_DifferentTokens_FixedProfit();

        console.log("0--------------------------------");

        tokenMI.mint(address(v3Mock), 1e20);
        assetToken1.mint(address(v3Mock), 1e20);
        bytes memory pathBytesMiMv = abi.encodePacked(address(tokenMI), uint24(3000), address(assetToken1));
        vm.startPrank(owner);
        console.log("1--------------------------------");

        vm.stopPrank();
        vm.startPrank(address(vault));
        tokenMI.approve(address(router), type(uint256).max);
        tokenMV.approve(address(router), type(uint256).max);
        tokenMV.approve(address(v3Mock), type(uint256).max);
        assetToken1.approve(address(router), type(uint256).max);
        assetToken1.approve(address(v3Mock), type(uint256).max);
        assetToken2.approve(address(router), type(uint256).max);
        assetToken2.approve(address(v3Mock), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(owner);
        vm.warp(block.timestamp + 1 days);
        assetToken1.mint(address(v3Mock), 1e30);
        assetToken1.mint(address(router), 1e30);
        assetToken2.mint(address(router), 1e30);
        tokenMI.mint(address(v3Mock), 1e30);
        tokenMI.mint(address(router), 1e30);
        tokenMV.mint(address(v3Mock), 1e30);
        tokenMV.mint(address(router), 1e30);
        assetToken2.mint(address(v3Mock), 1e30);
        console.log("2--------------------------------");

        {
            bytes memory pathBytes = abi.encodePacked(address(tokenMI), uint24(3000), address(tokenMV));

            DataTypes.InitSwapsData memory data = DataTypes.InitSwapsData({
                quouter: address(router),
                router: address(router),
                path: new address[](2),
                pathBytes: pathBytes,
                amountOutMin: 0,
                capital: INITIAL_BALANCE,
                routerType: DataTypes.Router.UniswapV2
            });
            data.path[0] = address(tokenMI);
            data.path[1] = address(tokenMV);

            uint256 amountIn = (INITIAL_BALANCE * 7 * 10 ** 17) / Constants.SHARE_DENOMINATOR;
            uint256 amountOut = amountIn / 2; // From MockRouter implementation

            vm.expectEmit(true, false, false, true);
            emit MiToMvSwapInitialized(address(router), amountIn, amountOut, block.timestamp);

            vault.initMiToMvSwap(data, block.timestamp + 1);
        }

        console.log("2--------------------------------");

        uint256 balanceMi = tokenMI.balanceOf(address(vault));
        uint256 balanceMV = tokenMV.balanceOf(address(vault));

        DataTypes.InitSwapsData[] memory mvToTokenPaths = new DataTypes.InitSwapsData[](2);

        // Path for first asset (MV -> Asset1)
        bytes memory pathBytesAsset1 = abi.encodePacked(address(tokenMV), uint24(3000), address(assetToken1));

        mvToTokenPaths[0] = DataTypes.InitSwapsData({
            quouter: address(router),
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytesAsset1,
            amountOutMin: 0,
            capital: balanceMi / 4,
            routerType: DataTypes.Router.UniswapV2
        });
        mvToTokenPaths[0].path[0] = address(tokenMV);
        mvToTokenPaths[0].path[1] = address(assetToken1);

        // Path for second asset (MV -> Asset2)
        bytes memory pathBytesAsset2 = abi.encodePacked(address(assetToken2), uint24(3000), address(assetToken2));

        mvToTokenPaths[1] = DataTypes.InitSwapsData({
            quouter: address(router),
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytesAsset2,
            amountOutMin: 0,
            capital: balanceMi / 4,
            routerType: DataTypes.Router.UniswapV2
        });
        mvToTokenPaths[1].path[0] = address(tokenMV);
        mvToTokenPaths[1].path[1] = address(assetToken2);

        vm.expectEmit(true, false, false, true);
        emit MvToTokensSwapsInitialized(mvToTokenPaths.length, block.timestamp);
        console.log("3--------------------------------");

        vault.initMvToTokensSwaps(mvToTokenPaths, block.timestamp + 1);
        console.log("4--------------------------------");
        uint256 balance = assetToken1.balanceOf(address(vault));
        {
            IERC20[] memory tokens1 = new IERC20[](1);
            tokens1[0] = IERC20(address(assetToken1));
            // tokens1[1] = IERC20(address(assetToken2));
            uint256[] memory shares1 = new uint256[](1);
            shares1[0] = 0;
            // shares1[1] = 0;
            mainVault.setAvailableRouter(address(v3Mock), true);

            vault.setAssetShares(tokens1, shares1);
        }
        v3Mock.setPrice(address(assetToken1), address(tokenMV), 1000 * 10 ** 18);
        v3Mock.setPrice(address(tokenMV), address(tokenMI), 1000 * 10 ** 18);
        console.log("5--------------------------------");
        vault.exactInputSingle(
            DataTypes.DelegateExactInputSingleParams({
                router: address(v3Mock),
                amountIn: balance / 2,
                amountOutMinimum: 0,
                tokenIn: address(assetToken1),
                tokenOut: address(tokenMV),
                fee: 300,
                sqrtPriceLimitX96: 0,
                deadline: block.timestamp + 1e12,
                swapType: DataTypes.SwapType.Default
            })
        );

        vm.warp(block.timestamp + 1e12);
        console.log("6--------------------------------");
        vault.exactInputSingle(
            DataTypes.DelegateExactInputSingleParams({
                router: address(v3Mock),
                amountIn: balance / 2 / 2,
                amountOutMinimum: 0,
                tokenIn: address(assetToken1),
                tokenOut: address(tokenMV),
                fee: 300,
                sqrtPriceLimitX96: 0,
                deadline: block.timestamp + 1e12,
                swapType: DataTypes.SwapType.Default
            })
        );
        (uint256 profitMV1,,,,,) = vault.profitData();

        vault.exactInputSingle(
            DataTypes.DelegateExactInputSingleParams({
                router: address(v3Mock),
                amountIn: profitMV1,
                amountOutMinimum: 0,
                tokenIn: address(tokenMV),
                tokenOut: address(tokenMI),
                fee: 300,
                sqrtPriceLimitX96: 0,
                deadline: block.timestamp + 1e12,
                swapType: DataTypes.SwapType.ProfitMvToProfitMi
            })
        );
        vm.stopPrank();
    }

    function testMV_MI_profit_FixedProfit_Low_ThenMust() public {
        UniswapV3Mock v3Mock = new UniswapV3Mock();
        setUp_DifferentTokens_FixedProfit();

        console.log("0--------------------------------");

        tokenMI.mint(address(v3Mock), 1e20);
        assetToken1.mint(address(v3Mock), 1e20);
        bytes memory pathBytesMiMv = abi.encodePacked(address(tokenMI), uint24(3000), address(assetToken1));
        vm.startPrank(owner);
        console.log("1--------------------------------");

        vm.stopPrank();
        vm.startPrank(address(vault));
        tokenMI.approve(address(router), type(uint256).max);
        tokenMV.approve(address(router), type(uint256).max);
        tokenMV.approve(address(v3Mock), type(uint256).max);
        assetToken1.approve(address(router), type(uint256).max);
        assetToken1.approve(address(v3Mock), type(uint256).max);
        assetToken2.approve(address(router), type(uint256).max);
        assetToken2.approve(address(v3Mock), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(owner);
        vm.warp(block.timestamp + 1 days);
        assetToken1.mint(address(v3Mock), 1e30);
        assetToken1.mint(address(router), 1e30);
        assetToken2.mint(address(router), 1e30);
        tokenMI.mint(address(v3Mock), 1e30);
        tokenMI.mint(address(router), 1e30);
        tokenMV.mint(address(v3Mock), 1e30);
        tokenMV.mint(address(router), 1e30);
        assetToken2.mint(address(v3Mock), 1e30);
        console.log("2--------------------------------");

        {
            bytes memory pathBytes = abi.encodePacked(address(tokenMI), uint24(3000), address(tokenMV));

            DataTypes.InitSwapsData memory data = DataTypes.InitSwapsData({
                quouter: address(router),
                router: address(router),
                path: new address[](2),
                pathBytes: pathBytes,
                amountOutMin: 0,
                capital: INITIAL_BALANCE,
                routerType: DataTypes.Router.UniswapV2
            });
            data.path[0] = address(tokenMI);
            data.path[1] = address(tokenMV);

            uint256 amountIn = (INITIAL_BALANCE * 7 * 10 ** 17) / Constants.SHARE_DENOMINATOR;
            uint256 amountOut = amountIn / 2; // From MockRouter implementation

            vm.expectEmit(true, false, false, true);
            emit MiToMvSwapInitialized(address(router), amountIn, amountOut, block.timestamp);

            vault.initMiToMvSwap(data, block.timestamp + 1);
        }

        console.log("2--------------------------------");

        uint256 balanceMi = tokenMI.balanceOf(address(vault));
        uint256 balanceMV = tokenMV.balanceOf(address(vault));

        DataTypes.InitSwapsData[] memory mvToTokenPaths = new DataTypes.InitSwapsData[](2);

        // Path for first asset (MV -> Asset1)
        bytes memory pathBytesAsset1 = abi.encodePacked(address(tokenMV), uint24(3000), address(assetToken1));

        mvToTokenPaths[0] = DataTypes.InitSwapsData({
            quouter: address(router),
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytesAsset1,
            amountOutMin: 0,
            capital: balanceMi / 4,
            routerType: DataTypes.Router.UniswapV2
        });
        mvToTokenPaths[0].path[0] = address(tokenMV);
        mvToTokenPaths[0].path[1] = address(assetToken1);

        // Path for second asset (MV -> Asset2)
        bytes memory pathBytesAsset2 = abi.encodePacked(address(assetToken2), uint24(3000), address(assetToken2));

        mvToTokenPaths[1] = DataTypes.InitSwapsData({
            quouter: address(router),
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytesAsset2,
            amountOutMin: 0,
            capital: balanceMi / 4,
            routerType: DataTypes.Router.UniswapV2
        });
        mvToTokenPaths[1].path[0] = address(tokenMV);
        mvToTokenPaths[1].path[1] = address(assetToken2);

        vm.expectEmit(true, false, false, true);
        emit MvToTokensSwapsInitialized(mvToTokenPaths.length, block.timestamp);
        console.log("3--------------------------------");

        vault.initMvToTokensSwaps(mvToTokenPaths, block.timestamp + 1);
        console.log("4--------------------------------");
        uint256 balance = assetToken1.balanceOf(address(vault));
        {
            IERC20[] memory tokens1 = new IERC20[](1);
            tokens1[0] = IERC20(address(assetToken1));
            // tokens1[1] = IERC20(address(assetToken2));
            uint256[] memory shares1 = new uint256[](1);
            shares1[0] = 0;
            // shares1[1] = 0;
            mainVault.setAvailableRouter(address(v3Mock), true);

            vault.setAssetShares(tokens1, shares1);
        }
        v3Mock.setPrice(address(assetToken1), address(tokenMV), 1000 * 10 ** 18);
        v3Mock.setPrice(address(tokenMV), address(tokenMI), 1000 * 10 ** 18);
        console.log("5--------------------------------");
        vault.exactInputSingle(
            DataTypes.DelegateExactInputSingleParams({
                router: address(v3Mock),
                amountIn: balance / 2,
                amountOutMinimum: 0,
                tokenIn: address(assetToken1),
                tokenOut: address(tokenMV),
                fee: 300,
                sqrtPriceLimitX96: 0,
                deadline: block.timestamp + 1e12,
                swapType: DataTypes.SwapType.Default
            })
        );

        vm.warp(block.timestamp + 1e12);
        console.log("6--------------------------------");
        vault.exactInputSingle(
            DataTypes.DelegateExactInputSingleParams({
                router: address(v3Mock),
                amountIn: balance / 2 / 2,
                amountOutMinimum: 0,
                tokenIn: address(assetToken1),
                tokenOut: address(tokenMV),
                fee: 300,
                sqrtPriceLimitX96: 0,
                deadline: block.timestamp + 1e12,
                swapType: DataTypes.SwapType.Default
            })
        );
        (uint256 profitMV1,,,,,) = vault.profitData();
        vm.warp(block.timestamp + 1e14);

        vault.exactInputSingle(
            DataTypes.DelegateExactInputSingleParams({
                router: address(v3Mock),
                amountIn: profitMV1 / 1000,
                amountOutMinimum: 0,
                tokenIn: address(tokenMV),
                tokenOut: address(tokenMI),
                fee: 300,
                sqrtPriceLimitX96: 0,
                deadline: block.timestamp + 1e44,
                swapType: DataTypes.SwapType.ProfitMvToProfitMi
            })
        );
        vm.stopPrank();
    }

    function testMV_MI_profit_FixedProfit_MoreThenMust_Aftre_Low_ThenMust() public {
        UniswapV3Mock v3Mock = new UniswapV3Mock();
        setUp_DifferentTokens_FixedProfit();

        console.log("0--------------------------------");

        tokenMI.mint(address(v3Mock), 1e20);
        assetToken1.mint(address(v3Mock), 1e20);
        bytes memory pathBytesMiMv = abi.encodePacked(address(tokenMI), uint24(3000), address(assetToken1));
        vm.startPrank(owner);
        console.log("1--------------------------------");

        vm.stopPrank();
        vm.startPrank(address(vault));
        tokenMI.approve(address(router), type(uint256).max);
        tokenMV.approve(address(router), type(uint256).max);
        tokenMV.approve(address(v3Mock), type(uint256).max);
        assetToken1.approve(address(router), type(uint256).max);
        assetToken1.approve(address(v3Mock), type(uint256).max);
        assetToken2.approve(address(router), type(uint256).max);
        assetToken2.approve(address(v3Mock), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(owner);
        vm.warp(block.timestamp + 1 days);
        assetToken1.mint(address(v3Mock), 1e30);
        assetToken1.mint(address(router), 1e30);
        assetToken2.mint(address(router), 1e30);
        tokenMI.mint(address(v3Mock), 1e30);
        tokenMI.mint(address(router), 1e30);
        tokenMV.mint(address(v3Mock), 1e30);
        tokenMV.mint(address(router), 1e30);
        assetToken2.mint(address(v3Mock), 1e30);
        console.log("2--------------------------------");

        {
            bytes memory pathBytes = abi.encodePacked(address(tokenMI), uint24(3000), address(tokenMV));

            DataTypes.InitSwapsData memory data = DataTypes.InitSwapsData({
                quouter: address(router),
                router: address(router),
                path: new address[](2),
                pathBytes: pathBytes,
                amountOutMin: 0,
                capital: INITIAL_BALANCE,
                routerType: DataTypes.Router.UniswapV2
            });
            data.path[0] = address(tokenMI);
            data.path[1] = address(tokenMV);

            uint256 amountIn = (INITIAL_BALANCE * 7 * 10 ** 17) / Constants.SHARE_DENOMINATOR;
            uint256 amountOut = amountIn / 2; // From MockRouter implementation

            vm.expectEmit(true, false, false, true);
            emit MiToMvSwapInitialized(address(router), amountIn, amountOut, block.timestamp);

            vault.initMiToMvSwap(data, block.timestamp + 1);
        }

        console.log("2--------------------------------");

        uint256 balanceMi = tokenMI.balanceOf(address(vault));
        uint256 balanceMV = tokenMV.balanceOf(address(vault));

        DataTypes.InitSwapsData[] memory mvToTokenPaths = new DataTypes.InitSwapsData[](2);

        // Path for first asset (MV -> Asset1)
        bytes memory pathBytesAsset1 = abi.encodePacked(address(tokenMV), uint24(3000), address(assetToken1));

        mvToTokenPaths[0] = DataTypes.InitSwapsData({
            quouter: address(router),
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytesAsset1,
            amountOutMin: 0,
            capital: balanceMi / 4,
            routerType: DataTypes.Router.UniswapV2
        });
        mvToTokenPaths[0].path[0] = address(tokenMV);
        mvToTokenPaths[0].path[1] = address(assetToken1);

        // Path for second asset (MV -> Asset2)
        bytes memory pathBytesAsset2 = abi.encodePacked(address(assetToken2), uint24(3000), address(assetToken2));

        mvToTokenPaths[1] = DataTypes.InitSwapsData({
            quouter: address(router),
            router: address(router),
            path: new address[](2),
            pathBytes: pathBytesAsset2,
            amountOutMin: 0,
            capital: balanceMi / 4,
            routerType: DataTypes.Router.UniswapV2
        });
        mvToTokenPaths[1].path[0] = address(tokenMV);
        mvToTokenPaths[1].path[1] = address(assetToken2);

        vm.expectEmit(true, false, false, true);
        emit MvToTokensSwapsInitialized(mvToTokenPaths.length, block.timestamp);
        console.log("3--------------------------------");

        vault.initMvToTokensSwaps(mvToTokenPaths, block.timestamp + 1);
        console.log("4--------------------------------");
        uint256 balance = assetToken1.balanceOf(address(vault));
        {
            IERC20[] memory tokens1 = new IERC20[](1);
            tokens1[0] = IERC20(address(assetToken1));
            // tokens1[1] = IERC20(address(assetToken2));
            uint256[] memory shares1 = new uint256[](1);
            shares1[0] = 0;
            // shares1[1] = 0;
            mainVault.setAvailableRouter(address(v3Mock), true);

            vault.setAssetShares(tokens1, shares1);
        }
        v3Mock.setPrice(address(assetToken1), address(tokenMV), 1000 * 10 ** 18);
        v3Mock.setPrice(address(tokenMV), address(tokenMI), 1000 * 10 ** 18);
        console.log("5--------------------------------");
        vault.exactInputSingle(
            DataTypes.DelegateExactInputSingleParams({
                router: address(v3Mock),
                amountIn: balance / 2,
                amountOutMinimum: 0,
                tokenIn: address(assetToken1),
                tokenOut: address(tokenMV),
                fee: 300,
                sqrtPriceLimitX96: 0,
                deadline: block.timestamp + 1e12,
                swapType: DataTypes.SwapType.Default
            })
        );

        console.log("6--------------------------------");
        vault.exactInputSingle(
            DataTypes.DelegateExactInputSingleParams({
                router: address(v3Mock),
                amountIn: balance / 2 / 2,
                amountOutMinimum: 0,
                tokenIn: address(assetToken1),
                tokenOut: address(tokenMV),
                fee: 300,
                sqrtPriceLimitX96: 0,
                deadline: block.timestamp + 1e12,
                swapType: DataTypes.SwapType.Default
            })
        );
        (uint256 profitMV1,,,,,) = vault.profitData();

        vault.exactInputSingle(
            DataTypes.DelegateExactInputSingleParams({
                router: address(v3Mock),
                amountIn: profitMV1 / 1000,
                amountOutMinimum: 0,
                tokenIn: address(tokenMV),
                tokenOut: address(tokenMI),
                fee: 300,
                sqrtPriceLimitX96: 0,
                deadline: block.timestamp + 1e44,
                swapType: DataTypes.SwapType.ProfitMvToProfitMi
            })
        );
        vm.warp(block.timestamp + 234 days * 123);
        vault.exactInputSingle(
            DataTypes.DelegateExactInputSingleParams({
                router: address(v3Mock),
                amountIn: profitMV1 / 1000,
                amountOutMinimum: 0,
                tokenIn: address(tokenMV),
                tokenOut: address(tokenMI),
                fee: 300,
                sqrtPriceLimitX96: 0,
                deadline: block.timestamp + 1e44,
                swapType: DataTypes.SwapType.ProfitMvToProfitMi
            })
        );
        vm.stopPrank();
    }

    function testInitialization_InvalidStepTooHigh() public {
        vm.startPrank(owner);

        tokenMI = new MockToken("MI Token", "MI", 18);
        tokenMV = new MockToken("MV Token", "MV", 18);
        assetToken1 = new MockToken("Asset Token 1", "AT1", 18);
        assetToken2 = new MockToken("Asset Token 2", "AT2", 6);
        router = new MockRouter();

        mainVault = new MockMainVault();
        mainVault.setAvailableRouter(address(router), true);
        mainVault.setAvailableToken(address(tokenMI), true);
        mainVault.setAvailableToken(address(tokenMV), true);
        mainVault.setAvailableToken(address(assetToken1), true);
        mainVault.setAvailableToken(address(assetToken2), true);

        implementation = new InvestmentVault();
        mainVault.setCurrentImplementation(address(implementation));

        DataTypes.AssetInitData[] memory assets = new DataTypes.AssetInitData[](2);

        assets[0] = DataTypes.AssetInitData({
            token: IERC20(address(assetToken1)),
            shareMV: 5 * 10 ** 17,
            step: 5 * 10 ** 16,
            strategy: DataTypes.Strategy.Zero
        });

        assets[1] = DataTypes.AssetInitData({
            token: IERC20(address(assetToken2)),
            shareMV: 5 * 10 ** 17,
            step: 5 * 10 ** 16,
            strategy: DataTypes.Strategy.First
        });

        DataTypes.InvestmentVaultInitData memory initData = DataTypes.InvestmentVaultInitData({
            mainVault: IMainVault(address(mainVault)),
            tokenMI: IERC20(address(tokenMI)),
            tokenMV: IERC20(address(tokenMV)),
            initDeposit: INITIAL_BALANCE,
            shareMI: 7 * 10 ** 17,
            step: Constants.MAX_STEP + 1,
            assets: assets
        });

        bytes memory encodedInitData = abi.encodeWithSelector(InvestmentVault.initialize.selector, initData);

        vm.expectRevert(InvestmentVault.InvalidStep.selector);
        proxy = new ERC1967Proxy(address(implementation), encodedInitData);

        vm.stopPrank();
    }

    function testInitialization_InvalidStepTooLow() public {
        vm.startPrank(owner);

        tokenMI = new MockToken("MI Token", "MI", 18);
        tokenMV = new MockToken("MV Token", "MV", 18);
        assetToken1 = new MockToken("Asset Token 1", "AT1", 18);
        assetToken2 = new MockToken("Asset Token 2", "AT2", 6);
        router = new MockRouter();

        mainVault = new MockMainVault();
        mainVault.setAvailableRouter(address(router), true);
        mainVault.setAvailableToken(address(tokenMI), true);
        mainVault.setAvailableToken(address(tokenMV), true);
        mainVault.setAvailableToken(address(assetToken1), true);
        mainVault.setAvailableToken(address(assetToken2), true);

        implementation = new InvestmentVault();
        mainVault.setCurrentImplementation(address(implementation));

        DataTypes.AssetInitData[] memory assets = new DataTypes.AssetInitData[](2);

        assets[0] = DataTypes.AssetInitData({
            token: IERC20(address(assetToken1)),
            shareMV: 5 * 10 ** 17,
            step: 5 * 10 ** 16,
            strategy: DataTypes.Strategy.Zero
        });

        assets[1] = DataTypes.AssetInitData({
            token: IERC20(address(assetToken2)),
            shareMV: 5 * 10 ** 17,
            step: 5 * 10 ** 16,
            strategy: DataTypes.Strategy.First
        });

        DataTypes.InvestmentVaultInitData memory initData = DataTypes.InvestmentVaultInitData({
            mainVault: IMainVault(address(mainVault)),
            tokenMI: IERC20(address(tokenMI)),
            tokenMV: IERC20(address(tokenMV)),
            initDeposit: INITIAL_BALANCE,
            shareMI: 7 * 10 ** 17,
            step: Constants.MIN_STEP - 1,
            assets: assets
        });

        bytes memory encodedInitData = abi.encodeWithSelector(InvestmentVault.initialize.selector, initData);

        vm.expectRevert(InvestmentVault.InvalidStep.selector);
        proxy = new ERC1967Proxy(address(implementation), encodedInitData);

        vm.stopPrank();
    }

    function testInitialization_InvalidShareMITooHigh() public {
        vm.startPrank(owner);

        tokenMI = new MockToken("MI Token", "MI", 18);
        tokenMV = new MockToken("MV Token", "MV", 18);
        assetToken1 = new MockToken("Asset Token 1", "AT1", 18);
        assetToken2 = new MockToken("Asset Token 2", "AT2", 6);
        router = new MockRouter();

        mainVault = new MockMainVault();
        mainVault.setAvailableRouter(address(router), true);
        mainVault.setAvailableToken(address(tokenMI), true);
        mainVault.setAvailableToken(address(tokenMV), true);
        mainVault.setAvailableToken(address(assetToken1), true);
        mainVault.setAvailableToken(address(assetToken2), true);

        implementation = new InvestmentVault();
        mainVault.setCurrentImplementation(address(implementation));

        DataTypes.AssetInitData[] memory assets = new DataTypes.AssetInitData[](2);

        assets[0] = DataTypes.AssetInitData({
            token: IERC20(address(assetToken1)),
            shareMV: 5 * 10 ** 17,
            step: 5 * 10 ** 16,
            strategy: DataTypes.Strategy.Zero
        });

        assets[1] = DataTypes.AssetInitData({
            token: IERC20(address(assetToken2)),
            shareMV: 5 * 10 ** 17,
            step: 5 * 10 ** 16,
            strategy: DataTypes.Strategy.First
        });

        DataTypes.InvestmentVaultInitData memory initData = DataTypes.InvestmentVaultInitData({
            mainVault: IMainVault(address(mainVault)),
            tokenMI: IERC20(address(tokenMI)),
            tokenMV: IERC20(address(tokenMV)),
            initDeposit: INITIAL_BALANCE,
            shareMI: Constants.SHARE_INITIAL_MAX + 1,
            step: 5 * 10 ** 16,
            assets: assets
        });

        bytes memory encodedInitData = abi.encodeWithSelector(InvestmentVault.initialize.selector, initData);

        vm.expectRevert(InvestmentVault.ShareExceedsMaximum.selector);
        proxy = new ERC1967Proxy(address(implementation), encodedInitData);

        vm.stopPrank();
    }

    function testInitialization_ValidShareMIDenominator() public {
        vm.startPrank(owner);

        tokenMI = new MockToken("MI Token", "MI", 18);
        tokenMV = new MockToken("MV Token", "MV", 18);
        assetToken1 = new MockToken("Asset Token 1", "AT1", 18);
        assetToken2 = new MockToken("Asset Token 2", "AT2", 6);
        router = new MockRouter();

        mainVault = new MockMainVault();
        mainVault.setAvailableRouter(address(router), true);
        mainVault.setAvailableToken(address(tokenMI), true);
        mainVault.setAvailableToken(address(tokenMV), true);
        mainVault.setAvailableToken(address(assetToken1), true);
        mainVault.setAvailableToken(address(assetToken2), true);

        implementation = new InvestmentVault();
        mainVault.setCurrentImplementation(address(implementation));

        DataTypes.AssetInitData[] memory assets = new DataTypes.AssetInitData[](2);

        assets[0] = DataTypes.AssetInitData({
            token: IERC20(address(assetToken1)),
            shareMV: 5 * 10 ** 17,
            step: 5 * 10 ** 16,
            strategy: DataTypes.Strategy.Zero
        });

        assets[1] = DataTypes.AssetInitData({
            token: IERC20(address(assetToken2)),
            shareMV: 5 * 10 ** 17,
            step: 5 * 10 ** 16,
            strategy: DataTypes.Strategy.First
        });

        DataTypes.InvestmentVaultInitData memory initData = DataTypes.InvestmentVaultInitData({
            mainVault: IMainVault(address(mainVault)),
            tokenMI: IERC20(address(tokenMI)),
            tokenMV: IERC20(address(tokenMV)),
            initDeposit: INITIAL_BALANCE,
            shareMI: Constants.SHARE_DENOMINATOR,
            step: 5 * 10 ** 16,
            assets: assets
        });

        bytes memory encodedInitData = abi.encodeWithSelector(InvestmentVault.initialize.selector, initData);

        proxy = new ERC1967Proxy(address(implementation), encodedInitData);
        vault = InvestmentVault(address(proxy));

        (IERC20 tMI,,,,,,,,,,) = vault.tokenData();
        assertEq(address(tMI), address(tokenMI), "Initialization should succeed with SHARE_DENOMINATOR");

        vm.stopPrank();
    }

    function testInitialization_AssetInvalidStepTooHigh() public {
        vm.startPrank(owner);

        tokenMI = new MockToken("MI Token", "MI", 18);
        tokenMV = new MockToken("MV Token", "MV", 18);
        assetToken1 = new MockToken("Asset Token 1", "AT1", 18);
        assetToken2 = new MockToken("Asset Token 2", "AT2", 6);
        router = new MockRouter();

        mainVault = new MockMainVault();
        mainVault.setAvailableRouter(address(router), true);
        mainVault.setAvailableToken(address(tokenMI), true);
        mainVault.setAvailableToken(address(tokenMV), true);
        mainVault.setAvailableToken(address(assetToken1), true);
        mainVault.setAvailableToken(address(assetToken2), true);

        implementation = new InvestmentVault();
        mainVault.setCurrentImplementation(address(implementation));

        DataTypes.AssetInitData[] memory assets = new DataTypes.AssetInitData[](2);

        assets[0] = DataTypes.AssetInitData({
            token: IERC20(address(assetToken1)),
            shareMV: 5 * 10 ** 17,
            step: Constants.MAX_STEP + 1,
            strategy: DataTypes.Strategy.Zero
        });

        assets[1] = DataTypes.AssetInitData({
            token: IERC20(address(assetToken2)),
            shareMV: 5 * 10 ** 17,
            step: 5 * 10 ** 16,
            strategy: DataTypes.Strategy.First
        });

        DataTypes.InvestmentVaultInitData memory initData = DataTypes.InvestmentVaultInitData({
            mainVault: IMainVault(address(mainVault)),
            tokenMI: IERC20(address(tokenMI)),
            tokenMV: IERC20(address(tokenMV)),
            initDeposit: INITIAL_BALANCE,
            shareMI: 7 * 10 ** 17,
            step: 5 * 10 ** 16,
            assets: assets
        });

        bytes memory encodedInitData = abi.encodeWithSelector(InvestmentVault.initialize.selector, initData);

        vm.expectRevert(InvestmentVault.InvalidStep.selector);
        proxy = new ERC1967Proxy(address(implementation), encodedInitData);

        vm.stopPrank();
    }

    function testInitialization_AssetInvalidStepTooLow() public {
        vm.startPrank(owner);

        tokenMI = new MockToken("MI Token", "MI", 18);
        tokenMV = new MockToken("MV Token", "MV", 18);
        assetToken1 = new MockToken("Asset Token 1", "AT1", 18);
        assetToken2 = new MockToken("Asset Token 2", "AT2", 6);
        router = new MockRouter();

        mainVault = new MockMainVault();
        mainVault.setAvailableRouter(address(router), true);
        mainVault.setAvailableToken(address(tokenMI), true);
        mainVault.setAvailableToken(address(tokenMV), true);
        mainVault.setAvailableToken(address(assetToken1), true);
        mainVault.setAvailableToken(address(assetToken2), true);

        implementation = new InvestmentVault();
        mainVault.setCurrentImplementation(address(implementation));

        DataTypes.AssetInitData[] memory assets = new DataTypes.AssetInitData[](2);

        assets[0] = DataTypes.AssetInitData({
            token: IERC20(address(assetToken1)),
            shareMV: 5 * 10 ** 17,
            step: Constants.MIN_STEP - 1,
            strategy: DataTypes.Strategy.Zero
        });

        assets[1] = DataTypes.AssetInitData({
            token: IERC20(address(assetToken2)),
            shareMV: 5 * 10 ** 17,
            step: 5 * 10 ** 16,
            strategy: DataTypes.Strategy.First
        });

        DataTypes.InvestmentVaultInitData memory initData = DataTypes.InvestmentVaultInitData({
            mainVault: IMainVault(address(mainVault)),
            tokenMI: IERC20(address(tokenMI)),
            tokenMV: IERC20(address(tokenMV)),
            initDeposit: INITIAL_BALANCE,
            shareMI: 7 * 10 ** 17,
            step: 5 * 10 ** 16,
            assets: assets
        });

        bytes memory encodedInitData = abi.encodeWithSelector(InvestmentVault.initialize.selector, initData);

        vm.expectRevert(InvestmentVault.InvalidStep.selector);
        proxy = new ERC1967Proxy(address(implementation), encodedInitData);

        vm.stopPrank();
    }

    function testInitialization_AssetShareMVTooHigh() public {
        vm.startPrank(owner);

        tokenMI = new MockToken("MI Token", "MI", 18);
        tokenMV = new MockToken("MV Token", "MV", 18);
        assetToken1 = new MockToken("Asset Token 1", "AT1", 18);
        assetToken2 = new MockToken("Asset Token 2", "AT2", 6);
        router = new MockRouter();

        mainVault = new MockMainVault();
        mainVault.setAvailableRouter(address(router), true);
        mainVault.setAvailableToken(address(tokenMI), true);
        mainVault.setAvailableToken(address(tokenMV), true);
        mainVault.setAvailableToken(address(assetToken1), true);
        mainVault.setAvailableToken(address(assetToken2), true);

        implementation = new InvestmentVault();
        mainVault.setCurrentImplementation(address(implementation));

        DataTypes.AssetInitData[] memory assets = new DataTypes.AssetInitData[](2);

        assets[0] = DataTypes.AssetInitData({
            token: IERC20(address(assetToken1)),
            shareMV: Constants.SHARE_INITIAL_MAX + 1,
            step: 5 * 10 ** 16,
            strategy: DataTypes.Strategy.Zero
        });

        assets[1] = DataTypes.AssetInitData({
            token: IERC20(address(assetToken2)),
            shareMV: 5 * 10 ** 17,
            step: 5 * 10 ** 16,
            strategy: DataTypes.Strategy.First
        });

        DataTypes.InvestmentVaultInitData memory initData = DataTypes.InvestmentVaultInitData({
            mainVault: IMainVault(address(mainVault)),
            tokenMI: IERC20(address(tokenMI)),
            tokenMV: IERC20(address(tokenMV)),
            initDeposit: INITIAL_BALANCE,
            shareMI: 7 * 10 ** 17,
            step: 5 * 10 ** 16,
            assets: assets
        });

        bytes memory encodedInitData = abi.encodeWithSelector(InvestmentVault.initialize.selector, initData);

        vm.expectRevert(InvestmentVault.ShareExceedsMaximum.selector);
        proxy = new ERC1967Proxy(address(implementation), encodedInitData);

        vm.stopPrank();
    }

    function testInitialization_AssetInvalidTokenMI() public {
        vm.startPrank(owner);

        tokenMI = new MockToken("MI Token", "MI", 18);
        tokenMV = new MockToken("MV Token", "MV", 18);
        assetToken1 = new MockToken("Asset Token 1", "AT1", 18);
        assetToken2 = new MockToken("Asset Token 2", "AT2", 6);
        router = new MockRouter();

        mainVault = new MockMainVault();
        mainVault.setAvailableRouter(address(router), true);
        mainVault.setAvailableToken(address(tokenMI), true);
        mainVault.setAvailableToken(address(tokenMV), true);
        mainVault.setAvailableToken(address(assetToken1), true);
        mainVault.setAvailableToken(address(assetToken2), true);

        implementation = new InvestmentVault();
        mainVault.setCurrentImplementation(address(implementation));

        DataTypes.AssetInitData[] memory assets = new DataTypes.AssetInitData[](2);

        assets[0] = DataTypes.AssetInitData({
            token: IERC20(address(tokenMI)),
            shareMV: 5 * 10 ** 17,
            step: 5 * 10 ** 16,
            strategy: DataTypes.Strategy.Zero
        });

        assets[1] = DataTypes.AssetInitData({
            token: IERC20(address(assetToken2)),
            shareMV: 5 * 10 ** 17,
            step: 5 * 10 ** 16,
            strategy: DataTypes.Strategy.First
        });

        DataTypes.InvestmentVaultInitData memory initData = DataTypes.InvestmentVaultInitData({
            mainVault: IMainVault(address(mainVault)),
            tokenMI: IERC20(address(tokenMI)),
            tokenMV: IERC20(address(tokenMV)),
            initDeposit: INITIAL_BALANCE,
            shareMI: 7 * 10 ** 17,
            step: 5 * 10 ** 16,
            assets: assets
        });

        bytes memory encodedInitData = abi.encodeWithSelector(InvestmentVault.initialize.selector, initData);

        vm.expectRevert(InvestmentVault.InvalidToken.selector);
        proxy = new ERC1967Proxy(address(implementation), encodedInitData);

        vm.stopPrank();
    }

    function testInitialization_AssetInvalidTokenMV() public {
        vm.startPrank(owner);

        tokenMI = new MockToken("MI Token", "MI", 18);
        tokenMV = new MockToken("MV Token", "MV", 18);
        assetToken1 = new MockToken("Asset Token 1", "AT1", 18);
        assetToken2 = new MockToken("Asset Token 2", "AT2", 6);
        router = new MockRouter();

        mainVault = new MockMainVault();
        mainVault.setAvailableRouter(address(router), true);
        mainVault.setAvailableToken(address(tokenMI), true);
        mainVault.setAvailableToken(address(tokenMV), true);
        mainVault.setAvailableToken(address(assetToken1), true);
        mainVault.setAvailableToken(address(assetToken2), true);

        implementation = new InvestmentVault();
        mainVault.setCurrentImplementation(address(implementation));

        DataTypes.AssetInitData[] memory assets = new DataTypes.AssetInitData[](2);

        assets[0] = DataTypes.AssetInitData({
            token: IERC20(address(assetToken1)),
            shareMV: 5 * 10 ** 17,
            step: 5 * 10 ** 16,
            strategy: DataTypes.Strategy.Zero
        });

        assets[1] = DataTypes.AssetInitData({
            token: IERC20(address(tokenMV)),
            shareMV: 5 * 10 ** 17,
            step: 5 * 10 ** 16,
            strategy: DataTypes.Strategy.First
        });

        DataTypes.InvestmentVaultInitData memory initData = DataTypes.InvestmentVaultInitData({
            mainVault: IMainVault(address(mainVault)),
            tokenMI: IERC20(address(tokenMI)),
            tokenMV: IERC20(address(tokenMV)),
            initDeposit: INITIAL_BALANCE,
            shareMI: 7 * 10 ** 17,
            step: 5 * 10 ** 16,
            assets: assets
        });

        bytes memory encodedInitData = abi.encodeWithSelector(InvestmentVault.initialize.selector, initData);

        vm.expectRevert(InvestmentVault.InvalidToken.selector);
        proxy = new ERC1967Proxy(address(implementation), encodedInitData);

        vm.stopPrank();
    }

    function testInitialization_InvalidShareMiForSameTokens() public {
        vm.startPrank(owner);

        tokenMI = new MockToken("Same Token", "SAME", 18);
        assetToken1 = new MockToken("Asset Token 1", "AT1", 18);
        assetToken2 = new MockToken("Asset Token 2", "AT2", 6);
        router = new MockRouter();

        mainVault = new MockMainVault();
        mainVault.setAvailableRouter(address(router), true);
        mainVault.setAvailableToken(address(tokenMI), true);
        mainVault.setAvailableToken(address(assetToken1), true);
        mainVault.setAvailableToken(address(assetToken2), true);

        implementation = new InvestmentVault();
        mainVault.setCurrentImplementation(address(implementation));

        DataTypes.AssetInitData[] memory assets = new DataTypes.AssetInitData[](2);

        assets[0] = DataTypes.AssetInitData({
            token: IERC20(address(assetToken1)),
            shareMV: 5 * 10 ** 17,
            step: 5 * 10 ** 16,
            strategy: DataTypes.Strategy.Zero
        });

        assets[1] = DataTypes.AssetInitData({
            token: IERC20(address(assetToken2)),
            shareMV: 5 * 10 ** 17,
            step: 5 * 10 ** 16,
            strategy: DataTypes.Strategy.First
        });

        DataTypes.InvestmentVaultInitData memory initData = DataTypes.InvestmentVaultInitData({
            mainVault: IMainVault(address(mainVault)),
            tokenMI: IERC20(address(tokenMI)),
            tokenMV: IERC20(address(tokenMI)),
            initDeposit: INITIAL_BALANCE,
            shareMI: 7 * 10 ** 17,
            step: 5 * 10 ** 16,
            assets: assets
        });

        bytes memory encodedInitData = abi.encodeWithSelector(InvestmentVault.initialize.selector, initData);

        vm.expectRevert(InvestmentVault.InvalidShareMi.selector);
        proxy = new ERC1967Proxy(address(implementation), encodedInitData);

        vm.stopPrank();
    }

    function testSetShareMi_ExceedsDenominator() public {
        setUp_DifferentTokens();
        vm.startPrank(owner);

        vm.expectRevert(InvestmentVault.ShareExceedsMaximum.selector);
        vault.setShareMi(Constants.SHARE_DENOMINATOR + 1);

        vm.stopPrank();
    }
}

contract InvestmentVaultV2 is InvestmentVault {
    function version() external pure returns (uint256) {
        return 2;
    }
}

contract PriceDeviationTest is InvestmentVault {
    function validatePriceDeviation(uint256 amountIn1, uint256 amountOut1, uint256 amountIn2, uint256 amountOut2)
        public
        pure
        returns (bool)
    {
        return _validatePriceDeviation(amountIn1, amountOut1, amountIn2, amountOut2);
    }
}

contract PriceDeviationTests is Test {
    PriceDeviationTest public vault;

    function setUp() public {
        vault = new PriceDeviationTest();
    }

    function testValidateDeviation_InvalidAmountIn() public {
        uint256 amountIn1 = 1000 * 10 ** 18;
        uint256 amountOut1 = 500 * 10 ** 18;
        uint256 amountIn2 = 2100 * 10 ** 18;
        uint256 amountOut2 = 1050 * 10 ** 18;

        bool result = vault.validatePriceDeviation(amountIn1, amountOut1, amountIn2, amountOut2);
        assertFalse(result, "Should return false for invalid amountIn2");
    }

    function testValidateDeviation_Price1GreaterThanPrice2_WithinDeviation() public {
        uint256 amountIn1 = 1000 * 10 ** 18;
        uint256 amountOut1 = 500 * 10 ** 18;
        uint256 amountIn2 = amountIn1 * Constants.PRICE_CHECK_DENOMINATOR;
        uint256 amountOut2 = 501 * 10 ** 18 * Constants.PRICE_CHECK_DENOMINATOR;

        bool result = vault.validatePriceDeviation(amountIn1, amountOut1, amountIn2, amountOut2);
        assertTrue(result, "Should return true for acceptable price deviation (price1 > price2)");
    }

    function testValidateDeviation_Price2GreaterThanPrice1_WithinDeviation() public {
        uint256 amountIn1 = 1000 * 10 ** 18;
        uint256 amountOut1 = 501 * 10 ** 18;
        uint256 amountIn2 = amountIn1 * Constants.PRICE_CHECK_DENOMINATOR;
        uint256 amountOut2 = 500 * 10 ** 18 * Constants.PRICE_CHECK_DENOMINATOR;

        bool result = vault.validatePriceDeviation(amountIn1, amountOut1, amountIn2, amountOut2);
        assertTrue(result, "Should return true for acceptable price deviation (price2 > price1)");
    }

    function testValidateDeviation_Price1GreaterThanPrice2_ExceedsDeviation() public {
        uint256 amountIn1 = 1000 * 10 ** 18;
        uint256 amountOut1 = 500 * 10 ** 18;
        uint256 amountIn2 = amountIn1 * Constants.PRICE_CHECK_DENOMINATOR;
        uint256 amountOut2 = 1000 * 10 ** 18 * Constants.PRICE_CHECK_DENOMINATOR;

        bool result = vault.validatePriceDeviation(amountIn1, amountOut1, amountIn2, amountOut2);
        assertTrue(result, "Should return true for excessive price deviation (price1 > price2)");
    }

    function testValidateDeviation_Price2GreaterThanPrice1_ExceedsDeviation() public {
        uint256 amountIn1 = 1000 * 10 ** 18;
        uint256 amountOut1 = 1000 * 10 ** 18;
        uint256 amountIn2 = amountIn1 * Constants.PRICE_CHECK_DENOMINATOR;
        uint256 amountOut2 = 500 * 10 ** 18 * Constants.PRICE_CHECK_DENOMINATOR;

        bool result = vault.validatePriceDeviation(amountIn1, amountOut1, amountIn2, amountOut2);
        assertFalse(result, "Should return false for excessive price deviation (price2 > price1)");
    }

    function testValidateDeviation_EqualPrices() public {
        uint256 amountIn1 = 1000 * 10 ** 18;
        uint256 amountOut1 = 500 * 10 ** 18;
        uint256 amountIn2 = amountIn1 * Constants.PRICE_CHECK_DENOMINATOR;
        uint256 amountOut2 = amountOut1 * Constants.PRICE_CHECK_DENOMINATOR;

        bool result = vault.validatePriceDeviation(amountIn1, amountOut1, amountIn2, amountOut2);
        assertTrue(result, "Should return true for equal prices");
    }

    function testValidateDeviation_ZeroAmounts() public {
        uint256 amountIn1 = 1000 * 10 ** 18;
        uint256 amountIn2 = amountIn1 * Constants.PRICE_CHECK_DENOMINATOR;

        vm.expectRevert();
        vault.validatePriceDeviation(amountIn1, 0, amountIn2, 500 * 10 ** 18 * Constants.PRICE_CHECK_DENOMINATOR);

        vm.expectRevert();
        vault.validatePriceDeviation(amountIn1, 500 * 10 ** 18, amountIn2, 0);
    }

    function testValidateDeviation_LargeNumbers() public {
        uint256 amountIn1 = 1000000 * 10 ** 18;
        uint256 amountOut1 = 500000 * 10 ** 18;
        uint256 amountIn2 = amountIn1 * Constants.PRICE_CHECK_DENOMINATOR;
        uint256 amountOut2 = 500100 * 10 ** 18 * Constants.PRICE_CHECK_DENOMINATOR;

        bool result = vault.validatePriceDeviation(amountIn1, amountOut1, amountIn2, amountOut2);
        assertTrue(result, "Should return true for acceptable price deviation with large numbers");
    }

    function testValidateDeviation_SmallNumbers() public {
        uint256 amountIn1 = 100;
        uint256 amountOut1 = 50;
        uint256 amountIn2 = amountIn1 * Constants.PRICE_CHECK_DENOMINATOR;
        uint256 amountOut2 = 51 * Constants.PRICE_CHECK_DENOMINATOR;

        bool result = vault.validatePriceDeviation(amountIn1, amountOut1, amountIn2, amountOut2);
        assertTrue(result, "Should return true for acceptable price deviation with small numbers");
    }
}
