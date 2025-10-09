// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 fundmera.com

// https://github.com/merafund
pragma solidity ^0.8.29;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {MainVault} from "../src/MainVault.sol";
import {InvestmentVault} from "../src/InvestmentVault.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {DataTypes, IMainVault as DataTypesIMainVault} from "../src/utils/DataTypes.sol";
import {IPauserList} from "../src/interfaces/IPauserList.sol";
import {IMainVault} from "../src/interfaces/IMainVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Constants} from "../src/utils/Constants.sol";
import {MainVaultMockRevokeRole} from "../src/mocks/MainVaultMockRevokeRole.sol";
import {MainVaultV2} from "../src/mocks/MainVaultV2.sol";
import {InvestmentVaultV2} from "../src/mocks/InvestmentVaultV2.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockPauserList {
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    mapping(address => bool) public pausers;

    function hasRole(bytes32 role, address account) external view returns (bool) {
        if (role == PAUSER_ROLE) {
            return pausers[account];
        }
        return false;
    }

    function setPauser(address pauser, bool status) external {
        pausers[pauser] = status;
    }
}

contract MainVaultTest is Test {
    MainVault public implementation;
    ERC1967Proxy public proxy;
    MainVault public vault;
    MockERC20 public token;
    MockERC20 public secondToken;
    MockERC20 public thirdToken;
    MockERC20 public fourthToken;
    MockPauserList public pauserList;
    InvestmentVault public investmentVaultImplementation;

    address public owner = address(1);
    address public user1 = address(2);
    address public user2 = address(3);

    address public mainInvestor = vm.addr(123456);
    address public backupInvestor = address(5);
    address public emergencyInvestor = address(6);
    address public manager = address(7);
    address public admin = address(8);
    address public backupAdmin = address(9);
    address public emergencyAdmin = address(10);
    address public feeWallet = address(11);
    address public profitWallet = address(12);

    uint256 public constant INITIAL_BALANCE = 10000 * 10 ** 18;
    uint256 public constant DEPOSIT_AMOUNT = 1000 * 10 ** 18;
    uint256 public constant FEE_PERCENTAGE = 200; // 2%

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event InvestmentVaultDeployed(address indexed vault, address indexed token, uint256 deposit, uint256 vaultId);
    event WithdrawalLockAutoRenewed(uint64 newLockUntil);
    event Upgraded(address indexed newImplementation);
    event ProfitTypeSet(DataTypes.ProfitType profitType);
    event ProposedFixedProfitPercentByAdminSet(uint32 newPercent);
    event CurrentFixedProfitPercentSet(uint32 oldPercent, uint32 newPercent);
    event WithdrawalLockSet(uint256 lockPeriod, uint64 lockUntil);
    event AutoRenewWithdrawalLockSet(bool autoRenewEnabled, bool newAutoRenewValue);
    event ProposedMeraPriceOracleByAdminSet(address newOracle);
    event MeraPriceOracleSet(address oldOracle, address newOracle);

    function setUp() public {
        vm.startPrank(owner);

        vm.warp(block.timestamp + 10 * 365 days);
        token = new MockERC20();
        secondToken = new MockERC20();
        thirdToken = new MockERC20();
        fourthToken = new MockERC20();

        pauserList = new MockPauserList();

        implementation = new MainVault();

        investmentVaultImplementation = new InvestmentVault();

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
            feePercentage: FEE_PERCENTAGE,
            currentImplementationOfInvestmentVault: address(investmentVaultImplementation),
            pauserList: address(pauserList),
            meraPriceOracle: address(0),
            lockPeriod: 0
        });

        bytes memory initData = abi.encodeWithSelector(MainVault.initialize.selector, initParams);

        proxy = new ERC1967Proxy(address(implementation), initData);

        vault = MainVault(address(proxy));

        token.transfer(user1, INITIAL_BALANCE);
        token.transfer(user2, INITIAL_BALANCE);
        token.transfer(mainInvestor, INITIAL_BALANCE);

        secondToken.transfer(user1, INITIAL_BALANCE);
        secondToken.transfer(user2, INITIAL_BALANCE);
        secondToken.transfer(mainInvestor, INITIAL_BALANCE);

        thirdToken.transfer(user1, INITIAL_BALANCE);
        thirdToken.transfer(user2, INITIAL_BALANCE);
        thirdToken.transfer(mainInvestor, INITIAL_BALANCE);

        fourthToken.transfer(user1, INITIAL_BALANCE);
        fourthToken.transfer(user2, INITIAL_BALANCE);
        fourthToken.transfer(mainInvestor, INITIAL_BALANCE);

        vm.startPrank(mainInvestor);
        IMainVault.TokenAvailability[] memory tokenConfigs = new IMainVault.TokenAvailability[](4);
        tokenConfigs[0] = IMainVault.TokenAvailability({token: address(token), isAvailable: true});
        tokenConfigs[1] = IMainVault.TokenAvailability({token: address(secondToken), isAvailable: true});
        tokenConfigs[2] = IMainVault.TokenAvailability({token: address(thirdToken), isAvailable: true});
        tokenConfigs[3] = IMainVault.TokenAvailability({token: address(fourthToken), isAvailable: true});
        vault.setTokenAvailabilityByInvestor(tokenConfigs);
        vm.stopPrank();

        vm.startPrank(admin);
        vault.setTokenAvailabilityByAdmin(tokenConfigs);
        vm.stopPrank();
    }

    function testDeployInvestmentVaultSameTokens() public {
        vm.startPrank(mainInvestor);
        token.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(token, DEPOSIT_AMOUNT);
        vm.stopPrank();
        vm.startPrank(admin);

        DataTypes.AssetInitData[] memory assets = new DataTypes.AssetInitData[](2);

        assets[0] = DataTypes.AssetInitData({
            token: IERC20(address(fourthToken)),
            shareMV: 6 * 10 ** 17,
            step: 5 * 10 ** 16,
            strategy: DataTypes.Strategy.Zero
        });

        assets[1] = DataTypes.AssetInitData({
            token: IERC20(address(thirdToken)),
            shareMV: 4 * 10 ** 17,
            step: 5 * 10 ** 16,
            strategy: DataTypes.Strategy.First
        });

        DataTypes.InvestmentVaultInitData memory initData = DataTypes.InvestmentVaultInitData({
            mainVault: DataTypesIMainVault(address(vault)),
            tokenMI: IERC20(address(token)),
            tokenMV: IERC20(address(token)),
            capitalOfMi: DEPOSIT_AMOUNT / 2,
            shareMI: Constants.SHARE_DENOMINATOR,
            step: 5 * 10 ** 16,
            assets: assets
        });

        vm.recordLogs();

        (address vaultAddress, uint256 vaultId) = vault.deployInvestmentVault(initData);

        assertEq(vaultId, 0, "Vault ID should be 0");
        assertNotEq(vaultAddress, address(0), "Vault address should not be zero");
        assertEq(vault.investmentVaultsCount(), 1, "InvestmentVaultsCount should be 1");
        assertEq(vault.investmentVaults(0), vaultAddress, "InvestmentVaults mapping should be updated");

        assertEq(token.balanceOf(vaultAddress), DEPOSIT_AMOUNT / 2, "Tokens should be transferred to the new vault");

        vm.stopPrank();
    }

    function testDeployInvestmentVaultDifferentTokens() public {
        vm.startPrank(mainInvestor);

        token.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(token, DEPOSIT_AMOUNT);

        secondToken.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(secondToken, DEPOSIT_AMOUNT);

        thirdToken.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(thirdToken, DEPOSIT_AMOUNT);

        fourthToken.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(fourthToken, DEPOSIT_AMOUNT);
        vm.stopPrank();
        vm.startPrank(admin);

        DataTypes.AssetInitData[] memory assets = new DataTypes.AssetInitData[](2);

        assets[0] = DataTypes.AssetInitData({
            token: IERC20(address(token)),
            shareMV: 6 * 10 ** 17,
            step: 5 * 10 ** 16,
            strategy: DataTypes.Strategy.Zero
        });

        assets[1] = DataTypes.AssetInitData({
            token: IERC20(address(secondToken)),
            shareMV: 4 * 10 ** 17,
            step: 5 * 10 ** 16,
            strategy: DataTypes.Strategy.First
        });

        DataTypes.InvestmentVaultInitData memory initData = DataTypes.InvestmentVaultInitData({
            mainVault: DataTypesIMainVault(address(vault)),
            tokenMI: IERC20(address(fourthToken)),
            tokenMV: IERC20(address(thirdToken)),
            capitalOfMi: DEPOSIT_AMOUNT / 2,
            shareMI: 5000,
            step: 5 * 10 ** 16,
            assets: assets
        });

        vm.recordLogs();

        (address vaultAddress, uint256 vaultId) = vault.deployInvestmentVault(initData);

        assertEq(vaultId, 0, "Vault ID should be 0");
        assertNotEq(vaultAddress, address(0), "Vault address should not be zero");
        assertEq(vault.investmentVaultsCount(), 1, "InvestmentVaultsCount should be 1");
        assertEq(vault.investmentVaults(0), vaultAddress, "InvestmentVaults mapping should be updated");

        assertEq(
            fourthToken.balanceOf(vaultAddress), DEPOSIT_AMOUNT / 2, "Tokens should be transferred to the new vault"
        );

        InvestmentVault deployedVault = InvestmentVault(vaultAddress);

        (IERC20 tMI, IERC20 tMV,,,,,,,,,) = deployedVault.tokenData();

        assertEq(address(tMI), address(fourthToken), "TokenMI should be correctly set");
        assertEq(address(tMV), address(thirdToken), "TokenMV should be correctly set");

        vm.stopPrank();
    }

    function testSetRouterAvailabilityByAdmin() public {
        address router1 = address(100);
        address router2 = address(101);

        vm.startPrank(admin);

        IMainVault.RouterAvailability[] memory configs = new IMainVault.RouterAvailability[](2);
        configs[0] = IMainVault.RouterAvailability({router: router1, isAvailable: true});
        configs[1] = IMainVault.RouterAvailability({router: router2, isAvailable: false});

        vm.recordLogs();
        vault.setRouterAvailabilityByAdmin(configs);

        assertTrue(vault.availableRouterByAdmin(router1), "Router1 should be available");
        assertFalse(vault.availableRouterByAdmin(router2), "Router2 should not be available");

        vm.stopPrank();
    }

    function testSetRouterAvailabilityByAdmin_UpdateExisting() public {
        address router = address(100);

        vm.startPrank(admin);

        IMainVault.RouterAvailability[] memory configs = new IMainVault.RouterAvailability[](1);
        configs[0] = IMainVault.RouterAvailability({router: router, isAvailable: true});
        vault.setRouterAvailabilityByAdmin(configs);

        assertTrue(vault.availableRouterByAdmin(router), "Router should be initially available");

        configs[0] = IMainVault.RouterAvailability({router: router, isAvailable: false});
        vault.setRouterAvailabilityByAdmin(configs);

        assertFalse(vault.availableRouterByAdmin(router), "Router should be unavailable after update");

        vm.stopPrank();
    }

    function testSetRouterAvailabilityByAdmin_EmptyArray() public {
        vm.startPrank(admin);

        IMainVault.RouterAvailability[] memory configs = new IMainVault.RouterAvailability[](0);
        vault.setRouterAvailabilityByAdmin(configs);

        vm.stopPrank();
    }

    function testSetRouterAvailabilityByAdmin_OnlyAdminCanCall() public {
        address router = address(100);
        IMainVault.RouterAvailability[] memory configs = new IMainVault.RouterAvailability[](1);
        configs[0] = IMainVault.RouterAvailability({router: router, isAvailable: true});

        vm.startPrank(user1);
        vm.expectRevert();
        vault.setRouterAvailabilityByAdmin(configs);
        vm.stopPrank();

        vm.startPrank(mainInvestor);
        vm.expectRevert();
        vault.setRouterAvailabilityByAdmin(configs);
        vm.stopPrank();

        vm.startPrank(admin);
        vault.setRouterAvailabilityByAdmin(configs);
        assertTrue(vault.availableRouterByAdmin(router), "Router should be available when set by admin");
        vm.stopPrank();
    }

    function testSetRouterAvailabilityByAdmin_ZeroAddress() public {
        vm.startPrank(admin);

        IMainVault.RouterAvailability[] memory configs = new IMainVault.RouterAvailability[](1);
        configs[0] = IMainVault.RouterAvailability({router: address(0), isAvailable: true});

        vault.setRouterAvailabilityByAdmin(configs);
        assertTrue(vault.availableRouterByAdmin(address(0)), "Zero address router should be settable");

        vm.stopPrank();
    }

    function testSetLockPeriodsAvailability() public {
        uint256 period1 = 1 days;
        uint256 period2 = 7 days;

        vm.startPrank(admin);

        IMainVault.LockPeriodAvailability[] memory configs = new IMainVault.LockPeriodAvailability[](2);
        configs[0] = IMainVault.LockPeriodAvailability({period: period1, isAvailable: true});
        configs[1] = IMainVault.LockPeriodAvailability({period: period2, isAvailable: false});

        vm.recordLogs();
        vault.setLockPeriodsAvailability(configs);

        assertTrue(vault.availableLock(period1), "Period1 should be available");
        assertFalse(vault.availableLock(period2), "Period2 should not be available");

        vm.stopPrank();
    }

    function testSetLockPeriodsAvailability_UpdateExisting() public {
        uint256 period = 30 days;

        vm.startPrank(admin);

        IMainVault.LockPeriodAvailability[] memory configs = new IMainVault.LockPeriodAvailability[](1);
        configs[0] = IMainVault.LockPeriodAvailability({period: period, isAvailable: true});
        vault.setLockPeriodsAvailability(configs);

        assertTrue(vault.availableLock(period), "Lock period should be initially available");

        configs[0] = IMainVault.LockPeriodAvailability({period: period, isAvailable: false});
        vault.setLockPeriodsAvailability(configs);

        assertFalse(vault.availableLock(period), "Lock period should be unavailable after update");

        vm.stopPrank();
    }

    function testSetLockPeriodsAvailability_EmptyArray() public {
        vm.startPrank(admin);

        IMainVault.LockPeriodAvailability[] memory configs = new IMainVault.LockPeriodAvailability[](0);
        vault.setLockPeriodsAvailability(configs);

        vm.stopPrank();
    }

    function testSetLockPeriodsAvailability_OnlyAdminCanCall() public {
        uint256 period = 14 days;
        IMainVault.LockPeriodAvailability[] memory configs = new IMainVault.LockPeriodAvailability[](1);
        configs[0] = IMainVault.LockPeriodAvailability({period: period, isAvailable: true});

        vm.startPrank(user1);
        vm.expectRevert();
        vault.setLockPeriodsAvailability(configs);
        vm.stopPrank();

        vm.startPrank(mainInvestor);
        vm.expectRevert();
        vault.setLockPeriodsAvailability(configs);
        vm.stopPrank();

        vm.startPrank(admin);
        vault.setLockPeriodsAvailability(configs);
        assertTrue(vault.availableLock(period), "Lock period should be available when set by admin");
        vm.stopPrank();
    }

    function testSetLockPeriodsAvailability_ZeroPeriod() public {
        vm.startPrank(admin);

        IMainVault.LockPeriodAvailability[] memory configs = new IMainVault.LockPeriodAvailability[](1);
        configs[0] = IMainVault.LockPeriodAvailability({period: 0, isAvailable: true});

        vault.setLockPeriodsAvailability(configs);
        assertTrue(vault.availableLock(0), "Zero period should be settable");

        vm.stopPrank();
    }

    function testSetLockPeriodsAvailability_MultiplePeriods() public {
        vm.startPrank(admin);

        uint256[] memory periods = new uint256[](4);
        periods[0] = 1 days;
        periods[1] = 7 days;
        periods[2] = 30 days;
        periods[3] = 365 days;

        IMainVault.LockPeriodAvailability[] memory configs = new IMainVault.LockPeriodAvailability[](4);
        for (uint256 i = 0; i < periods.length; i++) {
            configs[i] = IMainVault.LockPeriodAvailability({period: periods[i], isAvailable: true});
        }

        vault.setLockPeriodsAvailability(configs);

        for (uint256 i = 0; i < periods.length; i++) {
            assertTrue(
                vault.availableLock(periods[i]), string(abi.encodePacked("Period ", periods[i], " should be available"))
            );
        }

        vm.stopPrank();
    }

    // Test for approveMainVaultUpgrade - Admin approval
    function testApproveMainVaultUpgrade_Admin() public {
        address newImplementation = address(new MainVaultV2());

        vm.startPrank(admin);
        vault.approveMainVaultUpgrade(newImplementation);

        // Verify state changes
        assertEq(vault.adminApprovedMainVaultImpl(), newImplementation, "Admin approved implementation should be set");
        assertEq(vault.adminApprovedMainVaultTimestamp(), block.timestamp, "Admin approval timestamp should be set");
        vm.stopPrank();
    }

    // Test for approveMainVaultUpgrade - Investor approval
    function testApproveMainVaultUpgrade_Investor() public {
        address newImplementation = address(new MainVaultV2());

        vm.startPrank(mainInvestor);
        vault.approveMainVaultUpgrade(newImplementation);

        // Verify state changes
        assertEq(
            vault.investorApprovedMainVaultImpl(), newImplementation, "Investor approved implementation should be set"
        );
        assertEq(
            vault.investorApprovedMainVaultTimestamp(), block.timestamp, "Investor approval timestamp should be set"
        );
        vm.stopPrank();
    }

    // Test for approveMainVaultUpgrade - Zero address
    function testApproveMainVaultUpgrade_ZeroAddress() public {
        vm.startPrank(admin);
        vm.expectRevert(MainVault.InvalidUpgradeAddress.selector);
        vault.approveMainVaultUpgrade(address(0));
        vm.stopPrank();
    }

    // Test for approveMainVaultUpgrade - Access control
    function testApproveMainVaultUpgrade_OnlyAdminOrInvestor() public {
        address newImplementation = address(new MainVaultV2());

        vm.startPrank(user1);
        vm.expectRevert(MainVault.AccessDenied.selector);
        vault.approveMainVaultUpgrade(newImplementation);
        vm.stopPrank();
    }

    // Test for approveInvestorVaultUpgrade - Admin approval
    function testApproveInvestorVaultUpgrade_Admin() public {
        address newImplementation = address(new InvestmentVaultV2());

        vm.startPrank(admin);
        vault.approveInvestorVaultUpgrade(newImplementation);

        // Verify state changes
        assertEq(
            vault.adminApprovedInvestorVaultImpl(), newImplementation, "Admin approved implementation should be set"
        );
        assertEq(vault.adminApprovedInvestorVaultTimestamp(), block.timestamp, "Admin approval timestamp should be set");
        vm.stopPrank();
    }

    // Test for approveInvestorVaultUpgrade - Investor approval
    function testApproveInvestorVaultUpgrade_Investor() public {
        address newImplementation = address(new InvestmentVaultV2());

        vm.startPrank(mainInvestor);
        vault.approveInvestorVaultUpgrade(newImplementation);

        // Verify state changes
        assertEq(
            vault.investorApprovedInvestorVaultImpl(),
            newImplementation,
            "Investor approved implementation should be set"
        );
        assertEq(
            vault.investorApprovedInvestorVaultTimestamp(), block.timestamp, "Investor approval timestamp should be set"
        );
        vm.stopPrank();
    }

    // Test for approveInvestorVaultUpgrade - Zero address
    function testApproveInvestorVaultUpgrade_ZeroAddress() public {
        vm.startPrank(admin);
        vm.expectRevert(MainVault.InvalidUpgradeAddress.selector);
        vault.approveInvestorVaultUpgrade(address(0));
        vm.stopPrank();
    }

    // Test for approveInvestorVaultUpgrade - Access control
    function testApproveInvestorVaultUpgrade_OnlyAdminOrInvestor() public {
        address newImplementation = address(new InvestmentVaultV2());

        vm.startPrank(user1);
        vm.expectRevert(MainVault.AccessDenied.selector);
        vault.approveInvestorVaultUpgrade(newImplementation);
        vm.stopPrank();
    }

    function testSetTokenAvailabilityByInvestor() public {
        address token1 = address(100);
        address token2 = address(101);

        vm.startPrank(mainInvestor);

        IMainVault.TokenAvailability[] memory configs = new IMainVault.TokenAvailability[](2);
        configs[0] = IMainVault.TokenAvailability({token: token1, isAvailable: true});
        configs[1] = IMainVault.TokenAvailability({token: token2, isAvailable: false});

        vm.recordLogs();
        vault.setTokenAvailabilityByInvestor(configs);

        assertTrue(vault.availableTokensByInvestor(token1), "Token1 should be available");
        assertFalse(vault.availableTokensByInvestor(token2), "Token2 should not be available");

        vm.stopPrank();
    }

    function testSetTokenAvailabilityByInvestor_UpdateExisting() public {
        address tokenAddress = address(100);

        vm.startPrank(mainInvestor);

        IMainVault.TokenAvailability[] memory configs = new IMainVault.TokenAvailability[](1);
        configs[0] = IMainVault.TokenAvailability({token: tokenAddress, isAvailable: true});
        vault.setTokenAvailabilityByInvestor(configs);

        assertTrue(vault.availableTokensByInvestor(tokenAddress), "Token should be initially available");

        configs[0] = IMainVault.TokenAvailability({token: tokenAddress, isAvailable: false});
        vault.setTokenAvailabilityByInvestor(configs);

        assertFalse(vault.availableTokensByInvestor(tokenAddress), "Token should be unavailable after update");

        vm.stopPrank();
    }

    function testSetTokenAvailabilityByInvestor_EmptyArray() public {
        vm.startPrank(mainInvestor);

        IMainVault.TokenAvailability[] memory configs = new IMainVault.TokenAvailability[](0);
        vault.setTokenAvailabilityByInvestor(configs);

        vm.stopPrank();
    }

    function testSetTokenAvailabilityByInvestor_OnlyMainInvestorCanCall() public {
        address tokenAddress = address(100);
        IMainVault.TokenAvailability[] memory configs = new IMainVault.TokenAvailability[](1);
        configs[0] = IMainVault.TokenAvailability({token: tokenAddress, isAvailable: true});

        vm.startPrank(user1);
        vm.expectRevert();
        vault.setTokenAvailabilityByInvestor(configs);
        vm.stopPrank();

        vm.startPrank(admin);
        vm.expectRevert();
        vault.setTokenAvailabilityByInvestor(configs);
        vm.stopPrank();

        vm.startPrank(mainInvestor);
        vault.setTokenAvailabilityByInvestor(configs);
        assertTrue(vault.availableTokensByInvestor(tokenAddress), "Token should be available when set by main investor");
        vm.stopPrank();
    }

    function testSetTokenAvailabilityByInvestor_ZeroAddress() public {
        vm.startPrank(mainInvestor);

        IMainVault.TokenAvailability[] memory configs = new IMainVault.TokenAvailability[](1);
        configs[0] = IMainVault.TokenAvailability({token: address(0), isAvailable: true});

        vault.setTokenAvailabilityByInvestor(configs);
        assertTrue(vault.availableTokensByInvestor(address(0)), "Zero address token should be settable");

        vm.stopPrank();
    }

    function testSetTokenAvailabilityByInvestor_WithLock() public {
        address tokenAddress = address(100);

        vm.startPrank(mainInvestor);

        vm.warp(1000);

        vault.setWithdrawalLock(10 minutes);

        vm.warp(1000 + 5 minutes);

        IMainVault.TokenAvailability[] memory configs = new IMainVault.TokenAvailability[](1);
        configs[0] = IMainVault.TokenAvailability({token: tokenAddress, isAvailable: true});

        vault.setTokenAvailabilityByInvestor(configs);

        assertEq(
            vault.pauseToTimestamp(),
            uint64(block.timestamp + Constants.PAUSE_AFTER_UPDATE_ACCESS),
            "Pause timestamp should be set correctly"
        );

        assertTrue(vault.availableTokensByInvestor(tokenAddress), "Token should be available despite lock");

        vm.stopPrank();
    }

    function testSetTokenAvailabilityByInvestor_WithLockMultipleTokens() public {
        address[] memory tokens = new address[](3);
        tokens[0] = address(100);
        tokens[1] = address(101);
        tokens[2] = address(102);

        vm.startPrank(mainInvestor);

        vm.warp(1000);

        vault.setWithdrawalLock(10 minutes);

        IMainVault.TokenAvailability[] memory configs = new IMainVault.TokenAvailability[](3);
        for (uint256 i = 0; i < tokens.length; i++) {
            configs[i] = IMainVault.TokenAvailability({token: tokens[i], isAvailable: true});
        }

        vault.setTokenAvailabilityByInvestor(configs);

        assertEq(
            vault.pauseToTimestamp(),
            uint64(block.timestamp + Constants.PAUSE_AFTER_UPDATE_ACCESS),
            "Pause timestamp should be set correctly"
        );

        for (uint256 i = 0; i < tokens.length; i++) {
            assertTrue(
                vault.availableTokensByInvestor(tokens[i]),
                string(abi.encodePacked("Token ", tokens[i], " should be available despite lock"))
            );
        }

        vm.stopPrank();
    }

    function testSetRouterAvailabilityByInvestor() public {
        address router1 = address(100);
        address router2 = address(101);

        vm.startPrank(mainInvestor);

        address[] memory routers = new address[](2);
        routers[0] = router1;
        routers[1] = router2;

        vm.recordLogs();
        vault.setRouterAvailabilityByInvestor(routers);

        assertTrue(vault.availableRouterByInvestor(router1), "Router1 should be available");
        assertTrue(vault.availableRouterByInvestor(router2), "Router2 should be available");

        vm.stopPrank();
    }

    function testSetRouterAvailabilityByInvestor_EmptyArray() public {
        vm.startPrank(mainInvestor);

        address[] memory routers = new address[](0);
        vault.setRouterAvailabilityByInvestor(routers);

        vm.stopPrank();
    }

    function testSetRouterAvailabilityByInvestor_OnlyMainInvestorCanCall() public {
        address router = address(100);
        address[] memory routers = new address[](1);
        routers[0] = router;

        vm.startPrank(user1);
        vm.expectRevert();
        vault.setRouterAvailabilityByInvestor(routers);
        vm.stopPrank();

        vm.startPrank(admin);
        vm.expectRevert();
        vault.setRouterAvailabilityByInvestor(routers);
        vm.stopPrank();

        vm.startPrank(mainInvestor);
        vault.setRouterAvailabilityByInvestor(routers);
        assertTrue(vault.availableRouterByInvestor(router), "Router should be available when set by main investor");
        vm.stopPrank();
    }

    function testSetRouterAvailabilityByInvestor_ZeroAddress() public {
        vm.startPrank(mainInvestor);

        address[] memory routers = new address[](1);
        routers[0] = address(0);

        vault.setRouterAvailabilityByInvestor(routers);
        assertTrue(vault.availableRouterByInvestor(address(0)), "Zero address router should be settable");

        vm.stopPrank();
    }

    function testSetRouterAvailabilityByInvestor_WithLock() public {
        address router = address(100);

        vm.startPrank(mainInvestor);

        vm.warp(1000);

        vault.setWithdrawalLock(10 minutes);

        vm.warp(1000 + 5 minutes);

        address[] memory routers = new address[](1);
        routers[0] = router;

        vault.setRouterAvailabilityByInvestor(routers);

        assertEq(
            vault.pauseToTimestamp(),
            uint64(block.timestamp + Constants.PAUSE_AFTER_UPDATE_ACCESS),
            "Pause timestamp should be set correctly"
        );

        assertTrue(vault.availableRouterByInvestor(router), "Router should be available despite lock");

        vm.stopPrank();
    }

    function testSetRouterAvailabilityByInvestor_WithLockMultipleRouters() public {
        address[] memory routers = new address[](3);
        routers[0] = address(100);
        routers[1] = address(101);
        routers[2] = address(102);

        vm.startPrank(mainInvestor);

        vm.warp(1000);

        vault.setWithdrawalLock(10 minutes);

        vm.warp(1000 + 5 minutes);

        vault.setRouterAvailabilityByInvestor(routers);

        assertEq(
            vault.pauseToTimestamp(),
            uint64(block.timestamp + Constants.PAUSE_AFTER_UPDATE_ACCESS),
            "Pause timestamp should be set correctly"
        );

        // Verify all routers were set correctly
        for (uint256 i = 0; i < routers.length; i++) {
            assertTrue(
                vault.availableRouterByInvestor(routers[i]),
                string(abi.encodePacked("Router ", routers[i], " should be available despite lock"))
            );
        }

        vm.stopPrank();
    }

    function testSetProfitWallet() public {
        address newWallet = address(123);

        vm.startPrank(mainInvestor);

        vm.recordLogs();

        vault.setProfitWallet(newWallet);

        assertEq(vault.profitWallet(), newWallet, "Profit wallet should be updated");

        assertEq(vault.profitLockedUntil(), uint64(block.timestamp + 7 days), "Profit should be locked for 7 days");

        vm.stopPrank();
    }

    function testSetProfitWallet_ZeroAddress() public {
        vm.startPrank(mainInvestor);

        // Try to set zero address
        vm.expectRevert(MainVault.ZeroAddressNotAllowed.selector);
        vault.setProfitWallet(address(0));

        vm.stopPrank();
    }

    function testSetProfitWallet_OnlyMainInvestorCanCall() public {
        address newWallet = address(123);

        // Try calling from non-main-investor addresses
        vm.startPrank(user1);
        vm.expectRevert();
        vault.setProfitWallet(newWallet);
        vm.stopPrank();

        vm.startPrank(admin);
        vm.expectRevert();
        vault.setProfitWallet(newWallet);
        vm.stopPrank();

        // Should work with main investor
        vm.startPrank(mainInvestor);
        vault.setProfitWallet(newWallet);
        assertEq(vault.profitWallet(), newWallet, "Profit wallet should be updated when set by main investor");
        vm.stopPrank();
    }

    function testSetProfitWallet_UpdateExistingWallet() public {
        address firstWallet = address(123);
        address secondWallet = address(456);

        vm.startPrank(mainInvestor);

        // Set first wallet
        vault.setProfitWallet(firstWallet);
        assertEq(vault.profitWallet(), firstWallet, "First wallet should be set");

        // Record first lock end time
        uint64 firstLockEnd = vault.profitLockedUntil();

        // Move time forward 3 days
        vm.warp(block.timestamp + 3 days);

        // Set second wallet
        vault.setProfitWallet(secondWallet);

        // Verify wallet was updated
        assertEq(vault.profitWallet(), secondWallet, "Second wallet should be set");

        // Verify new lock period is 7 days from latest update
        assertEq(
            vault.profitLockedUntil(),
            uint64(block.timestamp + 7 days),
            "New lock period should be 7 days from latest update"
        );

        // Verify new lock end is later than first lock end
        assertTrue(vault.profitLockedUntil() > firstLockEnd, "New lock end should be later than first lock end");

        vm.stopPrank();
    }

    function testWithdrawFromInvestmentVaults() public {
        // Deploy investment vault and deposit tokens
        vm.startPrank(mainInvestor);
        token.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(token, DEPOSIT_AMOUNT);
        vm.stopPrank();

        vm.startPrank(admin);
        DataTypes.AssetInitData[] memory assets = new DataTypes.AssetInitData[](1);
        assets[0] = DataTypes.AssetInitData({
            token: IERC20(address(fourthToken)),
            shareMV: 5 * 10 ** 17,
            step: 5 * 10 ** 16,
            strategy: DataTypes.Strategy.Zero
        });

        DataTypes.InvestmentVaultInitData memory initData = DataTypes.InvestmentVaultInitData({
            mainVault: DataTypesIMainVault(address(vault)),
            tokenMI: IERC20(address(token)),
            tokenMV: IERC20(address(token)),
            capitalOfMi: DEPOSIT_AMOUNT / 2,
            shareMI: Constants.SHARE_DENOMINATOR,
            step: 5 * 10 ** 16,
            assets: assets
        });

        vault.deployInvestmentVault(initData);
        vm.stopPrank();

        // Wait for initial lock period to expire (7 days)
        vm.warp(block.timestamp + 7 days + 1);

        vm.startPrank(mainInvestor);

        // Set commit timestamp
        uint256 commitTime = block.timestamp;
        vault.commitWithdrawFromInvestmentVault();

        // Move time forward to be within valid range (after min delay but before max delay)
        vm.warp(commitTime + Constants.WITHDRAW_COMMIT_MIN_DELAY + 1);

        IMainVault.WithdrawFromVaultData[] memory withdrawals = new IMainVault.WithdrawFromVaultData[](1);
        withdrawals[0] =
            IMainVault.WithdrawFromVaultData({vaultIndex: 0, token: IERC20(address(token)), amount: DEPOSIT_AMOUNT / 4});

        uint256 balanceBefore = token.balanceOf(address(vault));

        // Execute withdrawal
        vault.withdrawFromInvestmentVaults(withdrawals);

        // Verify balance increased
        assertEq(
            token.balanceOf(address(vault)),
            balanceBefore + DEPOSIT_AMOUNT / 4,
            "Main vault balance should increase after withdrawal"
        );

        vm.stopPrank();
    }

    function testWithdrawFromInvestmentVaults_CommitTimestampTooEarly() public {
        // Wait for initial lock period to expire (7 days)
        vm.warp(block.timestamp + 7 days + 1);

        vm.startPrank(mainInvestor);

        // Set commit timestamp
        uint256 commitTime = block.timestamp;
        vault.commitWithdrawFromInvestmentVault();

        // Try to withdraw before min delay
        vm.warp(commitTime + Constants.WITHDRAW_COMMIT_MIN_DELAY - 1);

        IMainVault.WithdrawFromVaultData[] memory withdrawals = new IMainVault.WithdrawFromVaultData[](1);
        withdrawals[0] =
            IMainVault.WithdrawFromVaultData({vaultIndex: 0, token: IERC20(address(token)), amount: DEPOSIT_AMOUNT});

        vm.expectRevert(MainVault.WithdrawCommitTimestampExpired.selector);
        vault.withdrawFromInvestmentVaults(withdrawals);

        vm.stopPrank();
    }

    function testWithdrawFromInvestmentVaults_CommitTimestampTooLate() public {
        // Wait for initial lock period to expire (7 days)
        vm.warp(block.timestamp + 7 days + 1);

        vm.startPrank(mainInvestor);

        // Set commit timestamp
        uint256 commitTime = block.timestamp;
        vault.commitWithdrawFromInvestmentVault();

        // Move time past max delay
        vm.warp(commitTime + Constants.WITHDRAW_COMMIT_MAX_DELAY + 1);

        IMainVault.WithdrawFromVaultData[] memory withdrawals = new IMainVault.WithdrawFromVaultData[](1);
        withdrawals[0] =
            IMainVault.WithdrawFromVaultData({vaultIndex: 0, token: IERC20(address(token)), amount: DEPOSIT_AMOUNT});

        vm.expectRevert(MainVault.WithdrawCommitTimestampExpired.selector);
        vault.withdrawFromInvestmentVaults(withdrawals);

        vm.stopPrank();
    }

    function testWithdrawFromInvestmentVaults_InvalidVaultIndex() public {
        // Deploy at least one vault first
        vm.startPrank(mainInvestor);
        token.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(token, DEPOSIT_AMOUNT);
        vm.stopPrank();

        vm.startPrank(admin);
        DataTypes.AssetInitData[] memory assets = new DataTypes.AssetInitData[](1);
        assets[0] = DataTypes.AssetInitData({
            token: IERC20(address(fourthToken)),
            shareMV: 5 * 10 ** 17,
            step: 5 * 10 ** 16,
            strategy: DataTypes.Strategy.Zero
        });

        DataTypes.InvestmentVaultInitData memory initData = DataTypes.InvestmentVaultInitData({
            mainVault: DataTypesIMainVault(address(vault)),
            tokenMI: IERC20(address(token)),
            tokenMV: IERC20(address(token)),
            capitalOfMi: DEPOSIT_AMOUNT / 2,
            shareMI: Constants.SHARE_DENOMINATOR,
            step: 5 * 10 ** 16,
            assets: assets
        });

        vault.deployInvestmentVault(initData);
        vm.stopPrank();

        // Wait for initial lock period to expire (7 days)
        vm.warp(block.timestamp + 7 days + 1);

        vm.startPrank(mainInvestor);

        // Set commit timestamp
        uint256 commitTime = block.timestamp;
        vault.commitWithdrawFromInvestmentVault();

        // Move time forward to be within valid range
        vm.warp(commitTime + Constants.WITHDRAW_COMMIT_MIN_DELAY + 1);

        IMainVault.WithdrawFromVaultData[] memory withdrawals = new IMainVault.WithdrawFromVaultData[](1);
        withdrawals[0] = IMainVault.WithdrawFromVaultData({
            vaultIndex: 999, // Non-existent vault index
            token: IERC20(address(token)),
            amount: DEPOSIT_AMOUNT
        });

        vm.expectRevert(MainVault.InvalidVaultIndex.selector);
        vault.withdrawFromInvestmentVaults(withdrawals);

        vm.stopPrank();
    }

    function testWithdrawFromInvestmentVaults_MultipleVaults() public {
        // Deploy first investment vault
        vm.startPrank(mainInvestor);
        token.approve(address(vault), DEPOSIT_AMOUNT * 2);
        vault.deposit(token, DEPOSIT_AMOUNT * 2);
        vm.stopPrank();

        vm.startPrank(admin);
        DataTypes.AssetInitData[] memory assets = new DataTypes.AssetInitData[](1);
        assets[0] = DataTypes.AssetInitData({
            token: IERC20(address(fourthToken)),
            shareMV: 5 * 10 ** 17,
            step: 5 * 10 ** 16,
            strategy: DataTypes.Strategy.Zero
        });

        // Deploy first vault
        DataTypes.InvestmentVaultInitData memory initData1 = DataTypes.InvestmentVaultInitData({
            mainVault: DataTypesIMainVault(address(vault)),
            tokenMI: IERC20(address(token)),
            tokenMV: IERC20(address(token)),
            capitalOfMi: DEPOSIT_AMOUNT / 2,
            shareMI: Constants.SHARE_DENOMINATOR,
            step: 5 * 10 ** 16,
            assets: assets
        });
        vault.deployInvestmentVault(initData1);

        // Deploy second vault
        DataTypes.InvestmentVaultInitData memory initData2 = DataTypes.InvestmentVaultInitData({
            mainVault: DataTypesIMainVault(address(vault)),
            tokenMI: IERC20(address(token)),
            tokenMV: IERC20(address(token)),
            capitalOfMi: DEPOSIT_AMOUNT / 2,
            shareMI: Constants.SHARE_DENOMINATOR,
            step: 5 * 10 ** 16,
            assets: assets
        });
        vault.deployInvestmentVault(initData2);
        vm.stopPrank();

        // Wait for initial lock period to expire (7 days)
        vm.warp(block.timestamp + 7 days + 1);

        vm.startPrank(mainInvestor);

        // Set commit timestamp
        uint256 commitTime = block.timestamp;
        vault.commitWithdrawFromInvestmentVault();

        // Move time forward to be within valid range
        vm.warp(commitTime + Constants.WITHDRAW_COMMIT_MIN_DELAY + 1);

        IMainVault.WithdrawFromVaultData[] memory withdrawals = new IMainVault.WithdrawFromVaultData[](2);
        withdrawals[0] =
            IMainVault.WithdrawFromVaultData({vaultIndex: 0, token: IERC20(address(token)), amount: DEPOSIT_AMOUNT / 4});
        withdrawals[1] =
            IMainVault.WithdrawFromVaultData({vaultIndex: 1, token: IERC20(address(token)), amount: DEPOSIT_AMOUNT / 4});

        uint256 balanceBefore = token.balanceOf(address(vault));

        // Execute withdrawals
        vault.withdrawFromInvestmentVaults(withdrawals);

        // Verify balance increased from both withdrawals
        assertEq(
            token.balanceOf(address(vault)),
            balanceBefore + DEPOSIT_AMOUNT / 2,
            "Main vault balance should increase after withdrawals from both vaults"
        );

        vm.stopPrank();
    }

    function testSetCurrentImplementationOfInvestmentVault() public {
        address newImplementation = address(new InvestmentVaultV2());

        // Both admin and investor approve
        vm.prank(admin);
        vault.approveInvestorVaultUpgrade(newImplementation);

        vm.prank(mainInvestor);
        vault.approveInvestorVaultUpgrade(newImplementation);

        // Admin sets the implementation
        vm.prank(admin);
        vault.setCurrentImplementationOfInvestmentVault(newImplementation);

        assertEq(
            vault.currentImplementationOfInvestmentVault(),
            newImplementation,
            "Current implementation should be updated"
        );

        // Verify approval state is cleared
        assertEq(vault.adminApprovedInvestorVaultImpl(), address(0), "Admin approval should be cleared");
        assertEq(vault.investorApprovedInvestorVaultImpl(), address(0), "Investor approval should be cleared");
    }

    function testSetCurrentImplementationOfInvestmentVault_OnlyInvestorApproved() public {
        address newImplementation = address(new InvestmentVaultV2());

        // Only investor approves
        vm.prank(mainInvestor);
        vault.approveInvestorVaultUpgrade(newImplementation);

        // Try to set without admin approval
        vm.prank(admin);
        vm.expectRevert(MainVault.ImplementationNotApprovedByAdmin.selector);
        vault.setCurrentImplementationOfInvestmentVault(newImplementation);
    }

    function testSetCurrentImplementationOfInvestmentVault_OnlyAdminApproved() public {
        address newImplementation = address(new InvestmentVaultV2());

        // Only admin approves
        vm.prank(admin);
        vault.approveInvestorVaultUpgrade(newImplementation);

        // Try to set without investor approval
        vm.prank(mainInvestor);
        vm.expectRevert(MainVault.ImplementationNotApprovedByInvestor.selector);
        vault.setCurrentImplementationOfInvestmentVault(newImplementation);
    }

    function testSetCurrentImplementationOfInvestmentVault_DifferentApprovals() public {
        address implementation1 = address(new InvestmentVaultV2());
        address implementation2 = address(new InvestmentVaultV2());

        // Admin approves one implementation
        vm.prank(admin);
        vault.approveInvestorVaultUpgrade(implementation1);

        // Investor approves different implementation
        vm.prank(mainInvestor);
        vault.approveInvestorVaultUpgrade(implementation2);

        // Try to set either - both should fail
        vm.prank(admin);
        vm.expectRevert(MainVault.ImplementationNotApprovedByInvestor.selector);
        vault.setCurrentImplementationOfInvestmentVault(implementation1);

        vm.prank(admin);
        vm.expectRevert(MainVault.ImplementationNotApprovedByAdmin.selector);
        vault.setCurrentImplementationOfInvestmentVault(implementation2);
    }

    function testSetCurrentImplementationOfInvestmentVault_ExpiredDeadline() public {
        address newImplementation = address(new InvestmentVaultV2());

        // Both approve
        vm.prank(admin);
        vault.approveInvestorVaultUpgrade(newImplementation);

        vm.prank(mainInvestor);
        vault.approveInvestorVaultUpgrade(newImplementation);

        // Warp past deadline
        vm.warp(block.timestamp + vault.UPGRADE_TIME_LIMIT() + 1);

        vm.prank(admin);
        vm.expectRevert(MainVault.UpgradeDeadlineExpired.selector);
        vault.setCurrentImplementationOfInvestmentVault(newImplementation);
    }

    function testSetCurrentImplementationOfInvestmentVault_AdminOrInvestorCanCall() public {
        address newImplementation = address(new InvestmentVaultV2());

        // Both approve
        vm.prank(admin);
        vault.approveInvestorVaultUpgrade(newImplementation);

        vm.prank(mainInvestor);
        vault.approveInvestorVaultUpgrade(newImplementation);

        // User cannot call
        vm.prank(user1);
        vm.expectRevert(MainVault.AccessDenied.selector);
        vault.setCurrentImplementationOfInvestmentVault(newImplementation);

        // Investor can call
        vm.prank(mainInvestor);
        vault.setCurrentImplementationOfInvestmentVault(newImplementation);

        assertEq(vault.currentImplementationOfInvestmentVault(), newImplementation, "Implementation should be updated");
    }

    function testSetAutoRenewWithdrawalLock() public {
        vm.startPrank(mainInvestor);

        assertFalse(vault.autoRenewWithdrawalLock(), "Auto renew should be initially disabled");

        vault.setAutoRenewWithdrawalLock(true);
        assertTrue(vault.autoRenewWithdrawalLock(), "Auto renew should be enabled");

        vault.setAutoRenewWithdrawalLock(false);
        assertFalse(vault.autoRenewWithdrawalLock(), "Auto renew should be disabled");

        vm.stopPrank();
    }

    function testSetAutoRenewWithdrawalLock_ExtendPeriodOnDisable() public {
        vm.startPrank(mainInvestor);

        vault.setWithdrawalLock(365 days);
        uint64 initialLockUntil = vault.withdrawalLockedUntil();

        vault.setAutoRenewWithdrawalLock(true);

        vm.warp(initialLockUntil - Constants.AUTO_RENEW_CHECK_PERIOD + 1);

        vault.setAutoRenewWithdrawalLock(false);

        assertEq(
            vault.withdrawalLockedUntil(),
            initialLockUntil + Constants.AUTO_RENEW_PERIOD,
            "Lock period should be extended when disabling auto renew near end"
        );

        vm.stopPrank();
    }

    function testSetAutoRenewWithdrawalLock_NoExtendPeriodOnDisable() public {
        vm.startPrank(mainInvestor);

        vault.setWithdrawalLock(10 minutes);
        uint64 initialLockUntil = vault.withdrawalLockedUntil();

        vault.setAutoRenewWithdrawalLock(true);

        vault.setAutoRenewWithdrawalLock(false);

        assertEq(
            vault.withdrawalLockedUntil(),
            initialLockUntil + Constants.AUTO_RENEW_PERIOD,
            "Lock period should be extended when disabling auto renew early"
        );

        vm.stopPrank();
    }

    function testSetAutoRenewWithdrawalLock_OnlyMainInvestorCanCall() public {
        vm.startPrank(user1);
        vm.expectRevert();
        vault.setAutoRenewWithdrawalLock(true);
        vm.stopPrank();

        vm.startPrank(admin);
        vm.expectRevert();
        vault.setAutoRenewWithdrawalLock(true);
        vm.stopPrank();

        vm.startPrank(mainInvestor);
        vault.setAutoRenewWithdrawalLock(true);
        assertTrue(vault.autoRenewWithdrawalLock(), "Main investor should be able to enable auto renew");
        vm.stopPrank();
    }

    function testSetAutoRenewWithdrawalLock_NoExtendOnEnable() public {
        vm.startPrank(mainInvestor);

        vault.setWithdrawalLock(10 minutes);
        uint64 initialLockUntil = vault.withdrawalLockedUntil();

        vault.setAutoRenewWithdrawalLock(true);

        assertEq(
            vault.withdrawalLockedUntil(),
            initialLockUntil,
            "Lock period should not be extended when enabling auto renew"
        );

        vm.stopPrank();
    }

    function testSetAutoRenewWithdrawalLock_MultipleToggles() public {
        vm.startPrank(mainInvestor);

        vault.setWithdrawalLock(10 minutes);
        uint64 initialLockUntil = vault.withdrawalLockedUntil();

        vault.setAutoRenewWithdrawalLock(true);
        assertTrue(vault.autoRenewWithdrawalLock(), "Should be enabled after first enable");

        vault.setAutoRenewWithdrawalLock(false);
        assertFalse(vault.autoRenewWithdrawalLock(), "Should be disabled after first disable");

        vm.warp(initialLockUntil - Constants.AUTO_RENEW_CHECK_PERIOD + 1);

        vault.setAutoRenewWithdrawalLock(true);
        assertTrue(vault.autoRenewWithdrawalLock(), "Should be enabled after second enable");

        vault.setAutoRenewWithdrawalLock(false);
        assertFalse(vault.autoRenewWithdrawalLock(), "Should be disabled after second disable");
        assertEq(
            vault.withdrawalLockedUntil(),
            initialLockUntil + Constants.AUTO_RENEW_PERIOD,
            "Lock period should be extended on final disable near end"
        );

        vm.stopPrank();
    }

    function testWithdraw() public {
        vm.startPrank(mainInvestor);

        token.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(token, DEPOSIT_AMOUNT);

        vm.warp(block.timestamp + 7 days + 1);

        uint256 initialBalance = token.balanceOf(mainInvestor);

        vault.withdraw(token, DEPOSIT_AMOUNT / 2);

        assertEq(
            token.balanceOf(mainInvestor),
            initialBalance + DEPOSIT_AMOUNT / 2,
            "Balance should increase after withdrawal"
        );

        assertEq(token.balanceOf(address(vault)), DEPOSIT_AMOUNT / 2, "Vault balance should decrease after withdrawal");

        vm.stopPrank();
    }

    function testWithdraw_ZeroAmount() public {
        vm.startPrank(mainInvestor);

        token.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(token, DEPOSIT_AMOUNT);

        vm.warp(block.timestamp + 7 days + 1);

        vm.expectRevert(MainVault.ZeroAmountNotAllowed.selector);
        vault.withdraw(token, 0);

        vm.stopPrank();
    }

    function testWithdraw_InsufficientBalance() public {
        vm.startPrank(mainInvestor);

        token.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(token, DEPOSIT_AMOUNT);

        vm.warp(block.timestamp + 7 days + 1);

        vm.expectRevert(MainVault.InsufficientBalance.selector);
        vault.withdraw(token, DEPOSIT_AMOUNT + 1);

        vm.stopPrank();
    }

    function testWithdraw_OnlyMainInvestorCanCall() public {
        vm.startPrank(mainInvestor);
        token.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(token, DEPOSIT_AMOUNT);
        vm.stopPrank();

        vm.warp(block.timestamp + 7 days + 1);

        vm.startPrank(user1);
        vm.expectRevert();
        vault.withdraw(token, DEPOSIT_AMOUNT / 2);
        vm.stopPrank();

        vm.startPrank(admin);
        vm.expectRevert();
        vault.withdraw(token, DEPOSIT_AMOUNT / 2);
        vm.stopPrank();

        vm.startPrank(mainInvestor);
        vault.withdraw(token, DEPOSIT_AMOUNT / 2);
        assertEq(
            token.balanceOf(mainInvestor),
            INITIAL_BALANCE - DEPOSIT_AMOUNT / 2,
            "Main investor should be able to withdraw"
        );
        vm.stopPrank();
    }

    function testWithdraw_WithdrawalLocked() public {
        vm.startPrank(mainInvestor);

        token.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(token, DEPOSIT_AMOUNT);

        vault.setWithdrawalLock(10 minutes);

        vm.expectRevert(MainVault.WithdrawalLocked.selector);
        vault.withdraw(token, DEPOSIT_AMOUNT / 2);

        vm.stopPrank();
    }

    function testWithdraw_AfterLockExpires() public {
        vm.startPrank(mainInvestor);

        token.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(token, DEPOSIT_AMOUNT);

        vault.setWithdrawalLock(10 minutes);

        vm.warp(block.timestamp + 7 days + 10 minutes + 1);

        uint256 initialBalance = token.balanceOf(mainInvestor);
        vault.withdraw(token, DEPOSIT_AMOUNT / 2);

        assertEq(
            token.balanceOf(mainInvestor),
            initialBalance + DEPOSIT_AMOUNT / 2,
            "Should be able to withdraw after lock expires"
        );

        vm.stopPrank();
    }

    function testWithdraw_WithAutoRenew() public {
        vm.startPrank(mainInvestor);

        token.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(token, DEPOSIT_AMOUNT);

        vm.warp(block.timestamp + 7 days + 1);

        vault.setWithdrawalLock(10 minutes);
        vault.setAutoRenewWithdrawalLock(true);

        uint64 currentLockUntil = vault.withdrawalLockedUntil();

        vm.warp(currentLockUntil - Constants.AUTO_RENEW_CHECK_PERIOD + 1);

        vm.expectRevert(MainVault.WithdrawalLocked.selector);
        vault.withdraw(token, DEPOSIT_AMOUNT / 2);

        assertGe(vault.withdrawalLockedUntil(), currentLockUntil, "Lock period should be extended by auto renew");

        vm.stopPrank();
    }

    function testWithdraw_MultipleWithdrawals() public {
        vm.startPrank(mainInvestor);

        token.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(token, DEPOSIT_AMOUNT);

        vm.warp(block.timestamp + 7 days + 1);

        uint256 initialBalance = token.balanceOf(mainInvestor);

        vault.withdraw(token, DEPOSIT_AMOUNT / 4);
        assertEq(token.balanceOf(mainInvestor), initialBalance + DEPOSIT_AMOUNT / 4, "First withdrawal should succeed");

        vault.withdraw(token, DEPOSIT_AMOUNT / 4);
        assertEq(token.balanceOf(mainInvestor), initialBalance + DEPOSIT_AMOUNT / 2, "Second withdrawal should succeed");

        assertEq(
            token.balanceOf(address(vault)),
            DEPOSIT_AMOUNT / 2,
            "Vault balance should be correct after multiple withdrawals"
        );

        vm.stopPrank();
    }

    function testGrantRole_RevokeRoleFails() public {
        MainVaultMockRevokeRole mockVaultImpl = new MainVaultMockRevokeRole();

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
            feePercentage: FEE_PERCENTAGE,
            currentImplementationOfInvestmentVault: address(investmentVaultImplementation),
            pauserList: address(pauserList),
            meraPriceOracle: address(0),
            lockPeriod: 0
        });

        bytes memory initData = abi.encodeWithSelector(MainVault.initialize.selector, initParams);

        ERC1967Proxy mockProxy = new ERC1967Proxy(address(mockVaultImpl), initData);
        MainVaultMockRevokeRole mockVault = MainVaultMockRevokeRole(address(mockProxy));

        bytes32 mainInvestorRole = mockVault.MAIN_INVESTOR_ROLE();

        vm.prank(emergencyInvestor);
        mockVault.grantRole(mainInvestorRole, user1);

        assertFalse(mockVault.hasRole(mainInvestorRole, mainInvestor), "Original role holder should not have role");
        assertTrue(mockVault.hasRole(mainInvestorRole, user1), "New user should have role");
    }

    function testAutoRenewDisabledWhenEmergencyInvestorEqualsBackupAdmin() public {
        vm.startPrank(mainInvestor);
        vault.setAutoRenewWithdrawalLock(true);
        vm.stopPrank();

        assertTrue(vault.autoRenewWithdrawalLock(), "Auto-renewal should be enabled initially");

        vm.startPrank(emergencyInvestor);
        vault.grantRole(vault.EMERGENCY_INVESTOR_ROLE(), emergencyAdmin);
        vm.stopPrank();

        assertFalse(vault.autoRenewWithdrawalLock(), "Auto-renewal should be disabled after granting role");
    }

    function testAutoRenewEventEmittedWhenDisabled() public {
        vm.startPrank(mainInvestor);
        vault.setAutoRenewWithdrawalLock(true);
        vm.stopPrank();

        vm.recordLogs();

        vm.startPrank(emergencyInvestor);
        vault.grantRole(vault.EMERGENCY_INVESTOR_ROLE(), emergencyAdmin);
        vm.stopPrank();

        Vm.Log[] memory entries = vm.getRecordedLogs();

        bool foundEvent = false;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("AutoRenewWithdrawalLockSet(bool,bool)")) {
                foundEvent = true;
                (bool oldValue, bool newValue) = abi.decode(entries[i].data, (bool, bool));
                assertTrue(oldValue, "Old value should be true");
                assertFalse(newValue, "New value should be false");
                break;
            }
        }
        assertTrue(foundEvent, "AutoRenewWithdrawalLockSet event should be emitted");
    }

    function testWithdrawalLockAutoRenewal() public {
        vm.startPrank(mainInvestor);
        vault.setAutoRenewWithdrawalLock(true);

        vault.setWithdrawalLock(365 days);
        uint64 initialLockUntil = vault.withdrawalLockedUntil();

        uint256 timeToMove = 365 days - 7 days + 1;
        vm.warp(block.timestamp + timeToMove);

        token.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(token, DEPOSIT_AMOUNT);

        vm.expectEmit(false, false, false, true);
        emit WithdrawalLockAutoRenewed(uint64(initialLockUntil + 365 days));

        vm.expectRevert(MainVault.WithdrawalLocked.selector);
        vault.withdraw(IERC20(address(token)), DEPOSIT_AMOUNT);

        vm.warp(block.timestamp + 8 days);

        vm.expectRevert(MainVault.WithdrawalLocked.selector);
        vault.withdraw(IERC20(address(token)), DEPOSIT_AMOUNT);

        vm.stopPrank();
    }

    function testWithdrawalLockNotRenewedWhenDisabled() public {
        vm.startPrank(mainInvestor);

        vault.setWithdrawalLock(365 days);
        uint64 initialLockUntil = vault.withdrawalLockedUntil();

        uint256 timeToMove = 365 days - Constants.AUTO_RENEW_CHECK_PERIOD + 1;
        vm.warp(block.timestamp + timeToMove);

        token.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(token, DEPOSIT_AMOUNT);

        vm.expectRevert(MainVault.WithdrawalLocked.selector);
        vault.withdraw(IERC20(address(token)), DEPOSIT_AMOUNT);

        assertEq(vault.withdrawalLockedUntil(), initialLockUntil, "Lock period should not be extended");
        vm.stopPrank();
    }

    function testWithdrawalLockNotRenewedWhenNotNearExpiry() public {
        vm.warp(block.timestamp + 365 days);
        vm.startPrank(mainInvestor);

        vault.setAutoRenewWithdrawalLock(true);

        vault.setWithdrawalLock(365 days);
        uint64 initialLockUntil = vault.withdrawalLockedUntil();

        uint256 timeToMove = 365 days - Constants.AUTO_RENEW_CHECK_PERIOD - 1 days;
        vm.warp(block.timestamp + timeToMove);

        token.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(token, DEPOSIT_AMOUNT);

        vm.expectRevert(MainVault.WithdrawalLocked.selector);
        vault.withdraw(IERC20(address(token)), DEPOSIT_AMOUNT);

        assertEq(vault.withdrawalLockedUntil(), initialLockUntil, "Lock period should not be extended");
        vm.stopPrank();
    }

    function testWithdrawalLockRenewalEvent() public {
        vm.startPrank(mainInvestor);
        vault.setWithdrawalLock(365 days);

        vault.setAutoRenewWithdrawalLock(true);
        uint64 initialLockUntil = vault.withdrawalLockedUntil();
        console.log("initialLockUntil", initialLockUntil);

        uint256 timeToMove = 365 days - Constants.AUTO_RENEW_CHECK_PERIOD + 1;
        vm.warp(block.timestamp + timeToMove);

        vm.recordLogs();

        token.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(token, DEPOSIT_AMOUNT);
        vm.expectRevert(MainVault.WithdrawalLocked.selector);
        vault.withdraw(IERC20(address(token)), DEPOSIT_AMOUNT);

        Vm.Log[] memory entries = vm.getRecordedLogs();

        bool foundEvent = false;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("WithdrawalLockAutoRenewed(uint64)")) {
                foundEvent = true;
                uint64 newLockUntil = abi.decode(entries[i].data, (uint64));
                assertEq(
                    newLockUntil,
                    uint64(initialLockUntil + Constants.AUTO_RENEW_PERIOD),
                    "New lock timestamp should be extended by AUTO_RENEW_PERIOD"
                );
                break;
            }
        }
        assertTrue(foundEvent, "WithdrawalLockAutoRenewed event should be emitted");
        vm.stopPrank();
    }

    function testUpgradeAuthorization() public {
        address newImplementation = address(new MainVaultV2());

        // Both admin and investor approve
        vm.prank(admin);
        vault.approveMainVaultUpgrade(newImplementation);

        vm.prank(mainInvestor);
        vault.approveMainVaultUpgrade(newImplementation);

        // Verify approval state
        assertEq(vault.adminApprovedMainVaultImpl(), newImplementation);
        assertEq(vault.investorApprovedMainVaultImpl(), newImplementation);

        vm.expectEmit(true, true, true, true);
        emit Upgraded(newImplementation);

        vm.prank(admin);
        UUPSUpgradeable(address(vault)).upgradeToAndCall(newImplementation, "");

        // Verify approval state is cleared
        assertEq(vault.adminApprovedMainVaultImpl(), address(0));
        assertEq(vault.investorApprovedMainVaultImpl(), address(0));
    }

    function testUpgradeAuthorization_OnlyAdminOrInvestorCanUpgrade() public {
        address newImplementation = address(new MainVaultV2());

        // Both approve
        vm.prank(admin);
        vault.approveMainVaultUpgrade(newImplementation);

        vm.prank(mainInvestor);
        vault.approveMainVaultUpgrade(newImplementation);

        // User cannot upgrade
        vm.prank(user1);
        vm.expectRevert(MainVault.AccessDenied.selector);
        UUPSUpgradeable(address(vault)).upgradeToAndCall(newImplementation, "");

        // Admin can upgrade
        vm.prank(admin);
        UUPSUpgradeable(address(vault)).upgradeToAndCall(newImplementation, "");
    }

    function testUpgradeAuthorization_InvestorCanAlsoUpgrade() public {
        address newImplementation = address(new MainVaultV2());

        // Both approve
        vm.prank(admin);
        vault.approveMainVaultUpgrade(newImplementation);

        vm.prank(mainInvestor);
        vault.approveMainVaultUpgrade(newImplementation);

        // Investor can upgrade
        vm.prank(mainInvestor);
        UUPSUpgradeable(address(vault)).upgradeToAndCall(newImplementation, "");
    }

    function testUpgradeAuthorization_DifferentApprovals() public {
        address implementation1 = address(new MainVaultV2());
        address implementation2 = address(new MainVaultV2());

        // Admin approves one
        vm.prank(admin);
        vault.approveMainVaultUpgrade(implementation1);

        // Investor approves different one
        vm.prank(mainInvestor);
        vault.approveMainVaultUpgrade(implementation2);

        // Cannot upgrade to either
        vm.prank(admin);
        vm.expectRevert(MainVault.ImplementationNotApprovedByInvestor.selector);
        UUPSUpgradeable(address(vault)).upgradeToAndCall(implementation1, "");

        vm.prank(admin);
        vm.expectRevert(MainVault.ImplementationNotApprovedByAdmin.selector);
        UUPSUpgradeable(address(vault)).upgradeToAndCall(implementation2, "");
    }

    function testUpgradeAuthorization_ExpiredDeadline() public {
        address newImplementation = address(new MainVaultV2());

        // Both approve
        vm.prank(admin);
        vault.approveMainVaultUpgrade(newImplementation);

        vm.prank(mainInvestor);
        vault.approveMainVaultUpgrade(newImplementation);

        // Warp past deadline
        vm.warp(block.timestamp + vault.UPGRADE_TIME_LIMIT() + 1);

        vm.prank(admin);
        vm.expectRevert(MainVault.UpgradeDeadlineExpired.selector);
        UUPSUpgradeable(address(vault)).upgradeToAndCall(newImplementation, "");
    }

    function testUpgradeAuthorization_NoApprovals() public {
        address newImplementation = address(new MainVaultV2());

        vm.prank(admin);
        vm.expectRevert(MainVault.ImplementationNotApprovedByAdmin.selector);
        UUPSUpgradeable(address(vault)).upgradeToAndCall(newImplementation, "");
    }

    function testUpgradeAuthorization_OnlyAdminApproved() public {
        address newImplementation = address(new MainVaultV2());

        // Only admin approves
        vm.prank(admin);
        vault.approveMainVaultUpgrade(newImplementation);

        vm.prank(admin);
        vm.expectRevert(MainVault.ImplementationNotApprovedByInvestor.selector);
        UUPSUpgradeable(address(vault)).upgradeToAndCall(newImplementation, "");
    }

    function testUpgradeAuthorization_OnlyInvestorApproved() public {
        address newImplementation = address(new MainVaultV2());

        // Only investor approves
        vm.prank(mainInvestor);
        vault.approveMainVaultUpgrade(newImplementation);

        vm.prank(mainInvestor);
        vm.expectRevert(MainVault.ImplementationNotApprovedByAdmin.selector);
        UUPSUpgradeable(address(vault)).upgradeToAndCall(newImplementation, "");
    }

    // Test removed: testDeployInvestmentVault_ZeroImplementation
    // This test is no longer applicable because:
    // 1. Zero address cannot be approved via approveInvestorVaultUpgrade (checks for InvalidUpgradeAddress)
    // 2. Without approval, zero address cannot be set as currentImplementationOfInvestmentVault
    // 3. The zero address validation now happens at the approval stage, not deployment stage
    // Zero address validation is now tested in testApproveInvestorVaultUpgrade_ZeroAddress

    function testDeployInvestmentVault_TokenNotAvailable() public {
        vm.startPrank(mainInvestor);
        token.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(token, DEPOSIT_AMOUNT);
        vm.stopPrank();

        vm.startPrank(admin);
        DataTypes.AssetInitData[] memory assets = new DataTypes.AssetInitData[](1);
        assets[0] = DataTypes.AssetInitData({
            token: IERC20(address(token)),
            shareMV: Constants.SHARE_DENOMINATOR,
            step: 300,
            strategy: DataTypes.Strategy.Zero
        });

        DataTypes.InvestmentVaultInitData memory initData = DataTypes.InvestmentVaultInitData({
            mainVault: DataTypesIMainVault(address(vault)),
            tokenMI: IERC20(address(token)),
            tokenMV: IERC20(address(token)),
            capitalOfMi: DEPOSIT_AMOUNT / 2,
            shareMI: Constants.SHARE_DENOMINATOR,
            step: 5 * 10 ** 16,
            assets: assets
        });

        // Set token as unavailable
        vm.stopPrank();
        vm.startPrank(mainInvestor);
        IMainVault.TokenAvailability[] memory tokenConfigs = new IMainVault.TokenAvailability[](1);
        tokenConfigs[0] = IMainVault.TokenAvailability({token: address(token), isAvailable: false});
        vault.setTokenAvailabilityByInvestor(tokenConfigs);
        vm.stopPrank();

        vm.startPrank(admin);
        vm.expectRevert(MainVault.TokenNotAvailable.selector);
        vault.deployInvestmentVault(initData);
        vm.stopPrank();
    }

    function testDeployInvestmentVault_InvalidMainVaultAddress() public {
        vm.startPrank(mainInvestor);
        token.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(token, DEPOSIT_AMOUNT);
        vm.stopPrank();

        vm.startPrank(admin);
        DataTypes.AssetInitData[] memory assets = new DataTypes.AssetInitData[](1);
        assets[0] = DataTypes.AssetInitData({
            token: IERC20(address(token)),
            shareMV: Constants.SHARE_DENOMINATOR,
            step: 300,
            strategy: DataTypes.Strategy.Zero
        });

        DataTypes.InvestmentVaultInitData memory initData = DataTypes.InvestmentVaultInitData({
            mainVault: DataTypesIMainVault(address(0)), // Set invalid main vault address
            tokenMI: IERC20(address(token)),
            tokenMV: IERC20(address(token)),
            capitalOfMi: DEPOSIT_AMOUNT / 2,
            shareMI: Constants.SHARE_DENOMINATOR,
            step: 5 * 10 ** 16,
            assets: assets
        });

        vm.expectRevert(MainVault.InvalidMainVaultAddress.selector);
        vault.deployInvestmentVault(initData);
        vm.stopPrank();
    }

    function testDeployInvestmentVault_ZerocapitalOfMi() public {
        vm.startPrank(mainInvestor);
        token.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(token, DEPOSIT_AMOUNT);
        vm.stopPrank();

        vm.startPrank(admin);
        DataTypes.AssetInitData[] memory assets = new DataTypes.AssetInitData[](1);
        assets[0] = DataTypes.AssetInitData({
            token: IERC20(address(token)),
            shareMV: Constants.SHARE_DENOMINATOR,
            step: 300,
            strategy: DataTypes.Strategy.Zero
        });

        DataTypes.InvestmentVaultInitData memory initData = DataTypes.InvestmentVaultInitData({
            mainVault: DataTypesIMainVault(address(vault)),
            tokenMI: IERC20(address(token)),
            tokenMV: IERC20(address(token)),
            capitalOfMi: 0, // Set zero init deposit
            shareMI: Constants.SHARE_DENOMINATOR,
            step: 5 * 10 ** 16,
            assets: assets
        });

        vm.expectRevert(MainVault.ZeroAmountNotAllowed.selector);
        vault.deployInvestmentVault(initData);
        vm.stopPrank();
    }

    function testDeployInvestmentVault_InsufficientBalance() public {
        vm.startPrank(mainInvestor);
        token.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(token, DEPOSIT_AMOUNT);
        vm.stopPrank();

        vm.startPrank(admin);
        DataTypes.AssetInitData[] memory assets = new DataTypes.AssetInitData[](1);
        assets[0] = DataTypes.AssetInitData({
            token: IERC20(address(token)),
            shareMV: Constants.SHARE_DENOMINATOR,
            step: 300,
            strategy: DataTypes.Strategy.Zero
        });

        DataTypes.InvestmentVaultInitData memory initData = DataTypes.InvestmentVaultInitData({
            mainVault: DataTypesIMainVault(address(vault)),
            tokenMI: IERC20(address(token)),
            tokenMV: IERC20(address(token)),
            capitalOfMi: DEPOSIT_AMOUNT * 2, // Request more than available balance
            shareMI: Constants.SHARE_DENOMINATOR,
            step: 5 * 10 ** 16,
            assets: assets
        });

        vm.expectRevert(MainVault.InsufficientBalance.selector);
        vault.deployInvestmentVault(initData);
        vm.stopPrank();
    }

    function testSetWithdrawalLock_PeriodNotAvailable() public {
        vm.startPrank(mainInvestor);

        // Try to set withdrawal lock with a period that hasn't been made available
        uint256 unavailablePeriod = 15 days;
        vm.expectRevert(MainVault.LockPeriodNotAvailable.selector);
        vault.setWithdrawalLock(unavailablePeriod);

        // Make the period available
        vm.stopPrank();
        vm.startPrank(admin);
        IMainVault.LockPeriodAvailability[] memory configs = new IMainVault.LockPeriodAvailability[](1);
        configs[0] = IMainVault.LockPeriodAvailability({period: unavailablePeriod, isAvailable: true});
        vault.setLockPeriodsAvailability(configs);
        vm.stopPrank();

        // Now try to set the withdrawal lock again
        vm.startPrank(mainInvestor);
        vault.setWithdrawalLock(unavailablePeriod);
        assertEq(
            vault.withdrawalLockedUntil(),
            uint64(block.timestamp + unavailablePeriod),
            "Lock period should be set correctly"
        );
        vm.stopPrank();
    }

    function testDeposit_TokenNotAvailable() public {
        vm.startPrank(mainInvestor);

        // Make token unavailable
        IMainVault.TokenAvailability[] memory tokenConfigs = new IMainVault.TokenAvailability[](1);
        tokenConfigs[0] = IMainVault.TokenAvailability({token: address(token), isAvailable: false});
        vault.setTokenAvailabilityByInvestor(tokenConfigs);

        // Try to deposit with unavailable token
        token.approve(address(vault), DEPOSIT_AMOUNT);
        vm.expectRevert(MainVault.TokenNotAvailable.selector);
        vault.deposit(token, DEPOSIT_AMOUNT);

        // Make token available again
        tokenConfigs[0] = IMainVault.TokenAvailability({token: address(token), isAvailable: true});
        vault.setTokenAvailabilityByInvestor(tokenConfigs);

        // Now deposit should work
        vault.deposit(token, DEPOSIT_AMOUNT);
        assertEq(token.balanceOf(address(vault)), DEPOSIT_AMOUNT, "Token balance should be correct after deposit");
        vm.stopPrank();
    }

    function testDeposit_ZeroAmount() public {
        vm.startPrank(mainInvestor);

        // Try to deposit zero amount
        token.approve(address(vault), 0);
        vm.expectRevert(MainVault.ZeroAmountNotAllowed.selector);
        vault.deposit(token, 0);

        // Deposit non-zero amount should work
        token.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(token, DEPOSIT_AMOUNT);
        assertEq(token.balanceOf(address(vault)), DEPOSIT_AMOUNT, "Token balance should be correct after deposit");
        vm.stopPrank();
    }

    function testExactInputSingle_DuringAndAfterSetupPause() public {
        uint64 initialTime = uint64(block.timestamp) + 1 days;
        vm.warp(initialTime);

        uint64 lockDuration = 2 hours;
        address routerAddress = address(0x1337);

        vm.stopPrank();
        vm.startPrank(admin);
        // 1. Make lock period available
        IMainVault.LockPeriodAvailability[] memory lockConfigs = new IMainVault.LockPeriodAvailability[](1);
        lockConfigs[0] = IMainVault.LockPeriodAvailability({period: lockDuration, isAvailable: true});
        vault.setLockPeriodsAvailability(lockConfigs);

        IMainVault.TokenAvailability[] memory adminTokenConfigs = new IMainVault.TokenAvailability[](2);
        adminTokenConfigs[0] = IMainVault.TokenAvailability({token: address(token), isAvailable: true});
        adminTokenConfigs[1] = IMainVault.TokenAvailability({token: address(secondToken), isAvailable: true});
        vault.setTokenAvailabilityByAdmin(adminTokenConfigs);

        IMainVault.RouterAvailability[] memory adminRouterConfigs = new IMainVault.RouterAvailability[](1);
        adminRouterConfigs[0] = IMainVault.RouterAvailability({router: routerAddress, isAvailable: true});
        vault.setRouterAvailabilityByAdmin(adminRouterConfigs);
        vm.stopPrank();

        vm.startPrank(mainInvestor);

        vault.setWithdrawalLock(lockDuration);
        assertTrue(vault.withdrawalLockedUntil() > block.timestamp, "Withdrawal lock should be active");

        IMainVault.TokenAvailability[] memory investorTokenConfigs = new IMainVault.TokenAvailability[](1);
        investorTokenConfigs[0] = IMainVault.TokenAvailability({token: address(token), isAvailable: true});
        vault.setTokenAvailabilityByInvestor(investorTokenConfigs);

        uint64 pauseUntil = vault.pauseToTimestamp();
        assertTrue(pauseUntil > block.timestamp, "pauseToTimestamp should be set and in the future.");

        DataTypes.DelegateExactInputSingleParams memory params = DataTypes.DelegateExactInputSingleParams({
            router: routerAddress,
            tokenIn: address(token),
            tokenOut: address(secondToken),
            fee: 3000,
            deadline: block.timestamp + 1 hours,
            amountIn: 1 * 10 ** 18,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0,
            swapType: DataTypes.SwapType.Default
        });

        vm.expectRevert(MainVault.InitializePause.selector);
        vault.exactInputSingle(params);

        vm.stopPrank();
    }

    function testSetInvestorIsCanceledOracleCheck() public {
        // Initially both checks should be true because meraPriceOracle is address(0)
        assertTrue(vault.isCanceledOracleCheck(), "Initial oracle check state should be true");

        // Only MAIN_INVESTOR_ROLE can set investor check
        vm.startPrank(user1);
        vm.expectRevert();
        vault.setInvestorIsCanceledOracleCheck(false);
        vm.stopPrank();

        // MAIN_INVESTOR_ROLE can set the check
        vm.startPrank(mainInvestor);
        vault.setInvestorIsCanceledOracleCheck(false);
        vm.stopPrank();

        // Check should be false because investor check is false
        assertFalse(vault.isCanceledOracleCheck(), "Oracle check should be false when investor check is false");

        // Set it back to true
        vm.startPrank(mainInvestor);
        vault.setInvestorIsCanceledOracleCheck(true);
        vm.stopPrank();

        assertTrue(vault.isCanceledOracleCheck(), "Oracle check should be true when both checks are true");
    }

    function testSetAdminIsCanceledOracleCheck() public {
        // Initially both checks should be true because meraPriceOracle is address(0)
        assertTrue(vault.isCanceledOracleCheck(), "Initial oracle check state should be true");

        // Only ADMIN_ROLE can set admin check
        vm.startPrank(user1);
        vm.expectRevert();
        vault.setAdminIsCanceledOracleCheck(false);
        vm.stopPrank();

        // ADMIN_ROLE can set the check
        vm.startPrank(admin);
        vault.setAdminIsCanceledOracleCheck(false);
        vm.stopPrank();

        // Check should be false because admin check is false
        assertFalse(vault.isCanceledOracleCheck(), "Oracle check should be false when admin check is false");

        // Set it back to true
        vm.startPrank(admin);
        vault.setAdminIsCanceledOracleCheck(true);
        vm.stopPrank();

        assertTrue(vault.isCanceledOracleCheck(), "Oracle check should be true when both checks are true");
    }

    function testIsCanceledOracleCheck() public {
        // Initially both checks should be true because meraPriceOracle is address(0)
        assertTrue(vault.isCanceledOracleCheck(), "Initial oracle check state should be true");

        // Set investor check to false
        vm.startPrank(mainInvestor);
        vault.setInvestorIsCanceledOracleCheck(false);
        vm.stopPrank();

        // Check should be false when investor check is false
        assertFalse(vault.isCanceledOracleCheck(), "Oracle check should be false when investor check is false");

        // Set admin check to false
        vm.startPrank(admin);
        vault.setAdminIsCanceledOracleCheck(false);
        vm.stopPrank();

        // Check should still be false
        assertFalse(vault.isCanceledOracleCheck(), "Oracle check should be false when both checks are false");

        // Set investor check back to true
        vm.startPrank(mainInvestor);
        vault.setInvestorIsCanceledOracleCheck(true);
        vm.stopPrank();

        // Check should still be false because admin check is false
        assertFalse(vault.isCanceledOracleCheck(), "Oracle check should be false when only investor check is true");

        // Set admin check back to true
        vm.startPrank(admin);
        vault.setAdminIsCanceledOracleCheck(true);
        vm.stopPrank();

        // Now both checks are true again
        assertTrue(vault.isCanceledOracleCheck(), "Oracle check should be true when both checks are true");
    }

    function testSetProfitType() public {
        vm.startPrank(mainInvestor);

        vault.setProfitType(DataTypes.ProfitType.Dynamic);
        assertEq(uint8(vault.profitType()), uint8(DataTypes.ProfitType.Dynamic), "Profit type should be set to Dynamic");

        vault.setProfitType(DataTypes.ProfitType.Fixed);
        assertEq(uint8(vault.profitType()), uint8(DataTypes.ProfitType.Fixed), "Profit type should be set to Fixed");

        vm.stopPrank();
    }

    function testSetProfitType_OnlyMainInvestor() public {
        vm.startPrank(user1);
        vm.expectRevert();
        vault.setProfitType(DataTypes.ProfitType.Dynamic);
        vm.stopPrank();

        vm.startPrank(admin);
        vm.expectRevert();
        vault.setProfitType(DataTypes.ProfitType.Dynamic);
        vm.stopPrank();
    }

    function testSetProfitType_EmitsEvent() public {
        vm.startPrank(mainInvestor);

        vm.expectEmit(false, false, false, true);
        emit ProfitTypeSet(DataTypes.ProfitType.Dynamic);
        vault.setProfitType(DataTypes.ProfitType.Dynamic);

        vm.stopPrank();
    }

    function testSetProposedFixedProfitPercentByAdmin() public {
        vm.startPrank(admin);

        uint32 newPercent = 1000; // 10%
        vault.setProposedFixedProfitPercentByAdmin(newPercent);
        assertEq(
            vault.proposedFixedProfitPercentByAdmin(), newPercent, "Proposed fixed profit percent should be updated"
        );

        vm.stopPrank();
    }

    function testSetProposedFixedProfitPercentByAdmin_OnlyAdmin() public {
        uint32 newPercent = 1000;

        vm.startPrank(user1);
        vm.expectRevert();
        vault.setProposedFixedProfitPercentByAdmin(newPercent);
        vm.stopPrank();

        vm.startPrank(mainInvestor);
        vm.expectRevert();
        vault.setProposedFixedProfitPercentByAdmin(newPercent);
        vm.stopPrank();
    }

    function testSetProposedFixedProfitPercentByAdmin_ZeroAmount() public {
        vm.startPrank(admin);

        vm.expectRevert(MainVault.ZeroAmountNotAllowed.selector);
        vault.setProposedFixedProfitPercentByAdmin(0);

        vm.stopPrank();
    }

    function testSetProposedFixedProfitPercentByAdmin_ExceedsMaximum() public {
        vm.startPrank(admin);

        vm.expectRevert(MainVault.ExceedsMaximumPercentage.selector);
        vault.setProposedFixedProfitPercentByAdmin(uint32(Constants.MAX_FIXED_PROFIT_PERCENT + 1));

        vm.stopPrank();
    }

    function testSetProposedFixedProfitPercentByAdmin_EmitsEvent() public {
        vm.startPrank(admin);

        uint32 newPercent = 1000;
        vm.expectEmit(false, false, false, true);
        emit ProposedFixedProfitPercentByAdminSet(newPercent);
        vault.setProposedFixedProfitPercentByAdmin(newPercent);

        vm.stopPrank();
    }

    function testSetCurrentFixedProfitPercent() public {
        vm.startPrank(admin);
        uint32 proposedPercent = 1000;
        vault.setProposedFixedProfitPercentByAdmin(proposedPercent);
        vm.stopPrank();

        vm.startPrank(mainInvestor);
        vault.setCurrentFixedProfitPercent();
        assertEq(vault.currentFixedProfitPercent(), proposedPercent, "Current fixed profit percent should be updated");
        vm.stopPrank();
    }

    function testSetCurrentFixedProfitPercent_OnlyMainInvestor() public {
        vm.startPrank(user1);
        vm.expectRevert();
        vault.setCurrentFixedProfitPercent();
        vm.stopPrank();

        vm.startPrank(admin);
        vm.expectRevert();
        vault.setCurrentFixedProfitPercent();
        vm.stopPrank();
    }

    function testSetCurrentFixedProfitPercent_EmitsEvent() public {
        vm.startPrank(admin);
        uint32 proposedPercent = 1000;
        vault.setProposedFixedProfitPercentByAdmin(proposedPercent);
        vm.stopPrank();

        vm.startPrank(mainInvestor);

        uint32 oldPercent = vault.currentFixedProfitPercent();
        vm.expectEmit(false, false, false, true);
        emit CurrentFixedProfitPercentSet(oldPercent, proposedPercent);
        vault.setCurrentFixedProfitPercent();

        vm.stopPrank();
    }

    function testSetCurrentFixedProfitPercent_UpdatesValue() public {
        vm.startPrank(admin);
        uint32 firstProposedPercent = 1000;
        vault.setProposedFixedProfitPercentByAdmin(firstProposedPercent);
        vm.stopPrank();

        vm.startPrank(mainInvestor);
        vault.setCurrentFixedProfitPercent();
        assertEq(vault.currentFixedProfitPercent(), firstProposedPercent, "First update should set correct value");

        vm.stopPrank();
        vm.startPrank(admin);
        uint32 secondProposedPercent = 2000;
        vault.setProposedFixedProfitPercentByAdmin(secondProposedPercent);
        vm.stopPrank();

        vm.startPrank(mainInvestor);
        vault.setCurrentFixedProfitPercent();
        assertEq(vault.currentFixedProfitPercent(), secondProposedPercent, "Second update should set correct value");
        vm.stopPrank();
    }

    function testCheckAndRenewWithdrawalLock_AutoRenewDisabled() public {
        vm.startPrank(mainInvestor);
        // Set a withdrawal lock but keep auto-renew disabled
        vault.setWithdrawalLock(365 days);
        vm.stopPrank();

        // Move time close to expiry but not enough to trigger renewal
        vm.warp(vault.withdrawalLockedUntil() - Constants.AUTO_RENEW_CHECK_PERIOD + 1);

        vm.startPrank(admin);
        bool renewed = vault.checkAndRenewWithdrawalLock();
        assertFalse(renewed, "Should not renew when auto-renew is disabled");
        vm.stopPrank();
    }

    function testCheckAndRenewWithdrawalLock_NoActiveLock() public {
        vm.startPrank(mainInvestor);
        // Enable auto-renew but don't set any withdrawal lock
        vault.setAutoRenewWithdrawalLock(true);
        vm.stopPrank();

        vm.startPrank(admin);
        bool renewed = vault.checkAndRenewWithdrawalLock();
        assertTrue(renewed, "Should renew when there's no active lock");
        vm.stopPrank();
    }

    function testCheckAndRenewWithdrawalLock_NotNearExpiry() public {
        vm.startPrank(mainInvestor);
        vault.setWithdrawalLock(365 days);
        vault.setAutoRenewWithdrawalLock(true);
        vm.stopPrank();

        // Move time but not close enough to expiry
        vm.warp(vault.withdrawalLockedUntil() - Constants.AUTO_RENEW_CHECK_PERIOD - 1 days);

        vm.startPrank(admin);
        bool renewed = vault.checkAndRenewWithdrawalLock();
        assertFalse(renewed, "Should not renew when not near expiry");
        vm.stopPrank();
    }

    function testCheckAndRenewWithdrawalLock_SuccessfulRenewal() public {
        vm.startPrank(mainInvestor);
        vault.setWithdrawalLock(365 days);
        vault.setAutoRenewWithdrawalLock(true);
        vm.stopPrank();

        uint64 initialLockUntil = vault.withdrawalLockedUntil();

        // Move time close to expiry to trigger renewal
        vm.warp(initialLockUntil - Constants.AUTO_RENEW_CHECK_PERIOD + 1);

        vm.startPrank(admin);
        bool renewed = vault.checkAndRenewWithdrawalLock();
        assertTrue(renewed, "Should renew when all conditions are met");

        // Check that lock was extended
        assertEq(
            vault.withdrawalLockedUntil(),
            initialLockUntil + Constants.AUTO_RENEW_PERIOD,
            "Lock should be extended by AUTO_RENEW_PERIOD"
        );
        vm.stopPrank();
    }

    function testCheckAndRenewWithdrawalLock_EmitsEvent() public {
        vm.startPrank(mainInvestor);
        vault.setWithdrawalLock(365 days);
        vault.setAutoRenewWithdrawalLock(true);
        vm.stopPrank();

        uint64 initialLockUntil = vault.withdrawalLockedUntil();

        // Move time close to expiry to trigger renewal
        vm.warp(initialLockUntil - Constants.AUTO_RENEW_CHECK_PERIOD + 1);

        vm.startPrank(admin);

        vm.expectEmit(false, false, false, true);
        emit WithdrawalLockAutoRenewed(uint64(initialLockUntil + Constants.AUTO_RENEW_PERIOD));

        vault.checkAndRenewWithdrawalLock();
        vm.stopPrank();
    }

    function testCheckAndRenewWithdrawalLock_OnlyAdminCanCall() public {
        vm.startPrank(mainInvestor);
        vault.setWithdrawalLock(365 days);
        vault.setAutoRenewWithdrawalLock(true);
        vm.stopPrank();

        // Move time close to expiry
        vm.warp(vault.withdrawalLockedUntil() - Constants.AUTO_RENEW_CHECK_PERIOD + 1);

        // Test that non-admin addresses cannot call the function
        vm.startPrank(user1);
        vm.expectRevert();
        vault.checkAndRenewWithdrawalLock();
        vm.stopPrank();

        vm.startPrank(mainInvestor);
        vm.expectRevert();
        vault.checkAndRenewWithdrawalLock();
        vm.stopPrank();

        // Admin should be able to call it
        vm.startPrank(admin);
        bool renewed = vault.checkAndRenewWithdrawalLock();
        assertTrue(renewed, "Admin should be able to trigger renewal");
        vm.stopPrank();
    }

    function testCheckAndRenewWithdrawalLock_MultipleRenewals() public {
        vm.startPrank(mainInvestor);
        vault.setWithdrawalLock(365 days);
        vault.setAutoRenewWithdrawalLock(true);
        vm.stopPrank();

        uint64 firstLockUntil = vault.withdrawalLockedUntil();

        // First renewal
        vm.warp(firstLockUntil - Constants.AUTO_RENEW_CHECK_PERIOD + 1);

        vm.startPrank(admin);
        bool firstRenewal = vault.checkAndRenewWithdrawalLock();
        assertTrue(firstRenewal, "First renewal should succeed");

        uint64 secondLockUntil = vault.withdrawalLockedUntil();
        assertEq(
            secondLockUntil, firstLockUntil + Constants.AUTO_RENEW_PERIOD, "First renewal should extend lock correctly"
        );

        // Try calling again immediately - should not renew since not near expiry anymore
        bool immediateRenewal = vault.checkAndRenewWithdrawalLock();
        assertFalse(immediateRenewal, "Should not renew again immediately");
        assertEq(vault.withdrawalLockedUntil(), secondLockUntil, "Lock time should not change on failed renewal");

        // Second renewal when near expiry again
        vm.warp(secondLockUntil - Constants.AUTO_RENEW_CHECK_PERIOD + 1);
        bool secondRenewal = vault.checkAndRenewWithdrawalLock();
        assertTrue(secondRenewal, "Second renewal should succeed");

        assertEq(
            vault.withdrawalLockedUntil(),
            secondLockUntil + Constants.AUTO_RENEW_PERIOD,
            "Second renewal should extend lock correctly"
        );
        vm.stopPrank();
    }

    function testCheckAndRenewWithdrawalLock_ExactBoundaryConditions() public {
        vm.startPrank(mainInvestor);
        vault.setWithdrawalLock(365 days);
        vault.setAutoRenewWithdrawalLock(true);
        vm.stopPrank();

        uint64 lockUntil = vault.withdrawalLockedUntil();

        vm.startPrank(admin);

        // Test exactly at the boundary (should not renew)
        vm.warp(lockUntil - Constants.AUTO_RENEW_CHECK_PERIOD - 1);
        bool renewalAtBoundary = vault.checkAndRenewWithdrawalLock();
        assertFalse(renewalAtBoundary, "Should not renew exactly at boundary");

        // Test one second past boundary (should renew)
        vm.warp(lockUntil - Constants.AUTO_RENEW_CHECK_PERIOD);
        bool renewalPastBoundary = vault.checkAndRenewWithdrawalLock();
        assertTrue(renewalPastBoundary, "Should renew one second past boundary");

        vm.stopPrank();
    }

    // Tests for setWithdrawalLockWithAutoRenew function
    function testSetWithdrawalLockWithAutoRenew_BasicFunctionality() public {
        vm.startPrank(mainInvestor);

        uint256 lockPeriod = 365 days;
        bool autoRenewEnabled = true;

        // Account for existing withdrawal lock that might be longer than the new period
        uint64 currentLockUntil = vault.withdrawalLockedUntil();
        uint64 expectedLockUntil = uint64(Math.max(currentLockUntil, block.timestamp + lockPeriod));

        // Test setting withdrawal lock with auto-renewal enabled
        vm.expectEmit(true, true, true, true);
        emit WithdrawalLockSet(lockPeriod, expectedLockUntil);

        vm.expectEmit(true, true, true, true);
        emit AutoRenewWithdrawalLockSet(false, autoRenewEnabled);

        vault.setWithdrawalLockWithAutoRenew(lockPeriod, autoRenewEnabled);

        assertEq(vault.withdrawalLockedUntil(), expectedLockUntil, "Withdrawal lock should be set correctly");
        assertTrue(vault.autoRenewWithdrawalLock(), "Auto-renewal should be enabled");

        vm.stopPrank();
    }

    function testSetWithdrawalLockWithAutoRenew_DisableAutoRenew() public {
        vm.startPrank(mainInvestor);

        uint256 lockPeriod = 10 minutes;
        bool autoRenewEnabled = false;

        // Account for existing withdrawal lock that might be longer than the new period
        uint64 currentLockUntil = vault.withdrawalLockedUntil();
        uint64 expectedLockUntil = uint64(Math.max(currentLockUntil, block.timestamp + lockPeriod));

        // Test setting withdrawal lock with auto-renewal disabled
        vm.expectEmit(true, true, true, true);
        emit WithdrawalLockSet(lockPeriod, expectedLockUntil);

        vm.expectEmit(true, true, true, true);
        emit AutoRenewWithdrawalLockSet(false, autoRenewEnabled);

        vault.setWithdrawalLockWithAutoRenew(lockPeriod, autoRenewEnabled);

        assertEq(vault.withdrawalLockedUntil(), expectedLockUntil, "Withdrawal lock should be set correctly");
        assertFalse(vault.autoRenewWithdrawalLock(), "Auto-renewal should be disabled");

        vm.stopPrank();
    }

    function testSetWithdrawalLockWithAutoRenew_ExtendExistingLock() public {
        vm.startPrank(mainInvestor);

        // First, set an initial withdrawal lock
        uint256 initialPeriod = 365 days;
        vault.setWithdrawalLock(initialPeriod);
        uint64 initialLockUntil = vault.withdrawalLockedUntil();

        // Wait some time
        vm.warp(block.timestamp + 30 minutes);

        // Set a longer lock period with auto-renewal
        uint256 newPeriod = 365 days;
        uint64 expectedLockUntil = uint64(Math.max(initialLockUntil, block.timestamp + newPeriod));

        vault.setWithdrawalLockWithAutoRenew(newPeriod, true);

        assertGe(vault.withdrawalLockedUntil(), expectedLockUntil, "New lock should extend the existing lock");
        assertTrue(vault.autoRenewWithdrawalLock(), "Auto-renewal should be enabled");

        vm.stopPrank();
    }

    function testSetWithdrawalLockWithAutoRenew_ToggleAutoRenewFromEnabled() public {
        vm.startPrank(mainInvestor);

        // First enable auto-renewal
        vault.setAutoRenewWithdrawalLock(true);
        assertTrue(vault.autoRenewWithdrawalLock(), "Auto-renewal should be initially enabled");

        uint256 lockPeriod = 365 days;
        bool newAutoRenewValue = false;

        // Test disabling auto-renewal via combined function
        vm.expectEmit(true, true, true, true);
        emit AutoRenewWithdrawalLockSet(true, newAutoRenewValue);

        vault.setWithdrawalLockWithAutoRenew(lockPeriod, newAutoRenewValue);

        assertFalse(vault.autoRenewWithdrawalLock(), "Auto-renewal should be disabled");

        vm.stopPrank();
    }

    function testSetWithdrawalLockWithAutoRenew_PeriodNotAvailable() public {
        vm.startPrank(mainInvestor);

        // Try to set withdrawal lock with a period that hasn't been made available
        uint256 unavailablePeriod = 15 days;
        vm.expectRevert(MainVault.LockPeriodNotAvailable.selector);
        vault.setWithdrawalLockWithAutoRenew(unavailablePeriod, true);

        // Make the period available
        vm.stopPrank();
        vm.startPrank(admin);
        IMainVault.LockPeriodAvailability[] memory configs = new IMainVault.LockPeriodAvailability[](1);
        configs[0] = IMainVault.LockPeriodAvailability({period: unavailablePeriod, isAvailable: true});
        vault.setLockPeriodsAvailability(configs);
        vm.stopPrank();

        // Now the combined function should work
        vm.startPrank(mainInvestor);

        // Account for existing withdrawal lock that might be longer than the new period
        uint64 currentLockUntil = vault.withdrawalLockedUntil();
        uint64 expectedLockUntil = uint64(Math.max(currentLockUntil, block.timestamp + unavailablePeriod));

        vault.setWithdrawalLockWithAutoRenew(unavailablePeriod, true);

        assertEq(vault.withdrawalLockedUntil(), expectedLockUntil, "Lock period should be set correctly");
        assertTrue(vault.autoRenewWithdrawalLock(), "Auto-renewal should be enabled");

        vm.stopPrank();
    }

    function testSetWithdrawalLockWithAutoRenew_OnlyMainInvestorCanCall() public {
        uint256 lockPeriod = 365 days;

        // Test with user1
        vm.startPrank(user1);
        vm.expectRevert();
        vault.setWithdrawalLockWithAutoRenew(lockPeriod, true);
        vm.stopPrank();

        // Test with admin
        vm.startPrank(admin);
        vm.expectRevert();
        vault.setWithdrawalLockWithAutoRenew(lockPeriod, true);
        vm.stopPrank();

        // Test with backup investor
        vm.startPrank(backupInvestor);
        vm.expectRevert();
        vault.setWithdrawalLockWithAutoRenew(lockPeriod, true);
        vm.stopPrank();

        // Test with main investor (should work)
        vm.startPrank(mainInvestor);

        // Account for existing withdrawal lock that might be longer than the new period
        uint64 currentLockUntil = vault.withdrawalLockedUntil();
        uint64 expectedLockUntil = uint64(Math.max(currentLockUntil, block.timestamp + lockPeriod));

        vault.setWithdrawalLockWithAutoRenew(lockPeriod, true);

        assertEq(vault.withdrawalLockedUntil(), expectedLockUntil, "Lock should be set by main investor");
        assertTrue(vault.autoRenewWithdrawalLock(), "Auto-renewal should be enabled by main investor");

        vm.stopPrank();
    }

    function testSetWithdrawalLockWithAutoRenew_AutoExtendOnEnable() public {
        vm.startPrank(mainInvestor);

        // Set a withdrawal lock
        uint256 lockPeriod = 10 minutes;
        vault.setWithdrawalLock(lockPeriod);
        uint64 initialLockUntil = vault.withdrawalLockedUntil();

        // Move to near the end of the lock period (within AUTO_RENEW_CHECK_PERIOD)
        vm.warp(initialLockUntil - Constants.AUTO_RENEW_CHECK_PERIOD + 1);

        // Use combined function to enable auto-renewal
        // When auto-renewal is enabled and lock is about to expire, it should extend
        vault.setWithdrawalLockWithAutoRenew(lockPeriod, true);

        assertGt(
            vault.withdrawalLockedUntil(),
            initialLockUntil,
            "Lock should be extended when enabling auto-renewal near end"
        );
        assertTrue(vault.autoRenewWithdrawalLock(), "Auto-renewal should be enabled");

        vm.stopPrank();
    }

    function testSetWithdrawalLockWithAutoRenew_NoAutoExtendOnEnableEarly() public {
        vm.startPrank(mainInvestor);

        // Set a withdrawal lock
        uint256 lockPeriod = 365 days;
        vault.setWithdrawalLock(lockPeriod);
        uint64 initialLockUntil = vault.withdrawalLockedUntil();

        // Use combined function to enable auto-renewal while not near expiry
        vault.setWithdrawalLockWithAutoRenew(lockPeriod, true);

        // The lock period should be extended due to the new period being applied
        assertGe(
            vault.withdrawalLockedUntil(),
            uint64(block.timestamp + lockPeriod),
            "Lock should be set to at least the new period"
        );
        assertTrue(vault.autoRenewWithdrawalLock(), "Auto-renewal should be enabled");

        vm.stopPrank();
    }

    function testSetWithdrawalLockWithAutoRenew_EventsEmitted() public {
        vm.startPrank(mainInvestor);

        uint256 lockPeriod = 365 days;
        // Account for existing withdrawal lock that might be longer than the new period
        uint64 currentLockUntil = vault.withdrawalLockedUntil();
        uint64 expectedLockUntil = uint64(Math.max(currentLockUntil, block.timestamp + lockPeriod));

        // Test that both events are emitted in correct order
        vm.expectEmit(true, true, true, true);
        emit WithdrawalLockSet(lockPeriod, expectedLockUntil);

        vm.expectEmit(true, true, true, true);
        emit AutoRenewWithdrawalLockSet(false, true);

        vault.setWithdrawalLockWithAutoRenew(lockPeriod, true);

        vm.stopPrank();
    }

    // ============================= MeraPriceOracle Tests =============================

    function testSetProposedMeraPriceOracleByAdmin() public {
        address newOracle = makeAddr("newOracle");

        vm.startPrank(admin);
        vault.setProposedMeraPriceOracleByAdmin(newOracle);
        assertEq(vault.proposedMeraPriceOracleByAdmin(), newOracle, "Proposed oracle should be updated");
        vm.stopPrank();
    }

    function testSetProposedMeraPriceOracleByAdmin_OnlyAdmin() public {
        address newOracle = makeAddr("newOracle");

        vm.startPrank(user1);
        vm.expectRevert();
        vault.setProposedMeraPriceOracleByAdmin(newOracle);
        vm.stopPrank();
    }

    function testSetProposedMeraPriceOracleByAdmin_ZeroAddress() public {
        vm.startPrank(admin);
        vm.expectRevert();
        vault.setProposedMeraPriceOracleByAdmin(address(0));
        vm.stopPrank();
    }

    function testSetProposedMeraPriceOracleByAdmin_EmitsEvent() public {
        address newOracle = makeAddr("newOracle");

        vm.startPrank(admin);
        vm.expectEmit(true, true, true, true);
        emit ProposedMeraPriceOracleByAdminSet(newOracle);
        vault.setProposedMeraPriceOracleByAdmin(newOracle);
        vm.stopPrank();
    }

    function testSetCurrentMeraPriceOracle() public {
        address newOracle = makeAddr("newOracle");
        address oldOracle = address(vault.meraPriceOracle());

        // First admin proposes new oracle
        vm.startPrank(admin);
        vault.setProposedMeraPriceOracleByAdmin(newOracle);
        vm.stopPrank();

        // Then main investor confirms it
        vm.startPrank(mainInvestor);
        vault.setCurrentMeraPriceOracle();
        assertEq(address(vault.meraPriceOracle()), newOracle, "Oracle should be updated");
        assertEq(vault.proposedMeraPriceOracleByAdmin(), address(0), "Proposed oracle should be reset");
        vm.stopPrank();
    }

    function testSetCurrentMeraPriceOracle_OnlyMainInvestor() public {
        address newOracle = makeAddr("newOracle");

        // Admin proposes oracle first
        vm.startPrank(admin);
        vault.setProposedMeraPriceOracleByAdmin(newOracle);
        vm.stopPrank();

        // Try with non-main investor
        vm.startPrank(user1);
        vm.expectRevert();
        vault.setCurrentMeraPriceOracle();
        vm.stopPrank();
    }

    function testSetCurrentMeraPriceOracle_RequiresProposedOracle() public {
        vm.startPrank(mainInvestor);
        vm.expectRevert(); // Should revert because no oracle was proposed
        vault.setCurrentMeraPriceOracle();
        vm.stopPrank();
    }

    function testSetCurrentMeraPriceOracle_EmitsEvent() public {
        address newOracle = makeAddr("newOracle");
        address oldOracle = address(vault.meraPriceOracle());

        // Admin proposes oracle first
        vm.startPrank(admin);
        vault.setProposedMeraPriceOracleByAdmin(newOracle);
        vm.stopPrank();

        // Main investor confirms with event
        vm.startPrank(mainInvestor);
        vm.expectEmit(true, true, true, true);
        emit MeraPriceOracleSet(oldOracle, newOracle);
        vault.setCurrentMeraPriceOracle();
        vm.stopPrank();
    }

    // ============================= Initialize Lock Period Tests =============================

    function testExistingVault_InitializedWithZeroLockPeriod_AutoRenewDisabled() public {
        // Verify that the existing vault in setUp() has auto-renewal disabled
        // because it was initialized with lockPeriod: 0
        assertFalse(
            vault.autoRenewWithdrawalLock(),
            "Existing vault should have auto-renewal disabled when initialized with lockPeriod: 0"
        );
        assertEq(
            vault.withdrawalLockedUntil(),
            uint64(block.timestamp),
            "Existing vault should have withdrawal lock set to current timestamp"
        );
    }

    function testInitialize_WithZeroLockPeriod_AutoRenewDisabled() public {
        // Create a new vault with zero lock period
        MainVault newImplementation = new MainVault();

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
            feePercentage: FEE_PERCENTAGE,
            currentImplementationOfInvestmentVault: address(investmentVaultImplementation),
            pauserList: address(pauserList),
            meraPriceOracle: address(0),
            lockPeriod: 0 // Zero lock period
        });

        bytes memory initData = abi.encodeWithSelector(MainVault.initialize.selector, initParams);
        ERC1967Proxy newProxy = new ERC1967Proxy(address(newImplementation), initData);
        MainVault newVault = MainVault(address(newProxy));

        // Verify that auto-renewal is disabled when lock period is 0
        assertFalse(newVault.autoRenewWithdrawalLock(), "Auto-renewal should be disabled when lock period is 0");
        assertEq(
            newVault.withdrawalLockedUntil(),
            uint64(block.timestamp),
            "Withdrawal lock should be set to current timestamp"
        );
    }

    function testInitialize_WithPositiveLockPeriod_AutoRenewEnabled() public {
        // Create a new vault with positive lock period
        MainVault newImplementation = new MainVault();

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
            feePercentage: FEE_PERCENTAGE,
            currentImplementationOfInvestmentVault: address(investmentVaultImplementation),
            pauserList: address(pauserList),
            meraPriceOracle: address(0),
            lockPeriod: 365 days // Positive lock period
        });

        bytes memory initData = abi.encodeWithSelector(MainVault.initialize.selector, initParams);
        ERC1967Proxy newProxy = new ERC1967Proxy(address(newImplementation), initData);
        MainVault newVault = MainVault(address(newProxy));

        // Verify that auto-renewal is enabled when lock period > 0
        assertTrue(newVault.autoRenewWithdrawalLock(), "Auto-renewal should be enabled when lock period > 0");
        assertEq(
            newVault.withdrawalLockedUntil(),
            uint64(block.timestamp + 365 days),
            "Withdrawal lock should be set correctly"
        );
    }

    function testInitialize_WithTenMinutesLockPeriod_AutoRenewEnabled() public {
        // Create a new vault with 10 minutes lock period
        MainVault newImplementation = new MainVault();

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
            feePercentage: FEE_PERCENTAGE,
            currentImplementationOfInvestmentVault: address(investmentVaultImplementation),
            pauserList: address(pauserList),
            meraPriceOracle: address(0),
            lockPeriod: 10 minutes // 10 minutes lock period
        });

        bytes memory initData = abi.encodeWithSelector(MainVault.initialize.selector, initParams);
        ERC1967Proxy newProxy = new ERC1967Proxy(address(newImplementation), initData);
        MainVault newVault = MainVault(address(newProxy));

        // Verify that auto-renewal is enabled when lock period > 0
        assertTrue(newVault.autoRenewWithdrawalLock(), "Auto-renewal should be enabled when lock period > 0");
        assertEq(
            newVault.withdrawalLockedUntil(),
            uint64(block.timestamp + 10 minutes),
            "Withdrawal lock should be set correctly"
        );
    }

    function testInitialize_WithThreeYearsLockPeriod_AutoRenewEnabled() public {
        // Create a new vault with 3 years lock period
        MainVault newImplementation = new MainVault();

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
            feePercentage: FEE_PERCENTAGE,
            currentImplementationOfInvestmentVault: address(investmentVaultImplementation),
            pauserList: address(pauserList),
            meraPriceOracle: address(0),
            lockPeriod: 365 days * 3 // 3 years lock period
        });

        bytes memory initData = abi.encodeWithSelector(MainVault.initialize.selector, initParams);
        ERC1967Proxy newProxy = new ERC1967Proxy(address(newImplementation), initData);
        MainVault newVault = MainVault(address(newProxy));

        // Verify that auto-renewal is enabled when lock period > 0
        assertTrue(newVault.autoRenewWithdrawalLock(), "Auto-renewal should be enabled when lock period > 0");
        assertEq(
            newVault.withdrawalLockedUntil(),
            uint64(block.timestamp + 365 days * 3),
            "Withdrawal lock should be set correctly"
        );
    }

    function testInitialize_WithFiveYearsLockPeriod_AutoRenewEnabled() public {
        // Create a new vault with 5 years lock period
        MainVault newImplementation = new MainVault();

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
            feePercentage: FEE_PERCENTAGE,
            currentImplementationOfInvestmentVault: address(investmentVaultImplementation),
            pauserList: address(pauserList),
            meraPriceOracle: address(0),
            lockPeriod: 365 days * 5 // 5 years lock period
        });

        bytes memory initData = abi.encodeWithSelector(MainVault.initialize.selector, initParams);
        ERC1967Proxy newProxy = new ERC1967Proxy(address(newImplementation), initData);
        MainVault newVault = MainVault(address(newProxy));

        // Verify that auto-renewal is enabled when lock period > 0
        assertTrue(newVault.autoRenewWithdrawalLock(), "Auto-renewal should be enabled when lock period > 0");
        assertEq(
            newVault.withdrawalLockedUntil(),
            uint64(block.timestamp + 365 days * 5),
            "Withdrawal lock should be set correctly"
        );
    }
}
