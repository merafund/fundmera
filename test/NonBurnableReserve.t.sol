// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 fundmera.com

// https://github.com/merafund
pragma solidity ^0.8.29;

import {Test, console} from "forge-std/Test.sol";
import {SwapLibrary} from "../src/utils/SwapLibrary.sol";
import {Constants} from "../src/utils/Constants.sol";
import {DataTypes} from "../src/utils/DataTypes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockToken} from "../src/mocks/MockToken.sol";
import {MockMainVault} from "../src/mocks/MockMainVault.sol";
import {MockMeraPriceOracle} from "../src/mocks/MockMeraPriceOracle.sol";
import {IMainVault} from "../src/interfaces/IMainVault.sol";

// Wrapper contract to test internal functions
contract SwapLibraryWrapper {
    function checkNonBurnableReserve(uint256 mvBalanceAfter, uint256 totalMvBought, uint256 profitMV) external pure {
        SwapLibrary.checkNonBurnableReserve(mvBalanceAfter, totalMvBought, profitMV);
    }
}

// Test contract that exposes internal functions for testing
contract SwapLibraryTestWrapper {
    using SwapLibrary for DataTypes.TokenData;

    DataTypes.TokenData public tokenData;

    function setTokenData(DataTypes.TokenData memory _tokenData) external {
        tokenData = _tokenData;
    }

    function validateMvPriceFromEntryPoint(address mainVault) external view {
        SwapLibrary._validateMvPriceFromEntryPoint(tokenData, IMainVault(mainVault));
    }
}

