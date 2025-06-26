// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 fundmera.com

// https://github.com/merafund
pragma solidity ^0.8.10;

import {AggregatorInterface} from "./dependencies/chainlink/AggregatorInterface.sol";
import {IPriceOracleGetter} from "./interfaces/IPriceOracleGetter.sol";
import {IMeraPriceOracle} from "./interfaces/IMeraPriceOracle.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MeraPriceOracle
 * @notice Contract to get asset prices, manage price sources and update the fallback oracle
 * - Use of Chainlink Aggregators as first source of price
 * - If the returned price by a Chainlink aggregator is <= 0, the call is forwarded to a fallback oracle
 * - Owned by the Mera governance
 */
contract MeraPriceOracle is IMeraPriceOracle, Ownable {
    // Custom Errors
    error InconsistentParamsLength();

    // Map of asset price sources (asset => priceSource)
    mapping(address => AggregatorInterface) private assetsSources;
    mapping(address => uint8) private assetsDecimals;

    IPriceOracleGetter private _fallbackOracle;

    /**
     * @notice Constructor
     * @param assets The addresses of the assets
     * @param sources The address of the source of each asset
     * @param decimals The decimals for each asset
     * @param fallbackOracle The address of the fallback oracle to use if the data of an
     *        aggregator is not consistent
     */
    constructor(address[] memory assets, address[] memory sources, uint8[] memory decimals, address fallbackOracle)
        Ownable(msg.sender)
    {
        if (assets.length != sources.length || assets.length != decimals.length) {
            revert InconsistentParamsLength();
        }
        _setAssetsSources(assets, sources);
        _setAssetsDecimals(assets, decimals);
        _setFallbackOracle(fallbackOracle);
    }

    /// @inheritdoc IMeraPriceOracle
    function setAssetSources(address[] calldata assets, address[] calldata sources, uint8[] calldata decimals)
        external
        onlyOwner
    {
        if (assets.length != sources.length || assets.length != decimals.length) {
            revert InconsistentParamsLength();
        }
        _setAssetsSources(assets, sources);
        _setAssetsDecimals(assets, decimals);
    }

    /// @inheritdoc IMeraPriceOracle
    function setFallbackOracle(address fallbackOracle) external onlyOwner {
        _setFallbackOracle(fallbackOracle);
    }

    /**
     * @notice Internal function to set the sources for each asset
     * @param assets The addresses of the assets
     * @param sources The address of the source of each asset
     */
    function _setAssetsSources(address[] memory assets, address[] memory sources) internal {
        for (uint256 i = 0; i < assets.length; i++) {
            assetsSources[assets[i]] = AggregatorInterface(sources[i]);
            emit AssetSourceUpdated(assets[i], sources[i]);
        }
    }

    /**
     * @notice Internal function to set decimals for each asset
     * @param assets The addresses of the assets
     * @param decimals The decimals for each asset
     */
    function _setAssetsDecimals(address[] memory assets, uint8[] memory decimals) internal {
        for (uint256 i = 0; i < assets.length; i++) {
            assetsDecimals[assets[i]] = decimals[i];
        }
    }

    /**
     * @notice Internal function to set the fallback oracle
     * @param fallbackOracle The address of the fallback oracle
     */
    function _setFallbackOracle(address fallbackOracle) internal {
        _fallbackOracle = IPriceOracleGetter(fallbackOracle);
        emit FallbackOracleUpdated(fallbackOracle);
    }

    /// @inheritdoc IPriceOracleGetter
    function getAssetPrice(address asset) public view returns (uint256) {
        AggregatorInterface source = assetsSources[asset];

        if (address(source) == address(0)) {
            return _fallbackOracle.getAssetPrice(asset);
        } else {
            int256 price = source.latestAnswer();
            if (price > 0) {
                return uint256(price);
            } else {
                return _fallbackOracle.getAssetPrice(asset);
            }
        }
    }

    /// @inheritdoc IMeraPriceOracle
    function getAssetsPriceData(address[] calldata assets) external view returns (AssetPriceData[] memory) {
        AssetPriceData[] memory priceData = new AssetPriceData[](assets.length);

        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            AggregatorInterface source = assetsSources[asset];

            // Get price
            uint256 price = getAssetPrice(asset);

            // Get last update time
            uint256 lastUpdateTime = 0;
            if (address(source) != address(0)) {
                lastUpdateTime = source.latestTimestamp();
            }

            // Create price data struct
            priceData[i] =
                AssetPriceData({price: price, decimals: assetsDecimals[asset], lastUpdateTime: lastUpdateTime});
        }

        return priceData;
    }

    /// @inheritdoc IMeraPriceOracle
    function getSourceOfAsset(address asset) external view returns (address) {
        return address(assetsSources[asset]);
    }

    /// @inheritdoc IMeraPriceOracle
    function getFallbackOracle() external view returns (address) {
        return address(_fallbackOracle);
    }
}
