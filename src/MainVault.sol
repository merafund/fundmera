// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 fundmera.com

// https://github.com/merafund
pragma solidity 0.8.29;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {MultiAdminSingleHolderAccessControlUppgradable} from
    "./utils/MultiAdminSingleHolderAccessControlUppgradable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {IMainVault} from "./interfaces/IMainVault.sol";
import {IUniswapV2Router02} from "./interfaces/IUniswapV2Router02.sol";
import {IInvestmentVault} from "./interfaces/IInvestmentVault.sol";
import {ISwapRouter} from "./interfaces/ISwapRouter.sol";
import {IPauserList} from "./interfaces/IPauserList.sol";
import {Constants} from "./utils/Constants.sol";
import {DataTypes} from "./utils/DataTypes.sol";
import {MainVaultSwapLibrary} from "./utils/MainVaultSwapLibrary.sol";
import {IMeraPriceOracle} from "./interfaces/IMeraPriceOracle.sol";
/// @title MainVault
/// @dev Main storage for tokens with UUPS upgrade support and role system

contract MainVault is
    Initializable,
    UUPSUpgradeable,
    MultiAdminSingleHolderAccessControlUppgradable,
    EIP712Upgradeable,
    PausableUpgradeable,
    IMainVault
{
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    // Custom Errors
    error InvalidSigner();
    error TimestampMustBeInTheFuture();
    error InvalidImplementationAddress();
    error InvalidImplementationDeadline();
    error ZeroAddressNotAllowed();
    error ExceedsMaximumPercentage();
    error TokenNotAvailable();
    error WithdrawalLocked();
    error InsufficientBalance();
    error ZeroAmountNotAllowed();
    error RouterNotAvailable();
    error InvalidMainVaultAddress();
    error InvalidVaultIndex();
    error LockPeriodNotAvailable();
    error NotPauser();
    error InitializePause();
    error WithdrawCommitTimestampExpired();
    // Role definitions
    // Each role is represented by a unique bytes32 value computed from the role name

    bytes32 public constant MAIN_INVESTOR_ROLE = keccak256("MAIN_INVESTOR_ROLE"); // Main investor role
    bytes32 public constant BACKUP_INVESTOR_ROLE = keccak256("BACKUP_INVESTOR_ROLE"); // Backup investor role
    bytes32 public constant EMERGENCY_INVESTOR_ROLE = keccak256("EMERGENCY_INVESTOR_ROLE"); // Emergency investor role
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE"); // Manager role
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE"); // Admin role
    bytes32 public constant BACKUP_ADMIN_ROLE = keccak256("BACKUP_ADMIN_ROLE"); // Backup admin role
    bytes32 public constant EMERGENCY_ADMIN_ROLE = keccak256("EMERGENCY_ADMIN_ROLE"); // Emergency admin role

    // EIP-712 Type Hashes
    bytes32 private constant _FUTURE_MAIN_VAULT_IMPLEMENTATION_TYPEHASH =
        keccak256("FutureMainVaultImplementation(address implementation,uint64 deadline)");

    bytes32 private constant _FUTURE_INVESTOR_VAULT_IMPLEMENTATION_TYPEHASH =
        keccak256("FutureInvestorVaultImplementation(address implementation,uint64 deadline)");

    // Allowed tokens and routers mappings
    mapping(address => bool) public availableTokensByInvestor;
    mapping(address => bool) public availableRouterByInvestor;

    mapping(address => bool) public availableTokensByAdmin;
    mapping(address => bool) public availableRouterByAdmin;
    mapping(uint256 => bool) public availableLock;

    mapping(uint256 => address) public investmentVaults;
    uint256 public investmentVaultsCount;

    uint256 public feePercentage;

    address public feeWallet;
    address public profitWallet;
    uint64 public profitLockedUntil; // Timestamp until profit is locked
    uint64 public withdrawalLockedUntil; // Timestamp until withdrawals are locked
    bool public autoRenewWithdrawalLock; // Flag indicating whether withdrawal lock should auto-renew

    address public currentImplementationOfInvestmentVault;

    // we can optimize this storage
    address public nextFutureImplementationOfMainVault;
    uint64 public nextFutureImplementationOfMainVaultDeadline;
    address public nextFutureImplementationOfInvestorVault;
    uint64 public nextFutureImplementationOfInvestorVaultDeadline;

    uint64 public withdrawCommitTimestamp;
    uint64 public pauseToTimestamp;

    bool public investorIsCanceledOracleCheck;
    bool public adminIsCanceledOracleCheck;

    DataTypes.ProfitType public profitType;
    uint32 public currentFixedProfitPercent;
    uint32 public proposedFixedProfitPercentByAdmin;

    IPauserList public pauserList;
    IMeraPriceOracle public meraPriceOracle;

    modifier isNotLocked() {
        require(!_isLock(), WithdrawalLocked());
        _;
    }

    modifier onlyPauser() {
        if (!pauserList.hasRole(pauserList.PAUSER_ROLE(), msg.sender)) {
            revert NotPauser();
        }
        _;
    }

    modifier IsNotAfterSetupPause() {
        require(block.timestamp > pauseToTimestamp, InitializePause());
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev Contract initialization with role assignment (replaces constructor in upgradeable contracts)
    /// @param params All initialization parameters packed into a struct to prevent stack too deep errors
    function initialize(InitParams calldata params) public virtual initializer {
        __UUPSUpgradeable_init();
        __AccessControl_init();
        __EIP712_init("MainVault", "1");
        __Pausable_init();

        // Set initial wallets and configuration
        feeWallet = params.feeWallet;
        profitWallet = params.profitWallet;
        feePercentage = params.feePercentage;
        currentImplementationOfInvestmentVault = params.currentImplementationOfInvestmentVault;
        autoRenewWithdrawalLock = false; // Default to no auto-renewal
        pauserList = IPauserList(params.pauserList);

        meraPriceOracle = IMeraPriceOracle(params.meraPriceOracle);

        if (params.meraPriceOracle == address(0)) {
            investorIsCanceledOracleCheck = true;
            adminIsCanceledOracleCheck = true;
        }

        availableLock[10 minutes] = true;
        availableLock[365 days] = true;

        currentFixedProfitPercent = 2000; // 20%

        // Assign initial roles to respective addresses
        // Due to our custom _grantRole implementation, only one address can have each role
        _grantRole(MAIN_INVESTOR_ROLE, params.mainInvestor);
        _grantRole(BACKUP_INVESTOR_ROLE, params.backupInvestor);
        _grantRole(EMERGENCY_INVESTOR_ROLE, params.emergencyInvestor);
        _grantRole(MANAGER_ROLE, params.manager);
        _grantRole(ADMIN_ROLE, params.admin);
        _grantRole(BACKUP_ADMIN_ROLE, params.backupAdmin);
        _grantRole(EMERGENCY_ADMIN_ROLE, params.emergencyAdmin);

        // Role admin configuration section
        // Each _setRoleAdmin call configures which roles can manage other roles

        // Main investor can manage itself
        _setRoleAdmin(MAIN_INVESTOR_ROLE, MAIN_INVESTOR_ROLE);

        // Backup investor can manage main investor and itself
        _setRoleAdmin(MAIN_INVESTOR_ROLE, BACKUP_INVESTOR_ROLE);
        _setRoleAdmin(BACKUP_INVESTOR_ROLE, BACKUP_INVESTOR_ROLE);

        // Emergency investor can manage main investor, backup investor, and itself
        _setRoleAdmin(MAIN_INVESTOR_ROLE, EMERGENCY_INVESTOR_ROLE);
        _setRoleAdmin(BACKUP_INVESTOR_ROLE, EMERGENCY_INVESTOR_ROLE);
        _setRoleAdmin(EMERGENCY_INVESTOR_ROLE, EMERGENCY_INVESTOR_ROLE);

        // Regular management structure
        _setRoleAdmin(MANAGER_ROLE, MANAGER_ROLE);
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);

        // Backup admin can manage manager, admin, and itself
        _setRoleAdmin(MANAGER_ROLE, BACKUP_ADMIN_ROLE);
        _setRoleAdmin(ADMIN_ROLE, BACKUP_ADMIN_ROLE);
        _setRoleAdmin(BACKUP_ADMIN_ROLE, BACKUP_ADMIN_ROLE);

        // Emergency admin has full control over management roles
        _setRoleAdmin(MANAGER_ROLE, EMERGENCY_ADMIN_ROLE);
        _setRoleAdmin(ADMIN_ROLE, EMERGENCY_ADMIN_ROLE);
        _setRoleAdmin(BACKUP_ADMIN_ROLE, EMERGENCY_ADMIN_ROLE);
        _setRoleAdmin(EMERGENCY_ADMIN_ROLE, EMERGENCY_ADMIN_ROLE);

        withdrawalLockedUntil = uint64(block.timestamp);
    }

    /// @inheritdoc IMainVault
    function setFutureMainVaultImplementation(
        FutureMainVaultImplementation calldata futureImplementation,
        bytes calldata signature
    ) external onlyRole(ADMIN_ROLE) {
        // Verify the signature comes from the main investor
        address signer = _verifyFutureMainVaultImplementationSignature(futureImplementation, signature);
        require(hasRole(MAIN_INVESTOR_ROLE, signer), InvalidSigner());

        // Verify deadline is in the future
        require(futureImplementation.deadline > uint64(block.timestamp), TimestampMustBeInTheFuture());

        // Set the future implementation
        nextFutureImplementationOfMainVault = futureImplementation.implementation;
        nextFutureImplementationOfMainVaultDeadline = futureImplementation.deadline;

        emit FutureMainVaultImplementationSet(futureImplementation.implementation, futureImplementation.deadline);
    }

    /// @inheritdoc IMainVault
    function setFutureInvestorVaultImplementation(
        FutureInvestorVaultImplementation calldata futureImplementation,
        bytes calldata signature
    ) external onlyRole(ADMIN_ROLE) {
        // Verify the signature comes from the main investor
        address signer = _verifyFutureInvestorVaultImplementationSignature(futureImplementation, signature);
        require(hasRole(MAIN_INVESTOR_ROLE, signer), InvalidSigner());

        // Verify deadline is in the future
        require(futureImplementation.deadline > uint64(block.timestamp), TimestampMustBeInTheFuture());

        // Set the future implementation
        nextFutureImplementationOfInvestorVault = futureImplementation.implementation;
        nextFutureImplementationOfInvestorVaultDeadline = futureImplementation.deadline;

        emit FutureInvestorVaultImplementationSet(futureImplementation.implementation, futureImplementation.deadline);
    }

    /// @inheritdoc IMainVault
    function setTokenAvailabilityByInvestor(TokenAvailability[] calldata configs)
        external
        onlyRole(MAIN_INVESTOR_ROLE)
    {
        if (_isLock()) {
            pauseToTimestamp = uint64(block.timestamp + Constants.PAUSE_AFTER_UPDATE_ACCESS);
        }
        for (uint256 i = 0; i < configs.length; i++) {
            availableTokensByInvestor[configs[i].token] = configs[i].isAvailable;

            emit TokenAvailabilityByInvestorChanged(configs[i].token, configs[i].isAvailable);
        }
    }

    /// @inheritdoc IMainVault
    function setRouterAvailabilityByInvestor(address[] calldata routers) external onlyRole(MAIN_INVESTOR_ROLE) {
        if (_isLock()) {
            pauseToTimestamp = uint64(block.timestamp + Constants.PAUSE_AFTER_UPDATE_ACCESS);
        }
        // Process each router address in the array
        for (uint256 i = 0; i < routers.length; i++) {
            availableRouterByInvestor[routers[i]] = true;

            emit RouterAvailabilityByInvestorChanged(routers[i], true);
        }
    }

    /// @inheritdoc IMainVault
    function setTokenAvailabilityByAdmin(TokenAvailability[] calldata configs) external onlyRole(ADMIN_ROLE) {
        for (uint256 i = 0; i < configs.length; i++) {
            availableTokensByAdmin[configs[i].token] = configs[i].isAvailable;

            emit TokenAvailabilityByAdminChanged(configs[i].token, configs[i].isAvailable);
        }
    }

    /// @inheritdoc IMainVault
    function setRouterAvailabilityByAdmin(RouterAvailability[] calldata configs) external onlyRole(ADMIN_ROLE) {
        for (uint256 i = 0; i < configs.length; i++) {
            availableRouterByAdmin[configs[i].router] = configs[i].isAvailable;

            emit RouterAvailabilityByAdminChanged(configs[i].router, configs[i].isAvailable);
        }
    }

    /// @inheritdoc IMainVault
    function setLockPeriodsAvailability(LockPeriodAvailability[] calldata configs) external onlyRole(ADMIN_ROLE) {
        for (uint256 i = 0; i < configs.length; i++) {
            availableLock[configs[i].period] = configs[i].isAvailable;

            emit LockPeriodAvailabilityChanged(configs[i].period, configs[i].isAvailable);
        }
    }

    /// @inheritdoc IMainVault
    function setProfitType(DataTypes.ProfitType _profitType) external onlyRole(MAIN_INVESTOR_ROLE) {
        profitType = _profitType;
        emit ProfitTypeSet(profitType);
    }

    /// @inheritdoc IMainVault
    function setProposedFixedProfitPercentByAdmin(uint32 _proposedFixedProfitPercent) external onlyRole(ADMIN_ROLE) {
        require(_proposedFixedProfitPercent > 0, ZeroAmountNotAllowed());
        require(_proposedFixedProfitPercent < Constants.MAX_FIXED_PROFIT_PERCENT, ExceedsMaximumPercentage());
        proposedFixedProfitPercentByAdmin = _proposedFixedProfitPercent;
        emit ProposedFixedProfitPercentByAdminSet(proposedFixedProfitPercentByAdmin);
    }

    /// @inheritdoc IMainVault
    function setCurrentFixedProfitPercent() external onlyRole(MAIN_INVESTOR_ROLE) {
        uint32 oldPercent = currentFixedProfitPercent;
        currentFixedProfitPercent = proposedFixedProfitPercentByAdmin;

        emit CurrentFixedProfitPercentSet(oldPercent, currentFixedProfitPercent);
    }

    /// @inheritdoc IMainVault
    function setProfitWallet(address wallet) external onlyRole(MAIN_INVESTOR_ROLE) {
        require(wallet != address(0), ZeroAddressNotAllowed());

        address oldWallet = profitWallet;
        profitWallet = wallet;

        // Set profit locked until at least 7 days from now
        profitLockedUntil = uint64(Math.max(profitLockedUntil, block.timestamp + 7 days));

        emit ProfitWalletSet(oldWallet, wallet);
    }

    /// @inheritdoc IMainVault
    function setCurrentImplementationOfInvestmentVault(address implementation) external onlyRole(ADMIN_ROLE) {
        require(implementation == nextFutureImplementationOfInvestorVault, InvalidImplementationAddress());
        require(block.timestamp <= nextFutureImplementationOfInvestorVaultDeadline, InvalidImplementationDeadline());

        address oldImplementation = currentImplementationOfInvestmentVault;

        currentImplementationOfInvestmentVault = implementation;

        nextFutureImplementationOfInvestorVault = address(0);
        nextFutureImplementationOfInvestorVaultDeadline = 0;

        emit CurrentImplementationOfInvestmentVaultSet(oldImplementation, implementation);
    }

    /// @inheritdoc IMainVault
    function setWithdrawalLock(uint256 period) external onlyRole(MAIN_INVESTOR_ROLE) {
        require(availableLock[period], LockPeriodNotAvailable());
        _checkAndRenewWithdrawalLock();
        withdrawalLockedUntil = uint64(Math.max(withdrawalLockedUntil, block.timestamp + period));
        emit WithdrawalLockSet(period, withdrawalLockedUntil);
    }

    /// @inheritdoc IMainVault
    function setAutoRenewWithdrawalLock(bool enabled) external onlyRole(MAIN_INVESTOR_ROLE) {
        bool oldValue = autoRenewWithdrawalLock;
        autoRenewWithdrawalLock = enabled;
        if (oldValue && block.timestamp > withdrawalLockedUntil - Constants.AUTO_RENEW_CHECK_PERIOD) {
            withdrawalLockedUntil += uint64(Constants.AUTO_RENEW_PERIOD);
        }
        emit AutoRenewWithdrawalLockSet(oldValue, enabled);
    }

    /// @inheritdoc IMainVault
    function setWithdrawalLockWithAutoRenew(uint256 period, bool enabled) external onlyRole(MAIN_INVESTOR_ROLE) {
        // Check that the lock period is available
        require(availableLock[period], LockPeriodNotAvailable());

        // Check and renew withdrawal lock if needed
        _checkAndRenewWithdrawalLock();

        // Set the withdrawal lock
        withdrawalLockedUntil = uint64(Math.max(withdrawalLockedUntil, block.timestamp + period));

        // Set auto-renewal setting
        bool oldAutoRenewValue = autoRenewWithdrawalLock;
        autoRenewWithdrawalLock = enabled;

        // If auto-renewal is enabled and the lock is about to expire, extend it
        if (
            enabled && !oldAutoRenewValue && block.timestamp > withdrawalLockedUntil - Constants.AUTO_RENEW_CHECK_PERIOD
        ) {
            withdrawalLockedUntil += uint64(Constants.AUTO_RENEW_PERIOD);
        }

        // Emit events for both operations
        emit WithdrawalLockSet(period, withdrawalLockedUntil);
        emit AutoRenewWithdrawalLockSet(oldAutoRenewValue, enabled);
    }

    /// @dev Pauses the contract operations.
    /// Can only be called by a whitelisted pauser from pauserList
    function pause() external onlyPauser {
        _pause();
    }

    /// @dev Unpauses the contract operations.
    /// Can only be called by a whitelisted pauser from pauserList
    function unpause() external onlyPauser {
        _unpause();
    }

    /// @inheritdoc IMainVault
    /// @dev Overrides the paused function from PausableUpgradeable and IMainVault
    function paused() public view virtual override(PausableUpgradeable, IMainVault) returns (bool) {
        return super.paused();
    }

    /// @inheritdoc IMainVault
    function deposit(IERC20 token, uint256 amount) external whenNotPaused {
        require(availableTokensByInvestor[address(token)], TokenNotAvailable());
        require(amount > 0, ZeroAmountNotAllowed());

        token.safeTransferFrom(msg.sender, address(this), amount);
        emit Deposited(address(token), msg.sender, amount);
    }

    /// @inheritdoc IMainVault
    function withdraw(IERC20 token, uint256 amount) external isNotLocked onlyRole(MAIN_INVESTOR_ROLE) {
        require(amount > 0, ZeroAmountNotAllowed());

        uint256 vaultBalance = token.balanceOf(address(this));
        require(vaultBalance >= amount, InsufficientBalance());

        token.safeTransfer(msg.sender, amount);

        emit Withdrawn(address(token), msg.sender, amount);
    }

    /// @inheritdoc IMainVault
    function swapExactTokensForTokens(
        address router,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        uint256 deadline
    ) external onlyRole(MAIN_INVESTOR_ROLE) whenNotPaused IsNotAfterSetupPause returns (uint256[] memory amounts) {
        amounts = MainVaultSwapLibrary.executeSwapExactTokensForTokens(
            router, amountIn, amountOutMin, path, deadline, availableRouterByAdmin, availableTokensByAdmin
        );
    }

    /// @inheritdoc IMainVault
    function swapTokensForExactTokens(
        address router,
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        uint256 deadline
    ) external onlyRole(MAIN_INVESTOR_ROLE) whenNotPaused IsNotAfterSetupPause returns (uint256[] memory amounts) {
        amounts = MainVaultSwapLibrary.executeSwapTokensForExactTokens(
            router, amountOut, amountInMax, path, deadline, availableRouterByAdmin, availableTokensByAdmin
        );
    }

    /**
     * @dev Deploys a new Investment Vault
     * Only the main investor can call this function
     */
    function deployInvestmentVault(DataTypes.InvestmentVaultInitData calldata initData)
        external
        onlyRole(ADMIN_ROLE)
        whenNotPaused
        returns (address vaultAddress, uint256 vaultId)
    {
        require(currentImplementationOfInvestmentVault != address(0), InvalidImplementationAddress());

        require(availableTokensByInvestor[address(initData.tokenMI)], TokenNotAvailable());

        require(address(initData.mainVault) == address(this), InvalidMainVaultAddress());

        require(initData.initDeposit > 0, ZeroAmountNotAllowed());

        uint256 balance = initData.tokenMI.balanceOf(address(this));
        require(balance >= initData.initDeposit, InsufficientBalance());

        bytes memory initializationData = abi.encodeWithSelector(IInvestmentVault.initialize.selector, initData);

        ERC1967Proxy newProxy = new ERC1967Proxy(currentImplementationOfInvestmentVault, initializationData);

        vaultId = investmentVaultsCount;
        vaultAddress = address(newProxy);

        investmentVaults[vaultId] = vaultAddress;
        investmentVaultsCount++;

        initData.tokenMI.safeTransfer(vaultAddress, initData.initDeposit);

        emit InvestmentVaultDeployed(vaultAddress, address(initData.tokenMI), initData.initDeposit, vaultId);
    }

    /// @inheritdoc IMainVault
    function withdrawFromInvestmentVaults(WithdrawFromVaultData[] calldata withdrawals)
        external
        onlyRole(MAIN_INVESTOR_ROLE)
        isNotLocked
    {
        require(
            block.timestamp > withdrawCommitTimestamp + Constants.WITHDRAW_COMMIT_MIN_DELAY
                && block.timestamp < withdrawCommitTimestamp + Constants.WITHDRAW_COMMIT_MAX_DELAY,
            WithdrawCommitTimestampExpired()
        );
        for (uint256 i = 0; i < withdrawals.length; i++) {
            WithdrawFromVaultData calldata withdrawal = withdrawals[i];

            if (withdrawal.vaultIndex >= investmentVaultsCount) {
                revert InvalidVaultIndex();
            }

            address vaultAddress = investmentVaults[withdrawal.vaultIndex];

            IInvestmentVault vault = IInvestmentVault(vaultAddress);
            vault.withdraw(withdrawal.token, withdrawal.amount, address(this));

            emit WithdrawnFromInvestmentVault(vaultAddress, address(withdrawal.token), withdrawal.amount, msg.sender);
        }
    }

    /// @notice Commits to withdraw from investment vaults after a delay
    /// @dev Sets the withdraw commit timestamp that will be checked in withdrawFromInvestmentVaults
    function commitWithdrawFromInvestmentVault() external onlyRole(MAIN_INVESTOR_ROLE) {
        withdrawCommitTimestamp = uint64(block.timestamp);

        emit WithdrawCommitTimestampSet(withdrawCommitTimestamp);
    }

    /// @inheritdoc IMainVault
    function exactInputSingle(DataTypes.DelegateExactInputSingleParams calldata params)
        external
        onlyRole(MAIN_INVESTOR_ROLE)
        whenNotPaused
        IsNotAfterSetupPause
        returns (uint256 amountOut)
    {
        amountOut = MainVaultSwapLibrary.executeExactInputSingle(
            params.router, params, availableRouterByAdmin, availableTokensByAdmin
        );
    }

    /// @inheritdoc IMainVault
    function exactInput(DataTypes.DelegateExactInputParams calldata params)
        external
        onlyRole(MAIN_INVESTOR_ROLE)
        whenNotPaused
        IsNotAfterSetupPause
        returns (uint256 amountOut)
    {
        amountOut = MainVaultSwapLibrary.executeExactInput(
            params.router, params, availableRouterByAdmin, availableTokensByAdmin
        );
    }

    /// @inheritdoc IMainVault
    function exactOutputSingle(DataTypes.DelegateExactOutputSingleParams calldata params)
        external
        onlyRole(MAIN_INVESTOR_ROLE)
        whenNotPaused
        IsNotAfterSetupPause
        returns (uint256 amountIn)
    {
        amountIn = MainVaultSwapLibrary.executeExactOutputSingle(
            params.router, params, availableRouterByAdmin, availableTokensByAdmin
        );
    }

    /// @inheritdoc IMainVault
    function exactOutput(DataTypes.DelegateExactOutputParams calldata params)
        external
        onlyRole(MAIN_INVESTOR_ROLE)
        whenNotPaused
        IsNotAfterSetupPause
        returns (uint256 amountIn)
    {
        amountIn = MainVaultSwapLibrary.executeExactOutput(
            params.router, params, availableRouterByAdmin, availableTokensByAdmin
        );
    }

    /// @dev Swaps an exact amount of input tokens for as many output tokens as possible using Quickswap V3
    /// @param params The parameters necessary for the swap
    /// @return amountOut The amount of the received token
    function quickswapExactInputSingle(DataTypes.DelegateQuickswapExactInputSingleParams calldata params)
        external
        onlyRole(MAIN_INVESTOR_ROLE)
        whenNotPaused
        IsNotAfterSetupPause
        returns (uint256 amountOut)
    {
        amountOut = MainVaultSwapLibrary.executeQuickswapExactInputSingle(
            params.router, params, availableRouterByAdmin, availableTokensByAdmin
        );
    }

    /// @dev Swaps an exact amount of tokens for as many output tokens as possible along the specified path using Quickswap V3
    /// @param params The parameters necessary for the multi-hop swap
    /// @return amountOut The amount of the received token
    function quickswapExactInput(DataTypes.DelegateQuickswapExactInputParams calldata params)
        external
        onlyRole(MAIN_INVESTOR_ROLE)
        whenNotPaused
        IsNotAfterSetupPause
        returns (uint256 amountOut)
    {
        amountOut = MainVaultSwapLibrary.executeQuickswapExactInput(
            params.router, params, availableRouterByAdmin, availableTokensByAdmin
        );
    }

    /// @dev Swaps as little as possible of one token for an exact amount of another token using Quickswap V3
    /// @param params The parameters necessary for the swap
    /// @return amountIn The amount of the input token spent
    function quickswapExactOutputSingle(DataTypes.DelegateQuickswapExactOutputSingleParams calldata params)
        external
        onlyRole(MAIN_INVESTOR_ROLE)
        whenNotPaused
        IsNotAfterSetupPause
        returns (uint256 amountIn)
    {
        amountIn = MainVaultSwapLibrary.executeQuickswapExactOutputSingle(
            params.router, params, availableRouterByAdmin, availableTokensByAdmin
        );
    }

    /// @dev Swaps as little as possible of one token for an exact amount of another along the specified path using Quickswap V3
    /// @param params The parameters necessary for the multi-hop swap
    /// @return amountIn The amount of the input token spent
    function quickswapExactOutput(DataTypes.DelegateQuickswapExactOutputParams calldata params)
        external
        onlyRole(MAIN_INVESTOR_ROLE)
        whenNotPaused
        IsNotAfterSetupPause
        returns (uint256 amountIn)
    {
        amountIn = MainVaultSwapLibrary.executeQuickswapExactOutput(
            params.router, params, availableRouterByAdmin, availableTokensByAdmin
        );
    }

    /// @inheritdoc IMainVault
    function setInvestorIsCanceledOracleCheck(bool value) external onlyRole(MAIN_INVESTOR_ROLE) {
        investorIsCanceledOracleCheck = value;
    }

    /// @inheritdoc IMainVault
    function setAdminIsCanceledOracleCheck(bool value) external onlyRole(ADMIN_ROLE) {
        adminIsCanceledOracleCheck = value;
    }

    /// @inheritdoc IMainVault
    function isCanceledOracleCheck() external view returns (bool) {
        return investorIsCanceledOracleCheck && adminIsCanceledOracleCheck;
    }

    /// @inheritdoc IMainVault
    function checkAndRenewWithdrawalLock() external onlyRole(ADMIN_ROLE) returns (bool renewed) {
        return _checkAndRenewWithdrawalLock();
    }

    /// @dev Overrides MultiAdminSingleHolderAccessControlUppgradable._grantRole to ensure only one account has each role
    /// @param role The role being assigned
    /// @param account The account receiving the role
    /// @return Boolean indicating if the operation was successful
    function _grantRole(bytes32 role, address account)
        internal
        virtual
        override(MultiAdminSingleHolderAccessControlUppgradable)
        returns (bool)
    {
        // Set lock for 7 days when assigning MAIN_INVESTOR_ROLE
        if (role == MAIN_INVESTOR_ROLE) {
            withdrawalLockedUntil = uint64(Math.max(withdrawalLockedUntil, block.timestamp + 7 days));
        }

        // If emergency investor equals backup admin, remove lock and disable auto-renewal
        if ((role == EMERGENCY_INVESTOR_ROLE) && hasRole(EMERGENCY_ADMIN_ROLE, account)) {
            address backupAdmin = getRoleHolder(BACKUP_ADMIN_ROLE);

            _grantRole(BACKUP_INVESTOR_ROLE, backupAdmin);
            _grantRole(MAIN_INVESTOR_ROLE, backupAdmin);

            // The same address has both EMERGENCY_INVESTOR_ROLE and BACKUP_ADMIN_ROLE
            // Remove withdrawal lock and disable auto-renewal
            withdrawalLockedUntil = 0;
            if (autoRenewWithdrawalLock) {
                bool oldValue = autoRenewWithdrawalLock;
                autoRenewWithdrawalLock = false;
                emit AutoRenewWithdrawalLockSet(oldValue, false);
            }
            emit WithdrawalLockRemovedBySpecialRole(account);
        }

        return super._grantRole(role, account);
    }

    /// @dev Checks if withdrawal lock needs to be renewed and renews it if necessary
    /// Called before any operation that requires checking the withdrawal lock
    /// If auto-renewal is enabled and lock is about to expire, extends it by 365 days
    ///
    /// @return Whether the lock was renewed
    function _checkAndRenewWithdrawalLock() internal returns (bool) {
        if (
            autoRenewWithdrawalLock && withdrawalLockedUntil != 0
                && withdrawalLockedUntil - Constants.AUTO_RENEW_CHECK_PERIOD <= block.timestamp
        ) {
            withdrawalLockedUntil += uint64(Constants.AUTO_RENEW_PERIOD);

            emit WithdrawalLockAutoRenewed(withdrawalLockedUntil);
            return true;
        }
        return false;
    }

    function _isLock() internal returns (bool) {
        _checkAndRenewWithdrawalLock();

        return block.timestamp < withdrawalLockedUntil;
    }

    /// @dev Verifies the EIP-712 signature for a future Main Vault implementation
    /// @param futureImplementation The implementation data that was signed
    /// @param signature The signature to verify
    /// @return The signer's address
    function _verifyFutureMainVaultImplementationSignature(
        FutureMainVaultImplementation calldata futureImplementation,
        bytes calldata signature
    ) internal view returns (address) {
        bytes32 structHash = keccak256(
            abi.encode(
                _FUTURE_MAIN_VAULT_IMPLEMENTATION_TYPEHASH,
                futureImplementation.implementation,
                futureImplementation.deadline
            )
        );

        bytes32 hash = _hashTypedDataV4(structHash);
        return ECDSA.recover(hash, signature);
    }

    /// @dev Verifies the EIP-712 signature for a future Investor Vault implementation
    /// @param futureImplementation The implementation data that was signed
    /// @param signature The signature to verify
    /// @return The signer's address
    function _verifyFutureInvestorVaultImplementationSignature(
        FutureInvestorVaultImplementation calldata futureImplementation,
        bytes calldata signature
    ) internal view returns (address) {
        bytes32 structHash = keccak256(
            abi.encode(
                _FUTURE_INVESTOR_VAULT_IMPLEMENTATION_TYPEHASH,
                futureImplementation.implementation,
                futureImplementation.deadline
            )
        );

        bytes32 hash = _hashTypedDataV4(structHash);
        return ECDSA.recover(hash, signature);
    }

    /// @dev Contract upgrade authorization function (UUPS pattern)
    /// Only the admin role can authorize contract upgrades
    ///
    /// @param newImplementation Address of the new implementation
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(ADMIN_ROLE) {
        require(newImplementation == nextFutureImplementationOfMainVault, InvalidImplementationAddress());
        require(block.timestamp <= nextFutureImplementationOfMainVaultDeadline, InvalidImplementationDeadline());

        nextFutureImplementationOfMainVault = address(0);
        nextFutureImplementationOfMainVaultDeadline = 0;
    }
}
