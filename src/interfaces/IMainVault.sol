// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 fundmera.com

// https://github.com/merafund
pragma solidity ^0.8.29;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IInvestmentVault} from "./IInvestmentVault.sol";
import {IMultiAdminSingleHolderAccessControl} from "./IMultiAdminSingleHolderAccessControl.sol";
import {IERC5267} from "@openzeppelin/contracts/interfaces/IERC5267.sol";
import {IPauserList} from "./IPauserList.sol";
import {Constants} from "../utils/Constants.sol";
import {DataTypes} from "../utils/DataTypes.sol";
import {IMeraPriceOracle} from "./IMeraPriceOracle.sol";

/// @title IMainVault
/// @dev Interface for Main Vault
interface IMainVault is IMultiAdminSingleHolderAccessControl, IERC5267 {
    function paused() external view returns (bool);

    /// @dev Main investor role
    function MAIN_INVESTOR_ROLE() external view returns (bytes32);

    /// @dev Backup investor role
    function BACKUP_INVESTOR_ROLE() external view returns (bytes32);

    /// @dev Emergency investor role
    function EMERGENCY_INVESTOR_ROLE() external view returns (bytes32);

    /// @dev Manager role
    function MANAGER_ROLE() external view returns (bytes32);

    /// @dev Admin role
    function ADMIN_ROLE() external view returns (bytes32);

    /// @dev Backup admin role
    function BACKUP_ADMIN_ROLE() external view returns (bytes32);

    /// @dev Emergency admin role
    function EMERGENCY_ADMIN_ROLE() external view returns (bytes32);

    /// @dev Emitted when the contract is locked
    event ContractLocked(address indexed locker);

    /// @dev Emitted when the contract is unlocked
    event ContractUnlocked(address indexed unlocker);

    /// @dev Emitted when a token's availability is changed by an investor
    event TokenAvailabilityByInvestorChanged(address indexed token, bool isAvailable);

    /// @dev Emitted when a router's availability is changed by an investor
    event RouterAvailabilityByInvestorChanged(address indexed router, bool isAvailable);

    /// @dev Emitted when a token's availability is changed by an admin
    event TokenAvailabilityByAdminChanged(address indexed token, bool isAvailable);

    /// @dev Emitted when a router's availability is changed by an admin
    event RouterAvailabilityByAdminChanged(address indexed router, bool isAvailable);

    /// @dev Emitted when a lock period's availability is changed
    event LockPeriodAvailabilityChanged(uint256 indexed period, bool isAvailable);

    /// @dev Emitted when a withdrawal lock is set
    event WithdrawalLockSet(uint256 period, uint64 newLockTimestamp);

    /// @dev Emitted when withdrawal lock is removed because the same address has both
    /// EMERGENCY_INVESTOR_ROLE and BACKUP_ADMIN_ROLE
    event WithdrawalLockRemovedBySpecialRole(address indexed account);

    /// @dev Emitted when auto-renewal of withdrawal lock is enabled or disabled
    event AutoRenewWithdrawalLockSet(bool oldValue, bool newValue);

    /// @dev Emitted when withdrawal lock is automatically renewed
    event WithdrawalLockAutoRenewed(uint64 newLockTimestamp);

    /// @dev Emitted when withdraw commit timestamp is set
    event WithdrawCommitTimestampSet(uint64 timestamp);

    /// @dev Emitted when a future implementation for Main Vault is set
    event FutureMainVaultImplementationSet(address indexed implementation, uint64 deadline);

    /// @dev Emitted when a future implementation for Investor Vault is set
    event FutureInvestorVaultImplementationSet(address indexed implementation, uint64 deadline);

    /// @dev Emitted when profit wallet address is changed
    event ProfitWalletSet(address indexed oldWallet, address indexed newWallet);

    /// @dev Emitted when fee wallet address is changed
    event FeeWalletSet(address indexed oldWallet, address indexed newWallet);

    /// @dev Emitted when fee percentage is changed
    event FeePercentageChanged(uint256 oldPercentage, uint256 newPercentage);

    /// @dev Emitted when current implementation of investment vault is changed
    event CurrentImplementationOfInvestmentVaultSet(
        address indexed oldImplementation, address indexed newImplementation
    );

