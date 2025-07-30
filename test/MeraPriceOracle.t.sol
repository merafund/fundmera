// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 fundmera.com

// https://github.com/merafund
pragma solidity ^0.8.10;

import {Test} from "forge-std/Test.sol";
import {MeraPriceOracle} from "../src/MeraPriceOracle.sol";
import {MockAggregator} from "../src/mocks/MockAggregator.sol";
import {MockFallbackOracle} from "../src/mocks/MockFallbackOracle.sol";

contract MeraPriceOracleTest is Test {
    MeraPriceOracle public oracle;
    MockAggregator public mockAggregator1;
    MockAggregator public mockAggregator2;
    MockFallbackOracle public mockFallbackOracle;

    address public constant ASSET1 = address(0x1);
    address public constant ASSET2 = address(0x2);
    address public owner;

    uint8 public constant DECIMALS1 = 8;
    uint8 public constant DECIMALS2 = 18;

    function setUp() public {
        mockAggregator1 = new MockAggregator();
        mockAggregator2 = new MockAggregator();
        mockFallbackOracle = new MockFallbackOracle();

        address[] memory assets = new address[](2);
        assets[0] = ASSET1;
        assets[1] = ASSET2;

        address[] memory sources = new address[](2);
        sources[0] = address(mockAggregator1);
        sources[1] = address(mockAggregator2);

        uint8[] memory decimals = new uint8[](2);
        decimals[0] = DECIMALS1;
        decimals[1] = DECIMALS2;

        oracle = new MeraPriceOracle(assets, sources, decimals, address(mockFallbackOracle));

        owner = oracle.owner();
    }

    function test_InitialSetup() public {
        assertEq(oracle.getSourceOfAsset(ASSET1), address(mockAggregator1));
        assertEq(oracle.getSourceOfAsset(ASSET2), address(mockAggregator2));
        assertEq(oracle.getFallbackOracle(), address(mockFallbackOracle));

        address[] memory assets = new address[](2);
        assets[0] = ASSET1;
        assets[1] = ASSET2;

        MeraPriceOracle.AssetPriceData[] memory priceData = oracle.getAssetsPriceData(assets);
        assertEq(priceData[0].decimals, DECIMALS1);
        assertEq(priceData[1].decimals, DECIMALS2);
    }

    function test_GetAssetPrice_FromAggregator() public {
        mockAggregator1.setPrice(100);
        uint256 price = oracle.getAssetPrice(ASSET1);
        assertEq(price, 100);
    }

    function test_GetAssetPrice_FromFallback_WhenAggregatorReturnsZero() public {
        mockAggregator1.setShouldReturnZero(true);
        mockFallbackOracle.setAssetPrice(ASSET1, 200);
        uint256 price = oracle.getAssetPrice(ASSET1);
        assertEq(price, 200);
    }

    function test_GetAssetPrice_FromFallback_WhenNoAggregator() public {
        address assetWithoutAggregator = address(0x3);
        mockFallbackOracle.setAssetPrice(assetWithoutAggregator, 300);
        uint256 price = oracle.getAssetPrice(assetWithoutAggregator);
        assertEq(price, 300);
    }

    function test_GetAssetPrice_FromFallback_WhenAggregatorReturnsNegative() public {
        mockAggregator1.setPrice(-100);
        mockFallbackOracle.setAssetPrice(ASSET1, 400);
        uint256 price = oracle.getAssetPrice(ASSET1);
        assertEq(price, 400);
    }

    function test_GetAssetsPriceData() public {
        mockAggregator1.setPrice(100);
        mockAggregator2.setPrice(200);

        address[] memory assets = new address[](2);
        assets[0] = ASSET1;
        assets[1] = ASSET2;

        MeraPriceOracle.AssetPriceData[] memory priceData = oracle.getAssetsPriceData(assets);

        assertEq(priceData.length, 2);
        assertEq(priceData[0].price, 100);
        assertEq(priceData[0].decimals, DECIMALS1);
        assertEq(priceData[0].lastUpdateTime, block.timestamp);

        assertEq(priceData[1].price, 200);
        assertEq(priceData[1].decimals, DECIMALS2);
        assertEq(priceData[1].lastUpdateTime, block.timestamp);
    }

    function test_SetAssetSources() public {
        MockAggregator newAggregator = new MockAggregator();

        // Use a new asset that doesn't have a source set yet
        address newAsset = address(0x3);
        address[] memory assets = new address[](1);
        assets[0] = newAsset;

        address[] memory sources = new address[](1);
        sources[0] = address(newAggregator);

        uint8[] memory decimals = new uint8[](1);
        decimals[0] = 6;

        vm.prank(owner);
        oracle.setAssetSources(assets, sources, decimals);

        assertEq(oracle.getSourceOfAsset(newAsset), address(newAggregator));

        MeraPriceOracle.AssetPriceData[] memory priceData = oracle.getAssetsPriceData(assets);
        assertEq(priceData[0].decimals, 6);
    }

    function test_SetFallbackOracle() public {
        MockFallbackOracle newFallbackOracle = new MockFallbackOracle();

        vm.prank(owner);
        oracle.setFallbackOracle(address(newFallbackOracle));

        assertEq(oracle.getFallbackOracle(), address(newFallbackOracle));
    }

    function test_RevertWhen_SetAssetSources_NotOwner() public {
        address[] memory assets = new address[](1);
        address[] memory sources = new address[](1);
        uint8[] memory decimals = new uint8[](1);

        vm.prank(address(0x9999));
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", address(0x9999)));
        oracle.setAssetSources(assets, sources, decimals);
    }

    function test_RevertWhen_SetFallbackOracle_NotOwner() public {
        vm.prank(address(0x9999));
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", address(0x9999)));
        oracle.setFallbackOracle(address(0x8888));
    }

    function test_RevertWhen_SetAssetSources_InconsistentLength() public {
        address[] memory assets = new address[](2);
        address[] memory sources = new address[](1);
        uint8[] memory decimals = new uint8[](1);

        vm.prank(owner);
        vm.expectRevert(MeraPriceOracle.InconsistentParamsLength.selector);
        oracle.setAssetSources(assets, sources, decimals);
    }

    function test_RevertWhen_Constructor_InconsistentLength() public {
        address[] memory assets = new address[](2);
        address[] memory sources = new address[](1);
        uint8[] memory decimals = new uint8[](1);

        vm.expectRevert(MeraPriceOracle.InconsistentParamsLength.selector);
        new MeraPriceOracle(assets, sources, decimals, address(mockFallbackOracle));
    }

    function test_RevertWhen_SetAssetSources_AssetSourceAlreadySet() public {
        MockAggregator newAggregator = new MockAggregator();

        address[] memory assets = new address[](1);
        assets[0] = ASSET1; // ASSET1 already has a source set in setUp

        address[] memory sources = new address[](1);
        sources[0] = address(newAggregator);

        uint8[] memory decimals = new uint8[](1);
        decimals[0] = 6;

        vm.prank(owner);
        vm.expectRevert(MeraPriceOracle.AssetSourceAlreadySet.selector);
        oracle.setAssetSources(assets, sources, decimals);
    }
}
