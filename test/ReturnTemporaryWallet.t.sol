// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 fundmera.com

// https://github.com/merafund
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {ReturnTemporaryWallet} from "../src/ReturnTemporaryWallet.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract ReturnTemporaryWalletTest is Test {
    ReturnTemporaryWallet public wallet;
    MockERC20 public token;

    address public owner;
    address public recipient;
    address public nonOwner;
    address public zeroAddress = address(0);

    uint256 public constant INITIAL_TOKEN_BALANCE = 10000 * 10 ** 18;
    uint256 public constant TRANSFER_AMOUNT = 1000 * 10 ** 18;

    event RecipientSet(address indexed sender, address indexed recipient);
    event RecipientLocked(address indexed sender);

    function setUp() public {
        owner = makeAddr("owner");
        recipient = makeAddr("recipient");
        nonOwner = makeAddr("nonOwner");

        // Deploy mock token
        token = new MockERC20();

        // Deploy wallet as owner
        vm.startPrank(owner);
        wallet = new ReturnTemporaryWallet();
        vm.stopPrank();

        // Transfer tokens to wallet for testing
        token.transfer(address(wallet), INITIAL_TOKEN_BALANCE);
    }

    // Constructor tests
    function test_Constructor_SetsOwner() public {
        assertEq(wallet.owner(), owner, "Owner should be set correctly");
    }

    function test_Constructor_InitialState() public {
        assertEq(wallet.recipient(), zeroAddress, "Recipient should be zero address initially");
        assertFalse(wallet.recipientLocked(), "Recipient should not be locked initially");
    }

    // setRecipient tests
    function test_SetRecipient_Success() public {
        vm.startPrank(owner);
        vm.expectEmit(true, true, false, false);
        emit RecipientSet(owner, recipient);
        wallet.setRecipient(recipient);
        vm.stopPrank();

        assertEq(wallet.recipient(), recipient, "Recipient should be set correctly");
        assertFalse(wallet.recipientLocked(), "Recipient should not be locked after setting");
    }

    function test_SetRecipient_RevertWhenNotOwner() public {
        vm.startPrank(nonOwner);
        vm.expectRevert();
        wallet.setRecipient(recipient);
        vm.stopPrank();
    }

    function test_SetRecipient_RevertWhenZeroAddress() public {
        vm.startPrank(owner);
        vm.expectRevert(ReturnTemporaryWallet.ZeroAddressNotAllowed.selector);
        wallet.setRecipient(zeroAddress);
        vm.stopPrank();
    }

    function test_SetRecipient_RevertWhenLocked() public {
        // First set recipient
        vm.startPrank(owner);
        wallet.setRecipient(recipient);
        // Lock recipient
        wallet.setRecipientLocked();
        // Try to set recipient again
        vm.expectRevert(ReturnTemporaryWallet.RecipientAddressLocked.selector);
        wallet.setRecipient(makeAddr("newRecipient"));
        vm.stopPrank();
    }

    function test_SetRecipient_CanSetBeforeLock() public {
        address newRecipient = makeAddr("newRecipient");
        vm.startPrank(owner);
        wallet.setRecipient(recipient);
        // Can still change before locking
        wallet.setRecipient(newRecipient);
        assertEq(wallet.recipient(), newRecipient, "Recipient should be updated");
        vm.stopPrank();
    }

    // setRecipientLocked tests
    function test_SetRecipientLocked_Success() public {
        vm.startPrank(owner);
        vm.expectEmit(true, false, false, false);
        emit RecipientLocked(owner);
        wallet.setRecipientLocked();
        vm.stopPrank();

        assertTrue(wallet.recipientLocked(), "Recipient should be locked");
    }

    function test_SetRecipientLocked_RevertWhenNotOwner() public {
        vm.startPrank(nonOwner);
        vm.expectRevert();
        wallet.setRecipientLocked();
        vm.stopPrank();
    }

    function test_SetRecipientLocked_CanCallMultipleTimes() public {
        vm.startPrank(owner);
        wallet.setRecipientLocked();
        assertTrue(wallet.recipientLocked(), "Recipient should be locked after first call");
        // Can call again (idempotent)
        wallet.setRecipientLocked();
        assertTrue(wallet.recipientLocked(), "Recipient should still be locked after second call");
        vm.stopPrank();
    }

    // transferToken tests
    function test_TransferToken_Success() public {
        // Set recipient first
        vm.startPrank(owner);
        wallet.setRecipient(recipient);
        vm.stopPrank();

        uint256 initialRecipientBalance = token.balanceOf(recipient);
        uint256 initialWalletBalance = token.balanceOf(address(wallet));

        vm.startPrank(owner);
        wallet.transferToken(address(token), TRANSFER_AMOUNT);
        vm.stopPrank();

        assertEq(
            token.balanceOf(recipient),
            initialRecipientBalance + TRANSFER_AMOUNT,
            "Recipient should receive tokens"
        );
        assertEq(
            token.balanceOf(address(wallet)),
            initialWalletBalance - TRANSFER_AMOUNT,
            "Wallet should have tokens deducted"
        );
    }

    function test_TransferToken_RevertWhenNotOwner() public {
        vm.startPrank(owner);
        wallet.setRecipient(recipient);
        vm.stopPrank();

        vm.startPrank(nonOwner);
        vm.expectRevert();
        wallet.transferToken(address(token), TRANSFER_AMOUNT);
        vm.stopPrank();
    }

    function test_TransferToken_RevertWhenRecipientNotSet() public {
        vm.startPrank(owner);
        vm.expectRevert(ReturnTemporaryWallet.RecipientNotSet.selector);
        wallet.transferToken(address(token), TRANSFER_AMOUNT);
        vm.stopPrank();
    }

    function test_TransferToken_RevertWhenZeroTokenAddress() public {
        vm.startPrank(owner);
        wallet.setRecipient(recipient);
        vm.expectRevert(ReturnTemporaryWallet.ZeroAddressNotAllowed.selector);
        wallet.transferToken(zeroAddress, TRANSFER_AMOUNT);
        vm.stopPrank();
    }

    function test_TransferToken_CanTransferMultipleTimes() public {
        vm.startPrank(owner);
        wallet.setRecipient(recipient);
        vm.stopPrank();

        uint256 amount1 = 500 * 10 ** 18;
        uint256 amount2 = 300 * 10 ** 18;

        vm.startPrank(owner);
        wallet.transferToken(address(token), amount1);
        wallet.transferToken(address(token), amount2);
        vm.stopPrank();

        assertEq(
            token.balanceOf(recipient),
            amount1 + amount2,
            "Recipient should receive all transferred tokens"
        );
    }

    function test_TransferToken_CanTransferFullBalance() public {
        vm.startPrank(owner);
        wallet.setRecipient(recipient);
        uint256 walletBalance = token.balanceOf(address(wallet));
        wallet.transferToken(address(token), walletBalance);
        vm.stopPrank();

        assertEq(token.balanceOf(address(wallet)), 0, "Wallet should have zero balance");
        assertEq(token.balanceOf(recipient), INITIAL_TOKEN_BALANCE, "Recipient should receive all tokens");
    }

    // Integration tests
    function test_CompleteFlow_SetRecipientLockAndTransfer() public {
        vm.startPrank(owner);
        // Set recipient
        wallet.setRecipient(recipient);
        assertEq(wallet.recipient(), recipient, "Recipient should be set");
        assertFalse(wallet.recipientLocked(), "Recipient should not be locked yet");

        // Lock recipient
        wallet.setRecipientLocked();
        assertTrue(wallet.recipientLocked(), "Recipient should be locked");

        // Transfer tokens
        wallet.transferToken(address(token), TRANSFER_AMOUNT);
        assertEq(
            token.balanceOf(recipient),
            TRANSFER_AMOUNT,
            "Recipient should receive tokens"
        );
        vm.stopPrank();
    }

    function test_TransferToken_AfterLocking() public {
        vm.startPrank(owner);
        wallet.setRecipient(recipient);
        wallet.setRecipientLocked();
        // Can still transfer after locking
        wallet.transferToken(address(token), TRANSFER_AMOUNT);
        vm.stopPrank();

        assertEq(token.balanceOf(recipient), TRANSFER_AMOUNT, "Transfer should work after locking");
    }
}

