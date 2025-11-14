// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 fundmera.com

// https://github.com/merafund
pragma solidity 0.8.29;

import {IMeraPriceOracle} from "../interfaces/IMeraPriceOracle.sol";

contract MockMeraPriceOracle is IMeraPriceOracle {
    mapping(address => uint256) public prices;
    mapping(address => uint8) public decimals;
    mapping(address => uint256) public lastUpdateTimes;
    mapping(address => address) public sources;
    address public fallbackOracle;

    function setAssetPrice(address asset, uint256 price, uint8 assetDecimals) external {
        prices[asset] = price;
        decimals[asset] = assetDecimals;
        lastUpdateTimes[asset] = block.timestamp;
    }

    function getAssetsPriceData(address[] calldata assets) external view returns (AssetPriceData[] memory) {
        AssetPriceData[] memory priceData = new AssetPriceData[](assets.length);

        for (uint256 i = 0; i < assets.length; i++) {
            priceData[i] = AssetPriceData({
                price: prices[assets[i]],
                decimals: decimals[assets[i]],
                lastUpdateTime: lastUpdateTimes[assets[i]]
            });
        }

        return priceData;
    }

    function getAssetPrice(address asset) external view returns (uint256) {
        return prices[asset];
    }

    function setAssetSources(address[] calldata assets, address[] calldata _sources, uint8[] calldata _decimals)
        external
    {
        for (uint256 i = 0; i < assets.length; i++) {
            sources[assets[i]] = _sources[i];
            decimals[assets[i]] = _decimals[i];
            emit AssetSourceUpdated(assets[i], _sources[i]);
        }
    }

    function setFallbackOracle(address _fallbackOracle) external {
        fallbackOracle = _fallbackOracle;
        emit FallbackOracleUpdated(_fallbackOracle);
    }

    function getSourceOfAsset(address asset) external view returns (address) {
        return sources[asset];
    }

    function getFallbackOracle() external view returns (address) {
        return fallbackOracle;
    }
}