    /// @dev Emitted when tokens are deposited into the vault
    event Deposited(address indexed token, address indexed sender, uint256 amount);

    /// @dev Emitted when tokens are withdrawn from the vault
    event Withdrawn(address indexed token, address indexed receiver, uint256 amount);

    /// @dev Emitted when an exact amount of tokens is swapped for another token
    event ExactTokensSwapped(
        address indexed router, address indexed fromToken, address indexed toToken, uint256 amountIn, uint256 amountOut
    );

    /// @dev Emitted when tokens are swapped for an exact amount of output tokens
    event TokensSwappedForExact(
        address indexed router, address indexed fromToken, address indexed toToken, uint256 amountIn, uint256 amountOut
    );

    /// @dev Emitted when a new Investment Vault is deployed
    event InvestmentVaultDeployed(
        address indexed vaultAddress, address indexed tokenMI, uint256 initDeposit, uint256 vaultId
    );

    /// @dev Emitted when exactInputSingle is executed
    event ExactInputSingleExecuted(
        address indexed router, address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut
    );

    /// @dev Emitted when exactInput is executed
    event ExactInputExecuted(
        address indexed router, address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut
    );

    /// @dev Emitted when exactOutputSingle is executed
    event ExactOutputSingleExecuted(
        address indexed router, address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut
    );

    /// @dev Emitted when exactOutput is executed
    event ExactOutputExecuted(
        address indexed router, address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut
    );

    /// @dev Emitted when exactInputSingleDelegate is executed
    event ExactInputSingleDelegateExecuted(
        address indexed router, address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut
    );

    /// @dev Emitted when exactInputDelegate is executed
    event ExactInputDelegateExecuted(
        address indexed router, address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut
    );

    /// @dev Emitted when exactOutputSingleDelegate is executed
    event ExactOutputSingleDelegateExecuted(
        address indexed router, address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut
    );

    /// @dev Emitted when exactOutputDelegate is executed
    event ExactOutputDelegateExecuted(
        address indexed router, address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut
    );

    /// @dev Emitted when tokens are withdrawn from investment vault
    event WithdrawnFromInvestmentVault(
        address indexed vault, address indexed token, uint256 amount, address indexed receiver
    );

    /// @dev Emitted when current fixed profit percent is set
    event CurrentFixedProfitPercentSet(uint32 oldPercent, uint32 newPercent);

    /// @dev Emitted when profit type is set
    event ProfitTypeSet(DataTypes.ProfitType profitType);

    /// @dev Emitted when proposed fixed profit percent is set by admin
    event ProposedFixedProfitPercentByAdminSet(uint32 percent);

    /// @dev Initialization struct to prevent stack too deep errors
    struct InitParams {
        address mainInvestor;
        address backupInvestor;
        address emergencyInvestor;
        address manager;
        address admin;
        address backupAdmin;
        address emergencyAdmin;
        address feeWallet;
        address profitWallet;
        uint256 feePercentage;
        address currentImplementationOfInvestmentVault;
        address pauserList;
        address meraPriceOracle;
    }

    /// @dev Token availability configuration struct
    struct TokenAvailability {
        address token;
        bool isAvailable;
    }

    /// @dev Router availability configuration struct
    struct RouterAvailability {
        address router;
        bool isAvailable;
    }

    /// @dev Lock period availability configuration struct
    struct LockPeriodAvailability {
        uint256 period;
        bool isAvailable;
    }

    /// @dev Future Main Vault Implementation configuration struct
    struct FutureMainVaultImplementation {
        address implementation;
        uint64 deadline;
    }

    /// @dev Future Investor Vault Implementation configuration struct
    struct FutureInvestorVaultImplementation {
        address implementation;
        uint64 deadline;
    }

    /// @dev Get token availability by investor
    /// @param token Token address to check
    /// @return isAvailable True if token is available for investor
    function availableTokensByInvestor(address token) external view returns (bool);

    /// @dev Get router availability by investor
    /// @param router Router address to check
    /// @return isAvailable True if router is available for investor
    function availableRouterByInvestor(address router) external view returns (bool);

    /// @dev Get token availability by admin
    /// @param token Token address to check
    /// @return isAvailable True if token is available for admin
    function availableTokensByAdmin(address token) external view returns (bool);

