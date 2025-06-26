// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 fundmera.com

// https://github.com/merafund
pragma solidity ^0.8.10;

import {IPriceOracleGetter} from "./IPriceOracleGetter.sol";

/**
 * @title IMeraPriceOracle
 * @notice Interface for the Mera price oracle.
 */
interface IMeraPriceOracle is IPriceOracleGetter {
    /**
     * @dev Emitted when the source of an asset is updated
     * @param asset The address of the asset
     * @param source The address of the source
     */
    event AssetSourceUpdated(address indexed asset, address indexed source);

    /**
     * @dev Emitted when the fallback oracle is updated
     * @param fallbackOracle The address of the fallback oracle
     */
    event FallbackOracleUpdated(address indexed fallbackOracle);

    /**
     * @dev Structure containing all price-related data for an asset
     * @param price The current price of the asset
     * @param decimals The number of decimals for the asset price
     * @param lastUpdateTime The timestamp of the last price update
     */
    struct AssetPriceData {
        uint256 price;
        uint8 decimals;
        uint256 lastUpdateTime;
    }

    /**
     * @notice Sets the sources for multiple assets
     * @param assets The addresses of the assets
     * @param sources The addresses of the price sources
     * @param decimals The decimals of the assets
     */
    function setAssetSources(address[] calldata assets, address[] calldata sources, uint8[] calldata decimals)
        external;

    /**
     * @notice Sets the fallback oracle
     * @param fallbackOracle The address of the fallback oracle
     */
    function setFallbackOracle(address fallbackOracle) external;

    /**
     * @notice Gets all price data for a list of assets
     * @param assets The addresses of the assets
     * @return Array of AssetPriceData structs containing price information
     */
    function getAssetsPriceData(address[] calldata assets) external view returns (AssetPriceData[] memory);

    /**
     * @notice Gets the source of an asset's price
     * @param asset The address of the asset
     * @return The address of the source
     */
    function getSourceOfAsset(address asset) external view returns (address);

    /**
     * @notice Gets the address of the fallback oracle
     * @return The address of the fallback oracle
     */
    function getFallbackOracle() external view returns (address);
}
