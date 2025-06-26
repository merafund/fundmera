// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 fundmera.com

// https://github.com/merafund
pragma solidity ^0.8.29;

import {MainVault} from "../../src/MainVault.sol";

contract MainVaultV2 is MainVault {
    // Add a dummy function to make it different from V1
    function dummyFunction() external pure returns (uint256) {
        return 42;
    }
}
