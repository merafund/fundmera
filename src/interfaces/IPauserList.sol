// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 fundmera.com

// https://github.com/merafund
pragma solidity ^0.8.29;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

/// @title IPauserList
/// @dev Interface for the contract that stores a list of addresses with the right to pause functions
interface IPauserList is IAccessControl {
    /// @dev Returns the identifier of the pauser role
    /// @return identifier of the pauser role
    function PAUSER_ROLE() external view returns (bytes32);
}
