// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 fundmera.com

// https://github.com/merafund
pragma solidity ^0.8.29;

import {DataTypes} from "../utils/DataTypes.sol";

contract MockMainVault {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    mapping(address => bool) public roles;
    mapping(address => bool) public availableRouters;
    mapping(address => bool) public availableTokens;

    bool public _paused;
    uint256 public feePercentage;
    uint256 public profitLockedUntil;
    address public profitWallet;
    address public feeWallet;
    address public currentImplementationOfInvestmentVault;
    address private _meraPriceOracle;
    bool public isCanceledOracleCheck;
    uint32 public currentFixedProfitPercent;
    DataTypes.ProfitType public profitType;

    constructor() {
        roles[msg.sender] = true;
        feePercentage = 1000;
        profitWallet = address(0x123);
        feeWallet = address(0x456);
        currentImplementationOfInvestmentVault = address(0);
        _meraPriceOracle = address(0);
        isCanceledOracleCheck = true;
        currentFixedProfitPercent = 2000;
        profitType = DataTypes.ProfitType.Dynamic;
    }

    function hasRole(bytes32, /* role */ address account) external view returns (bool) {
        return roles[account];
    }

    function setRole(address account, bool hasRole) external {
        roles[account] = hasRole;
    }

    function paused() external view returns (bool) {
        return _paused;
    }

    function setPaused(bool paused_) external {
        _paused = paused_;
    }

    function setFeePercentage(uint256 _feePercentage) external {
        feePercentage = _feePercentage;
    }

    function setAvailableRouter(address router, bool available) external {
        availableRouters[router] = available;
    }

    function availableRouterByAdmin(address router) external view returns (bool) {
        return availableRouters[router];
    }

    function setAvailableToken(address token, bool available) external {
        availableTokens[token] = available;
    }

    function availableTokensByAdmin(address token) external view returns (bool) {
        return availableTokens[token];
    }

    function availableRouterByInvestor(address router) external view returns (bool) {
        return availableRouters[router];
    }

    function availableTokensByInvestor(address token) external view returns (bool) {
        return availableTokens[token];
    }

    function setProfitLock(uint256 lockUntil) external {
        profitLockedUntil = lockUntil;
    }

    function setCurrentImplementation(address impl) external {
        currentImplementationOfInvestmentVault = impl;
    }

    function setMeraPriceOracle(address oracle) external {
        _meraPriceOracle = oracle;
    }

    function setIsCanceledOracleCheck(bool isCanceled) external {
        isCanceledOracleCheck = isCanceled;
    }

    function meraPriceOracle() external view returns (address) {
        return _meraPriceOracle;
    }

    function setCurrentFixedProfitPercent(uint32 percent) external {
        currentFixedProfitPercent = percent;
    }

    function setProfitType(DataTypes.ProfitType type_) external {
        profitType = type_;
    }
}
