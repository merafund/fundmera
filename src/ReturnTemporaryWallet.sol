// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 fundmera.com

// https://github.com/merafund
pragma solidity ^0.8.29;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title ReturnTemporaryWallet
/// @dev Contract that allows setting a recipient address once and transferring tokens to it
contract ReturnTemporaryWallet is Ownable {
    using SafeERC20 for IERC20;

    // Custom Errors
    error RecipientAddressLocked();
    error ZeroAddressNotAllowed();
    error RecipientNotSet();

    // Recipient address
    address public recipient;

    // Flag that prevents changing recipient after it's been set
    bool public recipientLocked;

    // Events
    event RecipientSet(address indexed sender, address indexed recipient);
    event RecipientLocked(address indexed sender);

    constructor() Ownable(msg.sender) {}

    /// @notice Sets the recipient address. Can only be called once.
    /// @param _recipient The address to set as recipient
    function setRecipient(address _recipient) external onlyOwner {
        require(!recipientLocked, RecipientAddressLocked());
        require(_recipient != address(0), ZeroAddressNotAllowed());
        recipient = _recipient;
        emit RecipientSet(msg.sender, _recipient);
    }

    /// @notice Sets recipientLocked to true. Can only set to true, cannot revert to false.
    function setRecipientLocked() external onlyOwner {
        recipientLocked = true;
        emit RecipientLocked(msg.sender);
    }

    /// @notice Transfers tokens from this contract to the recipient address
    /// @param token The token contract address
    /// @param amount The amount of tokens to transfer
    function transferToken(address token, uint256 amount) external onlyOwner {
        require(recipient != address(0), RecipientNotSet());
        require(token != address(0), ZeroAddressNotAllowed());
        IERC20(token).safeTransfer(recipient, amount);
    }
}