contract NonBurnableReserveTest is Test {
    SwapLibraryWrapper public wrapper;
    SwapLibraryTestWrapper public testWrapper;
    MockToken public tokenMI;
    MockToken public tokenMV;
    MockMainVault public mainVault;
    MockMeraPriceOracle public oracle;
    DataTypes.TokenData public tokenData;

    function setUp() public {
        wrapper = new SwapLibraryWrapper();
        testWrapper = new SwapLibraryTestWrapper();

        // Deploy mock tokens
        tokenMI = new MockToken("MI Token", "MI", 18);
        tokenMV = new MockToken("MV Token", "MV", 18);

        // Deploy mock contracts
        mainVault = new MockMainVault();
        oracle = new MockMeraPriceOracle();

        // Setup main vault
        mainVault.setMeraPriceOracle(address(oracle));
        mainVault.setIsCanceledOracleCheck(false);

        // Setup token data
        tokenData = DataTypes.TokenData({
            tokenMI: IERC20(address(tokenMI)),
            tokenMV: IERC20(address(tokenMV)),
            capitalOfMi: 10000 * 10 ** 18,
            mvBought: 1000 * 10 ** 18,
            shareMV: 7 * 10 ** 17,
            depositInMv: 1000 * 10 ** 18,
            timestampOfStartInvestment: block.timestamp,
            profitType: DataTypes.ProfitType.Dynamic,
            step: 5 * 10 ** 16,
            lastBuyPrice: 0, // Will be set in individual tests
            lastBuyTimestamp: 0
        });
    }

    function testCheckNonBurnableReserve_SufficientReserve() public {
        uint256 mvBalanceAfter = 1000 * 10 ** 18; // 1000 MV
        uint256 totalMvBought = 1000 * 10 ** 18; // 1000 MV bought
        uint256 profitMV = 100 * 10 ** 18; // 100 MV profit

        // This should not revert - we have enough reserve
        wrapper.checkNonBurnableReserve(mvBalanceAfter, totalMvBought, profitMV);
    }

    function testCheckNonBurnableReserve_InsufficientReserve() public {
        uint256 mvBalanceAfter = 150 * 10 ** 18; // 150 MV
        uint256 totalMvBought = 1000 * 10 ** 18; // 1000 MV bought
        uint256 profitMV = 50 * 10 ** 18; // 50 MV profit

        // Available MV for trading = 150 - 50 = 100 MV
        // Required reserve = 20% of 1000 = 200 MV
        // 100 < 200, so this should revert

        vm.expectRevert(SwapLibrary.InsufficientNonBurnableReserve.selector);
        wrapper.checkNonBurnableReserve(mvBalanceAfter, totalMvBought, profitMV);
    }

    function testCheckNonBurnableReserve_ExactReserve() public {
        uint256 totalMvBought = 1000 * 10 ** 18; // 1000 MV bought
        uint256 profitMV = 50 * 10 ** 18; // 50 MV profit
        uint256 requiredReserve = (totalMvBought * Constants.NON_BURNABLE_RESERVE_PERCENT) / Constants.SHARE_DENOMINATOR; // 200 MV
        uint256 mvBalanceAfter = requiredReserve + profitMV; // Exactly enough

        // This should not revert - we have exactly enough reserve
        wrapper.checkNonBurnableReserve(mvBalanceAfter, totalMvBought, profitMV);
    }

    function testCheckNonBurnableReserve_ZeroProfit() public {
        uint256 mvBalanceAfter = 200 * 10 ** 18; // 200 MV
        uint256 totalMvBought = 1000 * 10 ** 18; // 1000 MV bought
        uint256 profitMV = 0; // No profit

        // Available MV for trading = 200 - 0 = 200 MV
        // Required reserve = 20% of 1000 = 200 MV
        // 200 >= 200, so this should not revert

        wrapper.checkNonBurnableReserve(mvBalanceAfter, totalMvBought, profitMV);
    }

    function testCheckNonBurnableReserve_ZeroMvBought() public {
        uint256 mvBalanceAfter = 100 * 10 ** 18; // 100 MV
        uint256 totalMvBought = 0; // No MV bought yet
        uint256 profitMV = 50 * 10 ** 18; // 50 MV profit

        // Required reserve = 20% of 0 = 0 MV
        // Available MV for trading = 100 - 50 = 50 MV
        // 50 >= 0, so this should not revert

        wrapper.checkNonBurnableReserve(mvBalanceAfter, totalMvBought, profitMV);
    }

    function testValidateMvPriceFromEntryPoint_NoEntryPrice() public {
        // Test when lastBuyPrice is 0 (no entry point set)
        tokenData.lastBuyPrice = 0;
        testWrapper.setTokenData(tokenData);

        // Should not revert - no validation when no entry price is set
        testWrapper.validateMvPriceFromEntryPoint(address(mainVault));
    }

    function testValidateMvPriceFromEntryPoint_OracleCheckCanceled() public {
        // Test when oracle check is canceled
        mainVault.setIsCanceledOracleCheck(true);
        tokenData.lastBuyPrice = 1 * 10 ** 18; // Set entry price
        testWrapper.setTokenData(tokenData);

        // Should not revert - validation skipped when oracle check is canceled
        testWrapper.validateMvPriceFromEntryPoint(address(mainVault));
    }

    function testValidateMvPriceFromEntryPoint_PriceNotDeclined() public {
        // Test when current price is higher than entry price
        tokenData.lastBuyPrice = 1 * 10 ** 18; // Entry price: 1 MV = 1 MI
        testWrapper.setTokenData(tokenData);

        // Set oracle prices: 1 MI = 1 USD, 1 MV = 1.1 USD (price increased)
        oracle.setAssetPrice(address(tokenMI), 1 * 10 ** 6, 6); // 1 MI = 1 USD
        oracle.setAssetPrice(address(tokenMV), 11 * 10 ** 5, 6); // 1 MV = 1.1 USD

        // Should not revert - price hasn't declined
        testWrapper.validateMvPriceFromEntryPoint(address(mainVault));
    }

    function testValidateMvPriceFromEntryPoint_PriceDeclinedWithinLimit() public {
        // Test when price declined but within 0.5% limit
        tokenData.lastBuyPrice = 1 * 10 ** 18; // Entry price: 1 MV = 1 MI
        testWrapper.setTokenData(tokenData);

        // Set oracle prices: 1 MI = 1 USD, 1 MV = 0.996 USD (0.4% decline)
        oracle.setAssetPrice(address(tokenMI), 1 * 10 ** 6, 6); // 1 MI = 1 USD
        oracle.setAssetPrice(address(tokenMV), 996 * 10 ** 3, 6); // 1 MV = 0.996 USD

        // Should not revert - decline is within 0.5% limit
        testWrapper.validateMvPriceFromEntryPoint(address(mainVault));
    }

    function testValidateMvPriceFromEntryPoint_PriceDeclinedExceedsLimit() public {
        // Test when price declined more than 0.5% limit
        tokenData.lastBuyPrice = 1 * 10 ** 18; // Entry price: 1 MV = 1 MI
        testWrapper.setTokenData(tokenData);

        // Set oracle prices: 1 MI = 1 USD, 1 MV = 0.99 USD (1% decline)
        oracle.setAssetPrice(address(tokenMI), 1 * 10 ** 6, 6); // 1 MI = 1 USD
        oracle.setAssetPrice(address(tokenMV), 99 * 10 ** 4, 6); // 1 MV = 0.99 USD

        // Should revert - decline exceeds 0.5% limit
        vm.expectRevert(SwapLibrary.MvPriceDeclinedTooMuch.selector);
        testWrapper.validateMvPriceFromEntryPoint(address(mainVault));
    }

    function testValidateMvPriceFromEntryPoint_ExactLimit() public {
        // Test when price declined exactly at 0.5% limit
        tokenData.lastBuyPrice = 1 * 10 ** 18; // Entry price: 1 MV = 1 MI
        testWrapper.setTokenData(tokenData);

        // Set oracle prices: 1 MI = 1 USD, 1 MV = 0.995 USD (exactly 0.5% decline)
        oracle.setAssetPrice(address(tokenMI), 1 * 10 ** 6, 6); // 1 MI = 1 USD
        oracle.setAssetPrice(address(tokenMV), 995 * 10 ** 3, 6); // 1 MV = 0.995 USD

        // Should not revert - decline is exactly at 0.5% limit
        testWrapper.validateMvPriceFromEntryPoint(address(mainVault));
    }

    function testValidateMvPriceFromEntryPoint_DifferentDecimals() public {
        // Test with different token decimals
        tokenData.lastBuyPrice = 1 * 10 ** 18; // Entry price: 1 MV = 1 MI
        testWrapper.setTokenData(tokenData);

        // Set oracle prices with different decimals: MI=18, MV=6
        oracle.setAssetPrice(address(tokenMI), 1 * 10 ** 18, 18); // 1 MI = 1 MI (18 decimals)
        oracle.setAssetPrice(address(tokenMV), 995 * 10 ** 3, 6); // 1 MV = 0.995 USD (6 decimals)

        // Should not revert - decline is within 0.5% limit
        testWrapper.validateMvPriceFromEntryPoint(address(mainVault));
    }
}
