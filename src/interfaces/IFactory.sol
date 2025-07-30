// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 fundmera.com

// https://github.com/merafund
pragma solidity ^0.8.29;

/// @title IFactory
/// @dev Interface for the Factory contract
interface IFactory {
    error CallerIsNotDeployer();
    error InvalidReferralCode();
    error ZeroAddress();
    error ReferralCodeAlreadyUsed();

    // Structure to hold constructor parameters to avoid stack too deep
    struct ConstructorParams {
        // MainVault parameters
        address mainVaultImplementation;
        address investmentVaultImplementation;
        address manager;
        address admin;
        address backupAdmin;
        address emergencyAdmin;
        uint256 feePercentage;
        address pauserList;
        // AgentDistribution parameters
        address agentDistributionImplementation;
        address fundWallet;
        address defaultAgentWallet;
        address meraCapitalWallet;
        address meraPriceOracle;
    }

    event MainVaultCreated(
        address indexed mainVaultProxy,
        address indexed mainInvestor,
        address indexed creator,
        address backupInvestor,
        address emergencyInvestor,
        address profitWallet,
        string referralCode
    );

    event DistributionContractCreated(address indexed proxyAddress, string referralCode, address agentWallet);
    event ReferralCodeRegistered(string indexed referralCode, address indexed agentDistribution);
    event DefaultAgentDistributionCreated(address indexed proxyAddress, address agentWallet);
    event FounderWalletUpdated(address indexed oldFundWallet, address indexed newFundWallet);
    event MeraCapitalWalletUpdated(address indexed oldMeraCapitalWallet, address indexed newMeraCapitalWallet);
    event DeployerUpdated(address indexed oldDeployer, address indexed newDeployer);
    event MeraPriceOracleUpdated(address indexed oldMeraPriceOracle, address indexed newMeraPriceOracle);
    /// @notice Creates a new MainVault instance
    /// @param mainInvestor The address of the main investor
    /// @param backupInvestor The address of the backup investor
    /// @param emergencyInvestor The address of the emergency investor
    /// @param profitWallet The address of the profit wallet
    /// @param referralCode The referral code to be used
    /// @return mainVaultProxy The address of the created MainVault proxy

    function createMainVault(
        address mainInvestor,
        address backupInvestor,
        address emergencyInvestor,
        address profitWallet,
        string calldata referralCode
    ) external returns (address mainVaultProxy);

    /// @notice Sets the deployer address
    /// @param _deployer The new deployer address
    function setDeployer(address _deployer) external;

    /// @notice Creates a new AgentDistributionProfit instance
    /// @param referralCode The referral code to be used
    /// @param agentWallet The address of the agent wallet
    /// @param reserveAgentWallet The address of the reserve agent wallet
    /// @param emergencyAgentWallet The address of the emergency agent wallet
    /// @return The address of the created AgentDistributionProfit proxy
    function createAgentDistribution(
        string calldata referralCode,
        address agentWallet,
        address reserveAgentWallet,
        address emergencyAgentWallet
    ) external returns (address);

    /// @notice Updates the implementation addresses
    /// @param newMainVaultImpl The new MainVault implementation address
    /// @param newInvestmentVaultImpl The new InvestmentVault implementation address
    /// @param newAgentDistributionImpl The new AgentDistribution implementation address
    function updateImplementations(
        address newMainVaultImpl,
        address newInvestmentVaultImpl,
        address newAgentDistributionImpl
    ) external;

    /// @notice Updates the fixed parameters for MainVault creation
    /// @param _manager The new manager address
    /// @param _admin The new admin address
    /// @param _backupAdmin The new backup admin address
    /// @param _emergencyAdmin The new emergency admin address
    /// @param _feePercentage The new fee percentage
    /// @param _pauserList The new pauser list address
    function updateMainVaultParameters(
        address _manager,
        address _admin,
        address _backupAdmin,
        address _emergencyAdmin,
        uint256 _feePercentage,
        address _pauserList
    ) external;

    /// @notice Updates fund wallet for all future AgentDistribution contracts
    /// @param _fundWallet The new fund wallet address
    /// @param _meraCapitalWallet The new Mera Capital wallet address
    function updateFundWallets(address _fundWallet, address _meraCapitalWallet) external;

    /// @notice Gets the AgentDistribution contract address for a referral code
    /// @param referralCode The referral code to query
    /// @return The address of the AgentDistribution contract
    function getAgentDistribution(string calldata referralCode) external view returns (address);

    /// @notice Gets the referral code for an AgentDistribution contract
    /// @param agentDistribution The address of the AgentDistribution contract
    /// @return The referral code associated with the contract
    function getReferralCode(address agentDistribution) external view returns (string memory);

    /// @notice Sets the Mera Price Oracle
    /// @param _meraPriceOracle The new Mera Price Oracle address
    function setMeraPriceOracle(address _meraPriceOracle) external;
}