    /// @dev Get router availability by admin
    /// @param router Router address to check
    /// @return isAvailable True if router is available for admin
    function availableRouterByAdmin(address router) external view returns (bool);

    /// @dev Get lock period availability
    /// @param period Lock period to check
    /// @return isAvailable True if lock period is available
    function availableLock(uint256 period) external view returns (bool);

    /// @dev Get investment vault address by ID
    /// @param id Investment vault ID
    /// @return vaultAddress Address of the investment vault
    function investmentVaults(uint256 id) external view returns (address);

    /// @dev Get total number of investment vaults
    /// @return count Total number of investment vaults
    function investmentVaultsCount() external view returns (uint256);

    /// @dev Get current fee percentage
    /// @return percentage Current fee percentage
    function feePercentage() external view returns (uint256);

    /// @dev Get fee wallet address
    /// @return wallet Fee wallet address
    function feeWallet() external view returns (address);

    /// @dev Get profit wallet address
    /// @return wallet Profit wallet address
    function profitWallet() external view returns (address);

    /// @dev Get timestamp until profit is locked
    /// @return timestamp Timestamp until profit is locked
    function profitLockedUntil() external view returns (uint64);

    /// @dev Get timestamp until withdrawals are locked
    /// @return timestamp Timestamp until withdrawals are locked
    function withdrawalLockedUntil() external view returns (uint64);

    /// @dev Get current implementation of investment vault
    /// @return implementation Current implementation address
    function currentImplementationOfInvestmentVault() external view returns (address);

    /// @dev Get next future implementation of main vault
    /// @return implementation Next implementation address
    function nextFutureImplementationOfMainVault() external view returns (address);

    /// @dev Get deadline for next future implementation of main vault
    /// @return deadline Deadline timestamp
    function nextFutureImplementationOfMainVaultDeadline() external view returns (uint64);

    /// @dev Get next future implementation of investor vault
    /// @return implementation Next implementation address
    function nextFutureImplementationOfInvestorVault() external view returns (address);

    /// @dev Manually triggers the withdrawal lock renewal check
    /// @dev Can only be called by admin to force check and potentially renew the withdrawal lock
    /// @return renewed True if the lock was renewed, false otherwise
    function checkAndRenewWithdrawalLock() external returns (bool renewed);

    /// @dev Get deadline for next future implementation of investor vault
    /// @return deadline Deadline timestamp
    function nextFutureImplementationOfInvestorVaultDeadline() external view returns (uint64);

    /// @dev Sets availability status for multiple tokens by investor
    /// @param configs Array of token availability configurations
    function setTokenAvailabilityByInvestor(TokenAvailability[] calldata configs) external;

    /// @dev Sets availability status for multiple routers by investor
    /// Always sets availability to true, can't be set to false
    /// @param routers Array of router addresses to enable
    function setRouterAvailabilityByInvestor(address[] calldata routers) external;

    /// @dev Sets availability status for multiple tokens by admin
    /// @param configs Array of token availability configurations
    function setTokenAvailabilityByAdmin(TokenAvailability[] calldata configs) external;

    /// @dev Sets availability status for multiple routers by admin
    /// @param configs Array of router availability configurations
    function setRouterAvailabilityByAdmin(RouterAvailability[] calldata configs) external;

    /// @dev Sets availability status for multiple lock periods
    /// Only admin can call this function
    /// @param configs Array of lock period availability configurations
    function setLockPeriodsAvailability(LockPeriodAvailability[] calldata configs) external;

    /// @dev Sets the future implementation of the Main Vault
    /// Only admin can call this function, and it requires a valid signature from the main investor
    ///
    /// @param futureImplementation Structure containing the implementation address and deadline
    /// @param signature EIP-712 signature from the main investor
    function setFutureMainVaultImplementation(
        FutureMainVaultImplementation calldata futureImplementation,
        bytes calldata signature
    ) external;

    /// @dev Sets the future implementation of the Investor Vault
    /// Only admin can call this function, and it requires a valid signature from the main investor
    ///
    /// @param futureImplementation Structure containing the implementation address and deadline
    /// @param signature EIP-712 signature from the main investor
    function setFutureInvestorVaultImplementation(
        FutureInvestorVaultImplementation calldata futureImplementation,
        bytes calldata signature
    ) external;

