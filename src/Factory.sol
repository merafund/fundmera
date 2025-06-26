// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 fundmera.com

// https://github.com/merafund
pragma solidity ^0.8.29;

import {MainVault} from "./MainVault.sol";
import {IMainVault} from "./interfaces/IMainVault.sol";
import {AgentDistributionProfit} from "./AgentDistributionProfit.sol";
import {IAgentDistributionProfit} from "./interfaces/IAgentDistributionProfit.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IFactory} from "./interfaces/IFactory.sol";

/// @title Factory
/// @dev Factory contract for deploying both MainVault and AgentDistributionProfit instances
contract Factory is IFactory, Ownable {
    // MainVault implementation and fixed parameters
    address public mainVaultImplementation;
    address public investmentVaultImplementation;
    address public manager;
    address public admin;
    address public backupAdmin;
    address public emergencyAdmin;
    uint256 public feePercentage;
    address public pauserList;
    address public meraCapitalWallet;
    address public meraPriceOracle;
    // AgentDistributionProfit implementation and default instance
    address public agentDistributionImplementation;
    address public defaultAgentDistribution;
    string public constant DEFAULT_REFERRAL_CODE = "DEFAULT";

    // Common fund wallet for all AgentDistribution contracts
    address public fundWallet;
    address public immutable defaultAgentWallet;

    // Referral code mapping
    mapping(string => address) public referralToAgentDistribution;
    mapping(address => string) public agentDistributionToReferral;

    address public deployer;

    constructor(ConstructorParams memory params) Ownable(msg.sender) {
        deployer = msg.sender;
        require(params.mainVaultImplementation != address(0), ZeroAddress());
        require(params.investmentVaultImplementation != address(0), ZeroAddress());
        require(params.manager != address(0), ZeroAddress());
        require(params.admin != address(0), ZeroAddress());
        require(params.backupAdmin != address(0), ZeroAddress());
        require(params.emergencyAdmin != address(0), ZeroAddress());
        require(params.pauserList != address(0), ZeroAddress());
        require(params.agentDistributionImplementation != address(0), ZeroAddress());
        require(params.fundWallet != address(0), ZeroAddress());
        require(params.defaultAgentWallet != address(0), ZeroAddress());

        mainVaultImplementation = params.mainVaultImplementation;
        investmentVaultImplementation = params.investmentVaultImplementation;
        manager = params.manager;
        admin = params.admin;
        backupAdmin = params.backupAdmin;
        emergencyAdmin = params.emergencyAdmin;
        feePercentage = params.feePercentage;
        pauserList = params.pauserList;
        agentDistributionImplementation = params.agentDistributionImplementation;
        fundWallet = params.fundWallet;
        defaultAgentWallet = params.defaultAgentWallet;
        meraCapitalWallet = params.meraCapitalWallet;
        meraPriceOracle = params.meraPriceOracle;
        // Deploy default AgentDistribution
        bytes memory initData = abi.encodeWithSelector(
            AgentDistributionProfit.initialize.selector,
            params.fundWallet,
            params.defaultAgentWallet,
            params.admin,
            params.emergencyAdmin,
            params.backupAdmin,
            params.emergencyAdmin, // Using emergencyAdmin as emergencyAgent for default distribution
            params.backupAdmin, // Using backupAdmin as reserveAgent for default distribution
            params.meraCapitalWallet
        );

        ERC1967Proxy proxy = new ERC1967Proxy(params.agentDistributionImplementation, initData);
        defaultAgentDistribution = address(proxy);

        // Register default referral code
        referralToAgentDistribution[DEFAULT_REFERRAL_CODE] = defaultAgentDistribution;
        agentDistributionToReferral[defaultAgentDistribution] = DEFAULT_REFERRAL_CODE;

        emit DefaultAgentDistributionCreated(defaultAgentDistribution, params.defaultAgentWallet);
        emit ReferralCodeRegistered(DEFAULT_REFERRAL_CODE, defaultAgentDistribution);
    }

    modifier onlyDeployer() {
        require(msg.sender == deployer, CallerIsNotDeployer());
        _;
    }

    modifier validReferralCode(string memory referralCode) {
        require(bytes(referralCode).length > 0, InvalidReferralCode());
        _;
    }

    /// @inheritdoc IFactory
    function createMainVault(
        address mainInvestor,
        address backupInvestor,
        address emergencyInvestor,
        address profitWallet,
        string calldata referralCode
    ) external returns (address mainVaultProxy) {
        require(mainInvestor != address(0), ZeroAddress());
        require(backupInvestor != address(0), ZeroAddress());
        require(emergencyInvestor != address(0), ZeroAddress());

        // Get profit wallet from referral code or use default
        address feeWallet = referralToAgentDistribution[referralCode];
        if (feeWallet == address(0)) {
            feeWallet = defaultAgentDistribution;
        }

        // Prepare initialization parameters
        IMainVault.InitParams memory initParams = IMainVault.InitParams({
            mainInvestor: mainInvestor,
            backupInvestor: backupInvestor,
            emergencyInvestor: emergencyInvestor,
            manager: manager,
            admin: admin,
            backupAdmin: backupAdmin,
            emergencyAdmin: emergencyAdmin,
            feeWallet: feeWallet,
            profitWallet: profitWallet,
            feePercentage: feePercentage,
            currentImplementationOfInvestmentVault: investmentVaultImplementation,
            pauserList: pauserList,
            meraPriceOracle: meraPriceOracle
        });

        // Encode initialization call
        bytes memory initData = abi.encodeWithSelector(MainVault.initialize.selector, initParams);

        // Deploy proxy
        ERC1967Proxy newProxy = new ERC1967Proxy(mainVaultImplementation, initData);
        mainVaultProxy = address(newProxy);

        // Use actual referral code or DEFAULT if not found
        string memory usedReferralCode = feeWallet == defaultAgentDistribution ? DEFAULT_REFERRAL_CODE : referralCode;

        emit MainVaultCreated(
            mainVaultProxy, mainInvestor, msg.sender, backupInvestor, emergencyInvestor, profitWallet, usedReferralCode
        );

        return mainVaultProxy;
    }

    /// @inheritdoc IFactory
    function setDeployer(address _deployer) external onlyOwner {
        require(_deployer != address(0), ZeroAddress());
        deployer = _deployer;
        emit DeployerUpdated(msg.sender, _deployer);
    }

    /// @inheritdoc IFactory
    function createAgentDistribution(
        string calldata referralCode,
        address agentWallet,
        address reserveAgentWallet,
        address emergencyAgentWallet
    ) external onlyDeployer validReferralCode(referralCode) returns (address) {
        require(agentWallet != address(0), ZeroAddress());
        require(reserveAgentWallet != address(0), ZeroAddress());
        require(emergencyAgentWallet != address(0), ZeroAddress());
        require(referralToAgentDistribution[referralCode] == address(0), ReferralCodeAlreadyUsed());

        // Encode initialization call
        bytes memory initData = abi.encodeWithSelector(
            AgentDistributionProfit.initialize.selector,
            fundWallet,
            agentWallet,
            admin,
            emergencyAdmin,
            backupAdmin,
            emergencyAgentWallet,
            reserveAgentWallet,
            meraCapitalWallet
        );

        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(agentDistributionImplementation, initData);
        address proxyAddress = address(proxy);

        // Register referral code
        referralToAgentDistribution[referralCode] = proxyAddress;
        agentDistributionToReferral[proxyAddress] = referralCode;

        emit DistributionContractCreated(proxyAddress, referralCode, agentWallet);
        emit ReferralCodeRegistered(referralCode, proxyAddress);

        return proxyAddress;
    }

    /// @inheritdoc IFactory
    function updateImplementations(
        address newMainVaultImpl,
        address newInvestmentVaultImpl,
        address newAgentDistributionImpl
    ) external onlyOwner {
        if (newMainVaultImpl != address(0)) {
            mainVaultImplementation = newMainVaultImpl;
        }
        if (newInvestmentVaultImpl != address(0)) {
            investmentVaultImplementation = newInvestmentVaultImpl;
        }
        if (newAgentDistributionImpl != address(0)) {
            agentDistributionImplementation = newAgentDistributionImpl;
        }
    }

    /// @inheritdoc IFactory
    function updateMainVaultParameters(
        address _manager,
        address _admin,
        address _backupAdmin,
        address _emergencyAdmin,
        uint256 _feePercentage,
        address _pauserList
    ) external onlyOwner {
        require(_manager != address(0), "Zero address not allowed");
        require(_admin != address(0), "Zero address not allowed");
        require(_backupAdmin != address(0), "Zero address not allowed");
        require(_emergencyAdmin != address(0), "Zero address not allowed");
        require(_pauserList != address(0), "Zero address not allowed");

        manager = _manager;
        admin = _admin;
        backupAdmin = _backupAdmin;
        emergencyAdmin = _emergencyAdmin;
        feePercentage = _feePercentage;
        pauserList = _pauserList;
    }

    /// @inheritdoc IFactory
    function updateFundWallets(address _fundWallet, address _meraCapitalWallet) external onlyOwner {
        require(_fundWallet != address(0), "Zero address not allowed");
        require(_meraCapitalWallet != address(0), "Zero address not allowed");
        address oldFundWallet = fundWallet;
        address oldMeraCapitalWallet = meraCapitalWallet;
        fundWallet = _fundWallet;
        meraCapitalWallet = _meraCapitalWallet;
        emit FounderWalletUpdated(oldFundWallet, _fundWallet);
        emit MeraCapitalWalletUpdated(oldMeraCapitalWallet, _meraCapitalWallet);
    }

    /// @inheritdoc IFactory
    function getAgentDistribution(string calldata referralCode) external view returns (address) {
        address distribution = referralToAgentDistribution[referralCode];
        return distribution != address(0) ? distribution : defaultAgentDistribution;
    }

    /// @inheritdoc IFactory
    function getReferralCode(address agentDistribution) external view returns (string memory) {
        return agentDistributionToReferral[agentDistribution];
    }
}
