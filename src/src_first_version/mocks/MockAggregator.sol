// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 fundmera.com

// https://github.com/merafund
pragma solidity ^0.8.10;

import {AggregatorInterface} from "../dependencies/chainlink/AggregatorInterface.sol";

contract MockAggregator is AggregatorInterface {
    int256 private _price;
    bool private _shouldReturnZero;
    uint256 private _lastUpdateTime;

    function setPrice(int256 price) external {
        _price = price;
        _lastUpdateTime = block.timestamp;
    }

    function setShouldReturnZero(bool shouldReturnZero) external {
        _shouldReturnZero = shouldReturnZero;
    }

    function latestAnswer() external view returns (int256) {
        if (_shouldReturnZero) {
            return 0;
        }
        return _price;
    }

    function latestTimestamp() external view returns (uint256) {
        return _lastUpdateTime;
    }

    function latestRound() external view returns (uint256) {
        return 1;
    }

    function getAnswer(uint256) external view returns (int256) {
        return _price;
    }

    function getTimestamp(uint256) external view returns (uint256) {
        return block.timestamp;
    }
}
