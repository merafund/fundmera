// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 fundmera.com

// https://github.com/merafund
pragma solidity ^0.8.29;

import {Test, console} from "forge-std/Test.sol";
import {Factory, IFactory} from "../src/Factory.sol";
import {MainVault} from "../src/MainVault.sol";
import {InvestmentVault} from "../src/InvestmentVault.sol";
import {AgentDistributionProfit} from "../src/AgentDistributionProfit.sol";
import {PauserList} from "../src/PauserList.sol";
import {IMainVault} from "../src/interfaces/IMainVault.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract FactoryTest is Test {
    Factory public factory;
    address public owner;
    address public manager;
    address public admin;
    address public backupAdmin;
    address public emergencyAdmin;
    address public fundWallet;
    address public defaultAgentWallet;
    address public meraCapitalWallet;
    address public mainVaultImpl;
    address public investmentVaultImpl;
    address public agentDistributionImpl;
    address public pauserList;
    uint256 public constant FEE_PERCENTAGE = 1000; // 10%

    // Test addresses
    address public constant ALICE = address(0x1);
    address public constant BOB = address(0x2);
    address public constant CHARLIE = address(0x3);

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
    event DeployerUpdated(address indexed oldDeployer, address indexed newDeployer);
    event FounderWalletUpdated(address indexed oldFundWallet, address indexed newFundWallet);
    event MeraCapitalWalletUpdated(address indexed oldMeraCapitalWallet, address indexed newMeraCapitalWallet);
    event MeraPriceOracleUpdated(address indexed oldMeraPriceOracle, address indexed newMeraPriceOracle);

    function setUp() public {
        owner = address(this);
        manager = makeAddr("manager");
        admin = makeAddr("admin");
        backupAdmin = makeAddr("backupAdmin");
        emergencyAdmin = makeAddr("emergencyAdmin");
        fundWallet = makeAddr("fundWallet");
        defaultAgentWallet = makeAddr("defaultAgentWallet");
        meraCapitalWallet = makeAddr("meraCapitalWallet");

        // Deploy PauserList first as it's needed for MainVault initialization
        PauserList pauserListContract = new PauserList(admin);
        pauserList = address(pauserListContract);

        // Deploy implementation contracts
        // Note: These are implementation contracts that will be used by proxies
        // They should not be initialized directly
        MainVault mainVaultImplementation = new MainVault();
        mainVaultImpl = address(mainVaultImplementation);

        InvestmentVault investmentVaultImplementation = new InvestmentVault();
        investmentVaultImpl = address(investmentVaultImplementation);

        AgentDistributionProfit agentDistributionImplementation = new AgentDistributionProfit();
        agentDistributionImpl = address(agentDistributionImplementation);

        // Prepare constructor parameters
        address meraPriceOracle = makeAddr("meraPriceOracle");
        IFactory.ConstructorParams memory params = IFactory.ConstructorParams({
            meraPriceOracle: meraPriceOracle,
            mainVaultImplementation: mainVaultImpl,
            investmentVaultImplementation: investmentVaultImpl,
            manager: manager,
            admin: admin,
            backupAdmin: backupAdmin,
            emergencyAdmin: emergencyAdmin,
            feePercentage: FEE_PERCENTAGE,
            pauserList: pauserList,
            agentDistributionImplementation: agentDistributionImpl,
            fundWallet: fundWallet,
            defaultAgentWallet: defaultAgentWallet,
            meraCapitalWallet: meraCapitalWallet
        });

        // Deploy Factory
        factory = new Factory(params);
    }

    function test_Constructor() public {
        assertEq(factory.mainVaultImplementation(), mainVaultImpl);
        assertEq(factory.investmentVaultImplementation(), investmentVaultImpl);
        assertEq(factory.manager(), manager);
        assertEq(factory.admin(), admin);
        assertEq(factory.backupAdmin(), backupAdmin);
        assertEq(factory.emergencyAdmin(), emergencyAdmin);
        assertEq(factory.feePercentage(), FEE_PERCENTAGE);
        assertEq(factory.pauserList(), pauserList);
        assertEq(factory.agentDistributionImplementation(), agentDistributionImpl);
        assertEq(factory.fundWallet(), fundWallet);
        assertEq(factory.defaultAgentWallet(), defaultAgentWallet);
        assertEq(factory.meraCapitalWallet(), meraCapitalWallet);
        assertEq(factory.deployer(), address(this));

        // Check default agent distribution was created
        address defaultAgentDist = factory.defaultAgentDistribution();
        assertTrue(defaultAgentDist != address(0));
        assertEq(factory.referralToAgentDistribution("DEFAULT"), defaultAgentDist);
        assertEq(factory.agentDistributionToReferral(defaultAgentDist), "DEFAULT");
    }

    function test_CreateMainVault() public {
        string memory referralCode = "TEST_CODE";
        address profitWallet = makeAddr("profitWallet");

        // First create agent distribution for the referral code
        vm.startPrank(factory.deployer());
        address agentWallet = makeAddr("agentWallet");
        address reserveAgentWallet = makeAddr("reserveAgentWallet");
        address emergencyAgentWallet = makeAddr("emergencyAgentWallet");
        address agentDistProxy =
            factory.createAgentDistribution(referralCode, agentWallet, reserveAgentWallet, emergencyAgentWallet);
        vm.stopPrank();

        // Create MainVault
        address mainVaultProxy = factory.createMainVault(ALICE, BOB, CHARLIE, profitWallet, referralCode);
        assertTrue(mainVaultProxy != address(0));

        // Verify MainVault initialization
        MainVault vault = MainVault(mainVaultProxy);
        assertTrue(vault.hasRole(vault.MAIN_INVESTOR_ROLE(), ALICE));
        assertTrue(vault.hasRole(vault.BACKUP_INVESTOR_ROLE(), BOB));
        assertTrue(vault.hasRole(vault.EMERGENCY_INVESTOR_ROLE(), CHARLIE));
        assertEq(vault.profitWallet(), profitWallet);
        assertEq(vault.feeWallet(), agentDistProxy);
    }

    function test_CreateMainVaultWithDefaultReferral() public {
        address profitWallet = makeAddr("profitWallet");
        string memory nonExistentCode = "NON_EXISTENT";

        address mainVaultProxy = factory.createMainVault(ALICE, BOB, CHARLIE, profitWallet, nonExistentCode);
        assertTrue(mainVaultProxy != address(0));

        // Verify MainVault uses default agent distribution
        MainVault vault = MainVault(mainVaultProxy);
        assertEq(vault.feeWallet(), factory.defaultAgentDistribution());
    }

    function test_CreateAgentDistribution() public {
        string memory referralCode = "TEST_CODE";
        address agentWallet = makeAddr("agentWallet");
        address reserveAgentWallet = makeAddr("reserveAgentWallet");
        address emergencyAgentWallet = makeAddr("emergencyAgentWallet");

        vm.startPrank(factory.deployer());

        address proxyAddress =
            factory.createAgentDistribution(referralCode, agentWallet, reserveAgentWallet, emergencyAgentWallet);

        vm.stopPrank();

        assertTrue(proxyAddress != address(0));
        assertEq(factory.referralToAgentDistribution(referralCode), proxyAddress);
        assertEq(factory.agentDistributionToReferral(proxyAddress), referralCode);
    }

    function test_RevertCreateAgentDistributionIfNotDeployer() public {
        string memory referralCode = "TEST_CODE";
        address agentWallet = makeAddr("agentWallet");
        address reserveAgentWallet = makeAddr("reserveAgentWallet");
        address emergencyAgentWallet = makeAddr("emergencyAgentWallet");

        vm.startPrank(ALICE);
        vm.expectRevert(IFactory.CallerIsNotDeployer.selector);
        factory.createAgentDistribution(referralCode, agentWallet, reserveAgentWallet, emergencyAgentWallet);
        vm.stopPrank();
    }

    function test_RevertCreateAgentDistributionIfCodeExists() public {
        string memory referralCode = "TEST_CODE";
        address agentWallet = makeAddr("agentWallet");
        address reserveAgentWallet = makeAddr("reserveAgentWallet");
        address emergencyAgentWallet = makeAddr("emergencyAgentWallet");

        vm.startPrank(factory.deployer());
        factory.createAgentDistribution(referralCode, agentWallet, reserveAgentWallet, emergencyAgentWallet);

        vm.expectRevert(IFactory.ReferralCodeAlreadyUsed.selector);
        factory.createAgentDistribution(referralCode, agentWallet, reserveAgentWallet, emergencyAgentWallet);
        vm.stopPrank();
    }

    function test_SetDeployer() public {
        vm.startPrank(owner);

        vm.expectEmit(true, true, true, true);
        emit DeployerUpdated(factory.deployer(), ALICE);

        factory.setDeployer(ALICE);
        assertEq(factory.deployer(), ALICE);

        vm.stopPrank();
    }

    function test_RevertSetDeployerIfNotOwner() public {
        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", ALICE));
        factory.setDeployer(BOB);
        vm.stopPrank();
    }

    function test_RevertSetDeployerToZeroAddress() public {
        vm.startPrank(owner);
        vm.expectRevert(IFactory.ZeroAddress.selector);
        factory.setDeployer(address(0));
        vm.stopPrank();
    }

    function test_UpdateImplementations() public {
        address newMainVaultImpl = address(new MainVault());
        address newInvestmentVaultImpl = address(new InvestmentVault());
        address newAgentDistributionImpl = address(new AgentDistributionProfit());

        vm.startPrank(owner);
        factory.updateImplementations(newMainVaultImpl, newInvestmentVaultImpl, newAgentDistributionImpl);
        vm.stopPrank();

        assertEq(factory.mainVaultImplementation(), newMainVaultImpl);
        assertEq(factory.investmentVaultImplementation(), newInvestmentVaultImpl);
        assertEq(factory.agentDistributionImplementation(), newAgentDistributionImpl);
    }

    function test_UpdateImplementationsPartially() public {
        address newMainVaultImpl = address(new MainVault());
        address oldInvestmentVaultImpl = factory.investmentVaultImplementation();
        address oldAgentDistributionImpl = factory.agentDistributionImplementation();

        vm.startPrank(owner);
        factory.updateImplementations(newMainVaultImpl, address(0), address(0));
        vm.stopPrank();

        assertEq(factory.mainVaultImplementation(), newMainVaultImpl);
        assertEq(factory.investmentVaultImplementation(), oldInvestmentVaultImpl);
        assertEq(factory.agentDistributionImplementation(), oldAgentDistributionImpl);
    }

    function test_RevertUpdateImplementationsIfNotOwner() public {
        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", ALICE));
        factory.updateImplementations(address(0), address(0), address(0));
        vm.stopPrank();
    }

    function test_GetAgentDistribution() public {
        string memory referralCode = "TEST_CODE";
        address agentWallet = makeAddr("agentWallet");
        address reserveAgentWallet = makeAddr("reserveAgentWallet");
        address emergencyAgentWallet = makeAddr("emergencyAgentWallet");

        // Create new agent distribution
        vm.startPrank(factory.deployer());
        address proxyAddress =
            factory.createAgentDistribution(referralCode, agentWallet, reserveAgentWallet, emergencyAgentWallet);
        vm.stopPrank();

        // Test existing referral code
        assertEq(factory.getAgentDistribution(referralCode), proxyAddress);

        // Test non-existent referral code
        assertEq(factory.getAgentDistribution("NON_EXISTENT"), factory.defaultAgentDistribution());
    }

    function test_GetReferralCode() public {
        string memory referralCode = "TEST_CODE";
        address agentWallet = makeAddr("agentWallet");
        address reserveAgentWallet = makeAddr("reserveAgentWallet");
        address emergencyAgentWallet = makeAddr("emergencyAgentWallet");

        // Create new agent distribution
        vm.startPrank(factory.deployer());
        address proxyAddress =
            factory.createAgentDistribution(referralCode, agentWallet, reserveAgentWallet, emergencyAgentWallet);
        vm.stopPrank();

        // Test existing agent distribution
        assertEq(factory.getReferralCode(proxyAddress), referralCode);

        // Test default agent distribution
        assertEq(factory.getReferralCode(factory.defaultAgentDistribution()), "DEFAULT");

        // Test non-existent agent distribution
        assertEq(factory.getReferralCode(address(0x123)), "");
    }

    function test_UpdateMainVaultParameters() public {
        address newManager = makeAddr("newManager");
        address newAdmin = makeAddr("newAdmin");
        address newBackupAdmin = makeAddr("newBackupAdmin");
        address newEmergencyAdmin = makeAddr("newEmergencyAdmin");
        uint256 newFeePercentage = 2000; // 20%
        address newPauserList = address(new PauserList(newAdmin));

        vm.startPrank(owner);
        factory.updateMainVaultParameters(
            newManager, newAdmin, newBackupAdmin, newEmergencyAdmin, newFeePercentage, newPauserList
        );
        vm.stopPrank();

        assertEq(factory.manager(), newManager);
        assertEq(factory.admin(), newAdmin);
        assertEq(factory.backupAdmin(), newBackupAdmin);
        assertEq(factory.emergencyAdmin(), newEmergencyAdmin);
        assertEq(factory.feePercentage(), newFeePercentage);
        assertEq(factory.pauserList(), newPauserList);
    }

    function test_RevertUpdateMainVaultParametersIfNotOwner() public {
        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", ALICE));
        factory.updateMainVaultParameters(address(0x1), address(0x2), address(0x3), address(0x4), 1000, address(0x5));
        vm.stopPrank();
    }

    function test_RevertUpdateMainVaultParametersWithZeroAddresses() public {
        address newManager = makeAddr("newManager");
        address newAdmin = makeAddr("newAdmin");
        address newBackupAdmin = makeAddr("newBackupAdmin");
        address newEmergencyAdmin = makeAddr("newEmergencyAdmin");
        uint256 newFeePercentage = 2000;
        address newPauserList = address(new PauserList(newAdmin));

        vm.startPrank(owner);

        vm.expectRevert("Zero address not allowed");
        factory.updateMainVaultParameters(
            address(0), newAdmin, newBackupAdmin, newEmergencyAdmin, newFeePercentage, newPauserList
        );

        vm.expectRevert("Zero address not allowed");
        factory.updateMainVaultParameters(
            newManager, address(0), newBackupAdmin, newEmergencyAdmin, newFeePercentage, newPauserList
        );

        vm.expectRevert("Zero address not allowed");
        factory.updateMainVaultParameters(
            newManager, newAdmin, address(0), newEmergencyAdmin, newFeePercentage, newPauserList
        );

        vm.expectRevert("Zero address not allowed");
        factory.updateMainVaultParameters(
            newManager, newAdmin, newBackupAdmin, address(0), newFeePercentage, newPauserList
        );

        vm.expectRevert("Zero address not allowed");
        factory.updateMainVaultParameters(
            newManager, newAdmin, newBackupAdmin, newEmergencyAdmin, newFeePercentage, address(0)
        );

        vm.stopPrank();
    }

    function test_UpdateFundWallets() public {
        address newFundWallet = makeAddr("newFundWallet");
        address newMeraCapitalWallet = makeAddr("newMeraCapitalWallet");
        address oldFundWallet = factory.fundWallet();
        address oldMeraCapitalWallet = factory.meraCapitalWallet();

        vm.startPrank(owner);

        vm.expectEmit(true, true, true, true);
        emit FounderWalletUpdated(oldFundWallet, newFundWallet);
        emit MeraCapitalWalletUpdated(oldMeraCapitalWallet, newMeraCapitalWallet);

        factory.updateFundWallets(newFundWallet, newMeraCapitalWallet);
        vm.stopPrank();

        assertEq(factory.fundWallet(), newFundWallet);
        assertEq(factory.meraCapitalWallet(), newMeraCapitalWallet);
    }

    function test_RevertUpdateFundWalletsIfNotOwner() public {
        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", ALICE));
        factory.updateFundWallets(address(0x1), address(0x2));
        vm.stopPrank();
    }

    function test_RevertUpdateFundWalletsWithZeroAddresses() public {
        address newFundWallet = makeAddr("newFundWallet");
        address newMeraCapitalWallet = makeAddr("newMeraCapitalWallet");

        vm.startPrank(owner);

        vm.expectRevert("Zero address not allowed");
        factory.updateFundWallets(address(0), newMeraCapitalWallet);

        vm.expectRevert("Zero address not allowed");
        factory.updateFundWallets(newFundWallet, address(0));

        vm.stopPrank();
    }

    function test_RevertConstructorWithZeroAddresses() public {
        address meraPriceOracle = makeAddr("meraPriceOracle");
        IFactory.ConstructorParams memory params = IFactory.ConstructorParams({
            meraPriceOracle: meraPriceOracle,
            mainVaultImplementation: mainVaultImpl,
            investmentVaultImplementation: investmentVaultImpl,
            manager: manager,
            admin: admin,
            backupAdmin: backupAdmin,
            emergencyAdmin: emergencyAdmin,
            feePercentage: FEE_PERCENTAGE,
            pauserList: pauserList,
            agentDistributionImplementation: agentDistributionImpl,
            fundWallet: fundWallet,
            defaultAgentWallet: defaultAgentWallet,
            meraCapitalWallet: meraCapitalWallet
        });

        params.mainVaultImplementation = address(0);
        vm.expectRevert(IFactory.ZeroAddress.selector);
        new Factory(params);
        params.mainVaultImplementation = mainVaultImpl;

        params.investmentVaultImplementation = address(0);
        vm.expectRevert(IFactory.ZeroAddress.selector);
        new Factory(params);
        params.investmentVaultImplementation = investmentVaultImpl;

        // Test manager
        params.manager = address(0);
        vm.expectRevert(IFactory.ZeroAddress.selector);
        new Factory(params);
        params.manager = manager;

        // Test admin
        params.admin = address(0);
        vm.expectRevert(IFactory.ZeroAddress.selector);
        new Factory(params);
        params.admin = admin;

        // Test backupAdmin
        params.backupAdmin = address(0);
        vm.expectRevert(IFactory.ZeroAddress.selector);
        new Factory(params);
        params.backupAdmin = backupAdmin;

        // Test emergencyAdmin
        params.emergencyAdmin = address(0);
        vm.expectRevert(IFactory.ZeroAddress.selector);
        new Factory(params);
        params.emergencyAdmin = emergencyAdmin;

        // Test pauserList
        params.pauserList = address(0);
        vm.expectRevert(IFactory.ZeroAddress.selector);
        new Factory(params);
        params.pauserList = pauserList;

        // Test agentDistributionImplementation
        params.agentDistributionImplementation = address(0);
        vm.expectRevert(IFactory.ZeroAddress.selector);
        new Factory(params);
        params.agentDistributionImplementation = agentDistributionImpl;

        // Test fundWallet
        params.fundWallet = address(0);
        vm.expectRevert(IFactory.ZeroAddress.selector);
        new Factory(params);
        params.fundWallet = fundWallet;

        // Test defaultAgentWallet
        params.defaultAgentWallet = address(0);
        vm.expectRevert(IFactory.ZeroAddress.selector);
        new Factory(params);
        params.defaultAgentWallet = defaultAgentWallet;

        // Test meraCapitalWallet
        params.meraCapitalWallet = address(0);
        vm.expectRevert(IFactory.ZeroAddress.selector);
        new Factory(params);
        params.meraCapitalWallet = meraCapitalWallet;

        // Test meraPriceOracle
        params.meraPriceOracle = address(0);
        vm.expectRevert(IFactory.ZeroAddress.selector);
        new Factory(params);
        params.meraPriceOracle = meraPriceOracle;
    }

    function test_RevertCreateAgentDistributionWithZeroAddresses() public {
        string memory referralCode = "TEST_CODE";
        address agentWallet = makeAddr("agentWallet");
        address reserveAgentWallet = makeAddr("reserveAgentWallet");
        address emergencyAgentWallet = makeAddr("emergencyAgentWallet");

        vm.startPrank(factory.deployer());

        // Test agentWallet
        vm.expectRevert(IFactory.ZeroAddress.selector);
        factory.createAgentDistribution(referralCode, address(0), reserveAgentWallet, emergencyAgentWallet);

        // Test reserveAgentWallet
        vm.expectRevert(IFactory.ZeroAddress.selector);
        factory.createAgentDistribution(referralCode, agentWallet, address(0), emergencyAgentWallet);

        // Test emergencyAgentWallet
        vm.expectRevert(IFactory.ZeroAddress.selector);
        factory.createAgentDistribution(referralCode, agentWallet, reserveAgentWallet, address(0));

        vm.stopPrank();
    }

    function test_RevertCreateAgentDistributionWithEmptyReferralCode() public {
        address agentWallet = makeAddr("agentWallet");
        address reserveAgentWallet = makeAddr("reserveAgentWallet");
        address emergencyAgentWallet = makeAddr("emergencyAgentWallet");

        vm.startPrank(factory.deployer());

        // Test empty string
        vm.expectRevert(IFactory.InvalidReferralCode.selector);
        factory.createAgentDistribution("", agentWallet, reserveAgentWallet, emergencyAgentWallet);

        vm.stopPrank();
    }

    function test_RevertCreateMainVaultWithZeroAddresses() public {
        string memory referralCode = "TEST_CODE";
        address profitWallet = makeAddr("profitWallet");
        address mainInvestor = makeAddr("mainInvestor");
        address backupInvestor = makeAddr("backupInvestor");
        address emergencyInvestor = makeAddr("emergencyInvestor");

        // Test mainInvestor
        vm.expectRevert(IFactory.ZeroAddress.selector);
        factory.createMainVault(address(0), backupInvestor, emergencyInvestor, profitWallet, referralCode);

        // Test backupInvestor
        vm.expectRevert(IFactory.ZeroAddress.selector);
        factory.createMainVault(mainInvestor, address(0), emergencyInvestor, profitWallet, referralCode);

        // Test emergencyInvestor
        vm.expectRevert(IFactory.ZeroAddress.selector);
        factory.createMainVault(mainInvestor, backupInvestor, address(0), profitWallet, referralCode);

        // Test profitWallet
        vm.expectRevert(IFactory.ZeroAddress.selector);
        factory.createMainVault(mainInvestor, backupInvestor, emergencyInvestor, address(0), referralCode);
    }

    function test_SetMeraPriceOracle() public {
        address newMeraPriceOracle = makeAddr("newMeraPriceOracle");
        address oldMeraPriceOracle = factory.meraPriceOracle();

        vm.startPrank(owner);

        vm.expectEmit(true, true, true, true);
        emit MeraPriceOracleUpdated(oldMeraPriceOracle, newMeraPriceOracle);

        factory.setMeraPriceOracle(newMeraPriceOracle);
        assertEq(factory.meraPriceOracle(), newMeraPriceOracle);

        vm.stopPrank();
    }

    function test_RevertSetMeraPriceOracleIfNotOwner() public {
        address newMeraPriceOracle = makeAddr("newMeraPriceOracle");

        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", ALICE));
        factory.setMeraPriceOracle(newMeraPriceOracle);
        vm.stopPrank();
    }

    function test_RevertSetMeraPriceOracleToZeroAddress() public {
        vm.startPrank(owner);
        vm.expectRevert(IFactory.ZeroAddress.selector);
        factory.setMeraPriceOracle(address(0));
        vm.stopPrank();
    }
}