    /// @dev Sets the profit wallet address
    /// Only the main investor can call this function
    /// Profit withdrawal will be locked for at least 7 days
    ///
    /// @param wallet New profit wallet address
    function setProfitWallet(address wallet) external;

    /// @dev Sets the current implementation of the Investment Vault
    /// Only admin can call this function
    /// The new implementation must match the previously set nextFutureImplementationOfInvestorVault
    /// and current time must not exceed nextFutureImplementationOfInvestorVaultDeadline
    /// After setting, nextFutureImplementationOfInvestorVault and nextFutureImplementationOfInvestorVaultDeadline are reset
    ///
    /// @param implementation New implementation address
    function setCurrentImplementationOfInvestmentVault(address implementation) external;

    /// @dev Deposits tokens into the vault
    /// Can only be called for tokens approved by both investor and admin
    ///
    /// @param token Token to deposit
    /// @param amount Amount of tokens to deposit
    function deposit(IERC20 token, uint256 amount) external;

    /// @dev Withdraws tokens from the vault
    /// Tokens are sent to the sender's address
    /// Can only be called when withdrawals are not locked
    ///
    /// @param token Token to withdraw
    /// @param amount Amount of tokens to withdraw
    function withdraw(IERC20 token, uint256 amount) external;

    /// @dev Swaps an exact amount of input tokens for as many output tokens as possible using Uniswap
    /// Only the main investor can call this function
    /// Router must be in the list of available routers
    /// First and last tokens in the path must be in the list of available tokens
    ///
    /// @param router The Uniswap router address to use
    /// @param amountIn The amount of input tokens to send
    /// @param amountOutMin The minimum amount of output tokens to receive
    /// @param path An array of token addresses representing the swap path
    /// @param deadline Unix timestamp after which the transaction will revert
    /// @return amounts The input token amount and all subsequent output token amounts
    function swapExactTokensForTokens(
        address router,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    /// @dev Swaps tokens for an exact amount of output tokens using Uniswap
    /// Only the main investor can call this function
    /// Router must be in the list of available routers
    /// First and last tokens in the path must be in the list of available tokens
    ///
    /// @param router The Uniswap router address to use
    /// @param amountOut The exact amount of output tokens to receive
    /// @param amountInMax The maximum amount of input tokens to send
    /// @param path An array of token addresses representing the swap path
    /// @param deadline Unix timestamp after which the transaction will revert
    /// @return amounts The input token amount and all subsequent output token amounts
    function swapTokensForExactTokens(
        address router,
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    /// @dev Deploys a new Investment Vault using the current implementation
    /// Only admin can call this function
    /// Uses the current implementation to deploy a proxy
    /// Transfers tokenMI in the amount of initDeposit to the new vault
    /// Initializes the vault with the provided data
    ///
    /// @param initData Initialization data for the new Investment Vault
    /// @return vaultAddress The address of the deployed Investment Vault
    /// @return vaultId The ID of the deployed Investment Vault
    function deployInvestmentVault(DataTypes.InvestmentVaultInitData calldata initData)
        external
        returns (address vaultAddress, uint256 vaultId);

    /// @dev Data structure for withdrawing tokens from investment vaults
    struct WithdrawFromVaultData {
        uint256 vaultIndex;
        IERC20 token;
        uint256 amount;
    }

    /// @dev Withdraws tokens from multiple investment vaults
    /// Only the main investor can call this function
    ///
    /// @param withdrawals Array of withdrawal requests containing vault index, token, and amount
    function withdrawFromInvestmentVaults(WithdrawFromVaultData[] calldata withdrawals) external;

    /// @dev Swaps an exact amount of `tokenIn` for as much as possible of `tokenOut`, receiving tokens to this contract
    /// @param params The simplified parameters necessary for the swap
    /// @return amountOut The amount of the received token
    function exactInputSingle(DataTypes.DelegateExactInputSingleParams calldata params)
        external
        returns (uint256 amountOut);

    /// @dev Swaps an exact amount of tokens for as many as possible along the specified path, receiving tokens to this contract
    /// @param params The simplified parameters necessary for the multi-hop swap
    /// @return amountOut The amount of the received token
    function exactInput(DataTypes.DelegateExactInputParams calldata params) external returns (uint256 amountOut);

    /// @dev Swaps as little as possible of one token for an exact amount of another token, receiving tokens to this contract
    /// @param params The simplified parameters necessary for the swap
    /// @return amountIn The amount of the input token
    function exactOutputSingle(DataTypes.DelegateExactOutputSingleParams calldata params)
        external
        returns (uint256 amountIn);

    /// @dev Swaps as little as possible of one token for an exact amount along the specified path, receiving tokens to this contract
    /// @param params The simplified parameters necessary for the multi-hop swap
    /// @return amountIn The amount of the input token
    function exactOutput(DataTypes.DelegateExactOutputParams calldata params) external returns (uint256 amountIn);

    /// @dev Get if auto-renewal of withdrawal lock is enabled
    /// @return enabled True if auto-renewal is enabled
    function autoRenewWithdrawalLock() external view returns (bool);

    /// @dev Sets a withdrawal lock for a specified period
    /// Only the main investor can call this function
    /// The period must be in the list of available lock periods
    ///
    /// @param period Lock period in seconds
    function setWithdrawalLock(uint256 period) external;

    /// @dev Sets whether withdrawal lock should automatically renew
    /// When enabled, the lock will be renewed for 365 days when it's within 7 days of expiry
    /// Only the main investor can call this function
    ///
    /// @param enabled Whether auto-renewal should be enabled
    function setAutoRenewWithdrawalLock(bool enabled) external;

    /// @dev Sets a withdrawal lock for a specified period and configures auto-renewal
    /// Combines the functionality of setWithdrawalLock and setAutoRenewWithdrawalLock
    /// Only the main investor can call this function
    /// The period must be in the list of available lock periods
    ///
    /// @param period Lock period in seconds
    /// @param enabled Whether auto-renewal should be enabled
    function setWithdrawalLockWithAutoRenew(uint256 period, bool enabled) external;

    /// @dev Commits to withdraw from investment vaults after a delay
    /// Only the main investor can call this function
    /// The timestamp will be set to block.timestamp + WITHDRAW_COMMIT_MIN_DELAY
    function commitWithdrawFromInvestmentVault() external;

    /// @dev Get PauserList contract address
    /// @return PauserList contract address
    function pauserList() external view returns (IPauserList);

    /// @dev Get MeraPriceOracle contract address
    /// @return MeraPriceOracle contract address
    function meraPriceOracle() external view returns (IMeraPriceOracle);

    /// @dev Get if investor is canceled oracle check
    /// @return isCanceled True if investor is canceled oracle check
    function investorIsCanceledOracleCheck() external view returns (bool);

    /// @dev Get if admin is canceled oracle check
    /// @return isCanceled True if admin is canceled oracle check
    function adminIsCanceledOracleCheck() external view returns (bool);

    /// @dev Get if oracle check is canceled
    /// @return isCanceled True if oracle check is canceled
    function isCanceledOracleCheck() external view returns (bool);

    /// @dev Set if investor is canceled oracle check
    /// @param value True if investor is canceled oracle check
    function setInvestorIsCanceledOracleCheck(bool value) external;

    /// @dev Set if admin is canceled oracle check
    /// @param value True if admin is canceled oracle check
    function setAdminIsCanceledOracleCheck(bool value) external;

    /// @dev Sets the current fixed profit percent if proposed values from admin and main investor match
    /// @dev Can be called by either admin or main investor
    function setCurrentFixedProfitPercent() external;

    /// @dev Sets the profit type
    /// @param _profitType The new profit type to set
    function setProfitType(DataTypes.ProfitType _profitType) external;

    /// @dev Sets the proposed fixed profit percent by admin
    /// @param _proposedFixedProfitPercent The proposed fixed profit percent
    function setProposedFixedProfitPercentByAdmin(uint32 _proposedFixedProfitPercent) external;

    /// @dev Get current fixed profit percent
    /// @return percent Current fixed profit percent
    function currentFixedProfitPercent() external view returns (uint32);

    /// @dev Get profit type
    /// @return profitType Profit type
    function profitType() external view returns (DataTypes.ProfitType);
}
