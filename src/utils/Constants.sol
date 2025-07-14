// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 fundmera.com

// https://github.com/merafund
pragma solidity ^0.8.29;

/**
 * @title Constants
 * @dev Library that contains all project constants in one place
 */
library Constants {
    // Common denominators
    uint256 public constant SHARE_DENOMINATOR = 1e18;

    // Time constants
    uint256 public constant PAUSE_AFTER_INIT = 4 hours;
    uint256 public constant AUTO_RENEW_CHECK_PERIOD = 7 days; // Period before lock expiry to check for auto-renewal
    uint256 public constant AUTO_RENEW_PERIOD = 182 days; // Period to extend lock when auto-renewal is enabled
    uint256 public constant PAUSE_AFTER_UPDATE_ACCESS = 4 hours; // Pause period after access update
    uint256 public constant WITHDRAW_COMMIT_MIN_DELAY = 1 hours; // Minimum delay for withdraw commit
    uint256 public constant WITHDRAW_COMMIT_MAX_DELAY = 1 days; // Maximum delay for withdraw commit

    // Percentage constants
    uint256 public constant MAX_PERCENT = 10000; // Represents 100.00% - fee percentage can't exceed this value

    // Price validation constants
    uint256 public constant PRICE_CHECK_DENOMINATOR = 100; // Denominator for price check calculation
    uint256 public constant PRICE_DIFF_MULTIPLIER = 100; // Multiplier for price difference calculation
    uint256 public constant MAX_PRICE_DEVIATION = 3 * 1e18; // Maximum allowed price deviation (3%)

    uint256 public constant MAX_PRICE_DEVIATION_FROM_ORACLE = 5 * 1e18; // Maximum allowed price deviation from oracle (5%)

    uint256 public constant MAX_FIXED_PROFIT_PERCENT = 2500; // Represents 25.00% - fixed profit percent can't exceed this value
    uint256 public constant MIN_TIME_BETWEEN_BUYS = 30 days; // Minimum time between buys of an asset
    uint256 public constant MAX_STEP = 3e17; // Maximum step of an asset
    uint256 public constant MIN_STEP = 2e16; // Minimum step of an asset
    uint256 public constant SHARE_INITIAL_MAX = 7e17; // Maximum share of an asset
}
