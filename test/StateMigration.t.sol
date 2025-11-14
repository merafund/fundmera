// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

// V1 contracts
import {MainVaultV1} from "../src/src_first_version/MainVault.sol";
import {InvestmentVaultV1} from "../src/src_first_version/InvestmentVault.sol";
import {AgentDistributionProfitV1} from "../src/src_first_version/AgentDistributionProfit.sol";
import {IMainVault as IMainVaultV1} from "../src/src_first_version/interfaces/IMainVault.sol";

// V2 contracts
import {MainVault} from "../src/MainVault.sol";
import {InvestmentVault} from "../src/InvestmentVault.sol";
import {AgentDistributionProfit} from "../src/AgentDistributionProfit.sol";
import {IMainVault} from "../src/interfaces/IMainVault.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {DataTypes} from "../src/utils/DataTypes.sol";
import {DataTypes as DataTypesV1} from "../src/src_first_version/utils/DataTypes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract MockERC20 is ERC20 {
    uint8 private _decimals;
    
    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _decimals = decimals_;
        _mint(msg.sender, 1000000 * 10 ** decimals_);
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
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

contract MockFactory {
    address public mainVaultImplementation;
    address public investmentVaultImplementation;

    constructor(address _mainVaultImplementation, address _investmentVaultImplementation) {
        mainVaultImplementation = _mainVaultImplementation;
        investmentVaultImplementation = _investmentVaultImplementation;
    }

    function setMainVaultImplementation(address _impl) external {
        mainVaultImplementation = _impl;
    }

    function setInvestmentVaultImplementation(address _impl) external {
        investmentVaultImplementation = _impl;
    }
    
    function createMainVault(
        address mainInvestor,
        address backupInvestor,
        address emergencyInvestor,
        address profitWallet,
        string calldata referralCode
    ) external returns (address) {
        // This is a mock implementation for testing
        // In real Factory, this would create and initialize the proxy
        // For testing, we'll just return the proxy address that was already created
        // The actual proxy creation should be done in the test
        return address(0);
    }
}

contract MockMeraPriceOracle {
    struct AssetPriceData {
        uint256 price;
        uint8 decimals;
    }

    function getAssetsPriceData(address[] memory) external pure returns (AssetPriceData[] memory) {
        AssetPriceData[] memory data = new AssetPriceData[](2);
        data[0] = AssetPriceData({price: 1e8, decimals: 8});
        data[1] = AssetPriceData({price: 1e8, decimals: 8});
        return data;
    }
}


/// @title StateMigrationTest
/// @notice Test contract to verify state preservation during contract upgrades from V1 to V2
contract StateMigrationTest is Test {
    // V1 implementations
    MainVaultV1 public mainVaultV1Impl;
    InvestmentVaultV1 public investmentVaultV1Impl;
    AgentDistributionProfitV1 public agentDistributionV1Impl;

    // V2 implementations
    MainVault public mainVaultV2Impl;
    InvestmentVault public investmentVaultV2Impl;
    AgentDistributionProfit public agentDistributionV2Impl;

    // Proxies
    ERC1967Proxy public mainVaultProxy;
    ERC1967Proxy public investmentVaultProxy;
    ERC1967Proxy public agentDistributionProxy;

    // Wrapped proxies (V1 interface)
    MainVaultV1 public mainVaultV1;
    InvestmentVaultV1 public investmentVaultV1;
    AgentDistributionProfitV1 public agentDistributionV1;

    // Tokens
    MockERC20 public tokenMI;
    MockERC20 public tokenMV;
    MockERC20 public tokenAsset1;
    MockERC20 public tokenAsset2;

    // Mocks
    MockPauserList public pauserList;
    MockFactory public factory;
    MockMeraPriceOracle public oracle;

    // Addresses
    address public mainInvestor = vm.addr(123456);
    address public backupInvestor = address(5);
    address public emergencyInvestor = address(6);
    address public manager = address(7);
    address public admin = address(8);
    address public backupAdmin = address(9);
    address public emergencyAdmin = address(10);
    address public feeWallet = address(11);
    address public profitWallet = address(12);

    address public mainAgent = address(13);
    address public backupAgent = address(14);
    address public emergencyAgent = address(15);
    address public fundWallet = address(16);
    address public meraCapitalWallet = address(17);

    function setUp() public {
        // Deploy tokens
        tokenMI = new MockERC20("Main Investment", "MI", 18);
        tokenMV = new MockERC20("Main Value", "MV", 18);
        tokenAsset1 = new MockERC20("Asset1", "AST1", 18);
        tokenAsset2 = new MockERC20("Asset2", "AST2", 18);

        // Deploy mocks
        pauserList = new MockPauserList();
        oracle = new MockMeraPriceOracle();

        // Deploy V1 implementations
        mainVaultV1Impl = new MainVaultV1();
        investmentVaultV1Impl = new InvestmentVaultV1();
        agentDistributionV1Impl = new AgentDistributionProfitV1();

        // Deploy V2 implementations
        mainVaultV2Impl = new MainVault();
        investmentVaultV2Impl = new InvestmentVault();
        // AgentDistributionProfit V2 is not upgradeable, so we don't need implementation
        // It will be deployed directly when needed

        // Deploy factory
        factory = new MockFactory(address(mainVaultV1Impl), address(investmentVaultV1Impl));
    }

    /// @notice Test MainVault state migration from V1 to V2
    function testMainVaultStateMigration() public {
        console.log("=== Testing MainVault State Migration ===");
        
        // Initialize MainVault V1 with proxy
        IMainVaultV1.InitParams memory initParams = IMainVaultV1.InitParams({
            mainInvestor: mainInvestor,
            backupInvestor: backupInvestor,
            emergencyInvestor: emergencyInvestor,
            manager: manager,
            admin: admin,
            backupAdmin: backupAdmin,
            emergencyAdmin: emergencyAdmin,
            feeWallet: feeWallet,
            profitWallet: profitWallet,
            feePercentage: 200, // 2%
            currentImplementationOfInvestmentVault: address(investmentVaultV1Impl),
            pauserList: address(pauserList),
            lockPeriod: 10 minutes,
            meraPriceOracle: address(oracle)
        });

        // Create proxy with MockFactory as msg.sender so that factory is set correctly
        bytes memory initData = abi.encodeWithSelector(MainVaultV1.initialize.selector, initParams);
        vm.startPrank(address(factory));
        mainVaultProxy = new ERC1967Proxy(address(mainVaultV1Impl), initData);
        vm.stopPrank();
        mainVaultV1 = MainVaultV1(address(mainVaultProxy));

        // Fill state with non-zero values
        vm.startPrank(mainInvestor);
        
        // Set token availability by investor
        IMainVaultV1.TokenAvailability[] memory tokenConfigs = new IMainVaultV1.TokenAvailability[](2);
        tokenConfigs[0] = IMainVaultV1.TokenAvailability({token: address(tokenMI), isAvailable: true});
        tokenConfigs[1] = IMainVaultV1.TokenAvailability({token: address(tokenMV), isAvailable: true});
        mainVaultV1.setTokenAvailabilityByInvestor(tokenConfigs);

        // Set router availability by investor
        address[] memory routers = new address[](1);
        routers[0] = address(0x1111111111111111111111111111111111111111);
        mainVaultV1.setRouterAvailabilityByInvestor(routers);

        // Set profit type
        mainVaultV1.setProfitType(DataTypesV1.ProfitType.Fixed);

        // Set oracle check flags
        mainVaultV1.setInvestorIsCanceledOracleCheck(true);

        vm.stopPrank();

        vm.startPrank(admin);
        
        // Set token availability by admin
        mainVaultV1.setTokenAvailabilityByAdmin(tokenConfigs);

        // Set router availability by admin
        IMainVaultV1.RouterAvailability[] memory routerConfigs = new IMainVaultV1.RouterAvailability[](1);
        routerConfigs[0] = IMainVaultV1.RouterAvailability({
            router: address(0x2222222222222222222222222222222222222222), 
            isAvailable: true
        });
        mainVaultV1.setRouterAvailabilityByAdmin(routerConfigs);

        // Set lock periods
        IMainVaultV1.LockPeriodAvailability[] memory lockConfigs = new IMainVaultV1.LockPeriodAvailability[](1);
        lockConfigs[0] = IMainVaultV1.LockPeriodAvailability({period: 30 days, isAvailable: true});
        mainVaultV1.setLockPeriodsAvailability(lockConfigs);

        // Set proposed fixed profit percent
        mainVaultV1.setProposedFixedProfitPercentByAdmin(2499); // 24.99%

        // Set proposed oracle
        mainVaultV1.setProposedMeraPriceOracleByAdmin(address(0x3333333333333333333333333333333333333333));

        // Set admin oracle check
        mainVaultV1.setAdminIsCanceledOracleCheck(true);

        vm.stopPrank();

        // Capture state before upgrade
        uint256 feePercentageBefore = mainVaultV1.feePercentage();
        address feeWalletBefore = mainVaultV1.feeWallet();
        address profitWalletBefore = mainVaultV1.profitWallet();
        uint64 profitLockedUntilBefore = mainVaultV1.profitLockedUntil();
        uint64 withdrawalLockedUntilBefore = mainVaultV1.withdrawalLockedUntil();
        bool autoRenewBefore = mainVaultV1.autoRenewWithdrawalLock();
        address currentInvestmentVaultImplBefore = mainVaultV1.currentImplementationOfInvestmentVault();
        DataTypesV1.ProfitType profitTypeBefore = mainVaultV1.profitType();
        uint32 currentFixedProfitPercentBefore = mainVaultV1.currentFixedProfitPercent();
        uint32 proposedFixedProfitPercentBefore = mainVaultV1.proposedFixedProfitPercentByAdmin();
        address proposedOracleBefore = mainVaultV1.proposedMeraPriceOracleByAdmin();
        bool investorCanceledOracleBefore = mainVaultV1.investorIsCanceledOracleCheck();
        bool adminCanceledOracleBefore = mainVaultV1.adminIsCanceledOracleCheck();
        address pauserListBefore = address(mainVaultV1.pauserList());
        address oracleBefore = address(mainVaultV1.meraPriceOracle());
        
        // Check token and router availability
        bool tokenMIAvailableByInvestorBefore = mainVaultV1.availableTokensByInvestor(address(tokenMI));
        bool tokenMIAvailableByAdminBefore = mainVaultV1.availableTokensByAdmin(address(tokenMI));
        bool routerAvailableByInvestorBefore = mainVaultV1.availableRouterByInvestor(routers[0]);
        bool routerAvailableByAdminBefore = mainVaultV1.availableRouterByAdmin(routerConfigs[0].router);
        bool lockPeriodAvailableBefore = mainVaultV1.availableLock(30 days);

        console.log("State before upgrade captured");
        console.log("Fee percentage:", feePercentageBefore);
        console.log("Profit type (0=Dynamic, 1=Fixed):", uint8(profitTypeBefore));

        // Verify all values are non-zero
        assertTrue(feePercentageBefore > 0, "feePercentage is zero");
        assertTrue(feeWalletBefore != address(0), "feeWallet is zero");
        assertTrue(profitWalletBefore != address(0), "profitWallet is zero");
        assertTrue(withdrawalLockedUntilBefore > 0, "withdrawalLockedUntil is zero");
        assertTrue(currentInvestmentVaultImplBefore != address(0), "currentImplementationOfInvestmentVault is zero");
        assertTrue(currentFixedProfitPercentBefore > 0, "currentFixedProfitPercent is zero");
        assertTrue(proposedFixedProfitPercentBefore > 0, "proposedFixedProfitPercent is zero");
        assertTrue(proposedOracleBefore != address(0), "proposedOracle is zero");
        assertTrue(pauserListBefore != address(0), "pauserList is zero");
        assertTrue(oracleBefore != address(0), "oracle is zero");
        assertTrue(tokenMIAvailableByInvestorBefore, "tokenMI not available by investor");
        assertTrue(tokenMIAvailableByAdminBefore, "tokenMI not available by admin");
        assertTrue(routerAvailableByInvestorBefore, "router not available by investor");
        assertTrue(routerAvailableByAdminBefore, "router not available by admin");
        assertTrue(lockPeriodAvailableBefore, "lock period not available");
        assertTrue(investorCanceledOracleBefore, "investor oracle check not canceled");
        assertTrue(adminCanceledOracleBefore, "admin oracle check not canceled");

        // Now perform the upgrade
        // Update factory to V2 implementations
        factory.setMainVaultImplementation(address(mainVaultV2Impl));
        
        // Temporarily upgrade to V2 to set approval (V1 doesn't have approveMainVaultUpgrade method)
        // Get implementation slot (EIP-1967: keccak256("eip1967.proxy.implementation") - 1)
        bytes32 IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        bytes32 currentImpl = vm.load(address(mainVaultProxy), IMPLEMENTATION_SLOT);
        
        // Temporarily set V2 implementation
        vm.store(
            address(mainVaultProxy),
            IMPLEMENTATION_SLOT,
            bytes32(uint256(uint160(address(mainVaultV2Impl))))
        );
        
        // Now that we're on V2, we need to set factory in storage
        // Factory is a new field in V2, so it needs to be initialized
        // Since V1 doesn't have factory, it will be address(0) in V2
        // Factory is stored at storage slot 21 (found via forge inspect)
        bytes32 factorySlot = bytes32(uint256(21));
        vm.store(address(mainVaultProxy), factorySlot, bytes32(uint256(uint160(address(factory)))));
        
        // Verify factory is set correctly
        MainVault tempMainVaultV2 = MainVault(address(mainVaultProxy));
        require(address(tempMainVaultV2.factory()) == address(factory), "Factory not set correctly");
        
        // Approve upgrade by main investor using V2 interface
        vm.prank(mainInvestor);
        tempMainVaultV2.approveMainVaultUpgrade(address(mainVaultV2Impl));
        
        // Restore V1 implementation
        vm.store(address(mainVaultProxy), IMPLEMENTATION_SLOT, currentImpl);
        
        // Perform upgrade through proper UUPS mechanism
        vm.prank(admin);
        UUPSUpgradeable(address(mainVaultProxy)).upgradeToAndCall(address(mainVaultV2Impl), "");
        
        // Factory was already set before upgrade, so no need to set it again

        console.log("Upgrade completed");

        // Wrap proxy with V2 interface
        MainVault mainVaultV2 = MainVault(address(mainVaultProxy));

        // Verify state after upgrade
        uint256 feePercentageAfter = mainVaultV2.feePercentage();
        address feeWalletAfter = mainVaultV2.feeWallet();
        address profitWalletAfter = mainVaultV2.profitWallet();
        uint64 profitLockedUntilAfter = mainVaultV2.profitLockedUntil();
        uint64 withdrawalLockedUntilAfter = mainVaultV2.withdrawalLockedUntil();
        bool autoRenewAfter = mainVaultV2.autoRenewWithdrawalLock();
        address currentInvestmentVaultImplAfter = mainVaultV2.currentImplementationOfInvestmentVault();
        DataTypes.ProfitType profitTypeAfter = mainVaultV2.profitType();
        uint32 currentFixedProfitPercentAfter = mainVaultV2.currentFixedProfitPercent();
        uint32 proposedFixedProfitPercentAfter = mainVaultV2.proposedFixedProfitPercentByAdmin();
        address proposedOracleAfter = mainVaultV2.proposedMeraPriceOracleByAdmin();
        bool investorCanceledOracleAfter = mainVaultV2.investorIsCanceledOracleCheck();
        bool adminCanceledOracleAfter = mainVaultV2.adminIsCanceledOracleCheck();
        address pauserListAfter = address(mainVaultV2.pauserList());
        address oracleAfter = address(mainVaultV2.meraPriceOracle());
        address factoryAfter = address(mainVaultV2.factory());
        
        bool tokenMIAvailableByInvestorAfter = mainVaultV2.availableTokensByInvestor(address(tokenMI));
        bool tokenMIAvailableByAdminAfter = mainVaultV2.availableTokensByAdmin(address(tokenMI));
        bool routerAvailableByInvestorAfter = mainVaultV2.availableRouterByInvestor(routers[0]);
        bool routerAvailableByAdminAfter = mainVaultV2.availableRouterByAdmin(routerConfigs[0].router);
        bool lockPeriodAvailableAfter = mainVaultV2.availableLock(30 days);

        console.log("State after upgrade:");
        console.log("Fee percentage:", feePercentageAfter);
        console.log("Profit type:", uint8(profitTypeAfter));

        // Assert all state preserved
        assertEq(feePercentageAfter, feePercentageBefore, "feePercentage not preserved");
        assertEq(feeWalletAfter, feeWalletBefore, "feeWallet not preserved");
        assertEq(profitWalletAfter, profitWalletBefore, "profitWallet not preserved");
        assertEq(profitLockedUntilAfter, profitLockedUntilBefore, "profitLockedUntil not preserved");
        assertEq(withdrawalLockedUntilAfter, withdrawalLockedUntilBefore, "withdrawalLockedUntil not preserved");
        assertEq(autoRenewAfter, autoRenewBefore, "autoRenewWithdrawalLock not preserved");
        assertEq(currentInvestmentVaultImplAfter, currentInvestmentVaultImplBefore, "currentImplementationOfInvestmentVault not preserved");
        assertEq(currentFixedProfitPercentAfter, currentFixedProfitPercentBefore, "currentFixedProfitPercent not preserved");
        assertEq(proposedFixedProfitPercentAfter, proposedFixedProfitPercentBefore, "proposedFixedProfitPercent not preserved");
        assertEq(proposedOracleAfter, proposedOracleBefore, "proposedOracle not preserved");
        assertEq(investorCanceledOracleAfter, investorCanceledOracleBefore, "investorCanceledOracle not preserved");
        assertEq(adminCanceledOracleAfter, adminCanceledOracleBefore, "adminCanceledOracle not preserved");
        assertEq(pauserListAfter, pauserListBefore, "pauserList not preserved");
        assertEq(oracleAfter, oracleBefore, "oracle not preserved");
        assertEq(uint8(profitTypeAfter), uint8(profitTypeBefore), "profitType not preserved");
        
        assertEq(tokenMIAvailableByInvestorAfter, tokenMIAvailableByInvestorBefore, "tokenMI availability by investor not preserved");
        assertEq(tokenMIAvailableByAdminAfter, tokenMIAvailableByAdminBefore, "tokenMI availability by admin not preserved");
        assertEq(routerAvailableByInvestorAfter, routerAvailableByInvestorBefore, "router availability by investor not preserved");
        assertEq(routerAvailableByAdminAfter, routerAvailableByAdminBefore, "router availability by admin not preserved");
        assertEq(lockPeriodAvailableAfter, lockPeriodAvailableBefore, "lock period availability not preserved");
        assertEq(factoryAfter, address(factory), "factory not set");

        console.log("=== MainVault state migration test PASSED ===");
    }

    /// @notice Test InvestmentVault state migration from V1 to V2
    function testInvestmentVaultStateMigration() public {
        console.log("=== Testing InvestmentVault State Migration ===");
        
        // Setup MainVault V1 first (needed for InvestmentVault V1)
        IMainVaultV1.InitParams memory initParams = IMainVaultV1.InitParams({
            mainInvestor: mainInvestor,
            backupInvestor: backupInvestor,
            emergencyInvestor: emergencyInvestor,
            manager: manager,
            admin: admin,
            backupAdmin: backupAdmin,
            emergencyAdmin: emergencyAdmin,
            feeWallet: feeWallet,
            profitWallet: profitWallet,
            feePercentage: 200,
            currentImplementationOfInvestmentVault: address(investmentVaultV1Impl),
            pauserList: address(pauserList),
            meraPriceOracle: address(oracle),
            lockPeriod: 0
        });

        bytes memory initData = abi.encodeWithSelector(MainVaultV1.initialize.selector, initParams);
        mainVaultProxy = new ERC1967Proxy(address(mainVaultV1Impl), initData);
        MainVaultV1 mainVaultV1 = MainVaultV1(address(mainVaultProxy));

        // Initialize InvestmentVault V1
        DataTypesV1.AssetInitData[] memory assets = new DataTypesV1.AssetInitData[](2);
        assets[0] = DataTypesV1.AssetInitData({
            token: IERC20(address(tokenAsset1)),
            shareMV: 3000, // 30%
            step: 1e17, // Valid step value between MIN_STEP (2e16) and MAX_STEP (3e17)
            strategy: DataTypesV1.Strategy.Zero
        });
        assets[1] = DataTypesV1.AssetInitData({
            token: IERC20(address(tokenAsset2)),
            shareMV: 2000, // 20%
            step: 1.5e17, // Valid step value
            strategy: DataTypesV1.Strategy.First
        });

        DataTypesV1.InvestmentVaultInitData memory vaultInitData = DataTypesV1.InvestmentVaultInitData({
            tokenMI: IERC20(address(tokenMI)),
            tokenMV: IERC20(address(tokenMV)),
            initDeposit: 10000 * 10 ** 18,
            shareMI: 8000, // 80%
            step: 2e17, // Valid step value
            mainVault: mainVaultV1,
            assets: assets
        });

        bytes memory invInitData = abi.encodeWithSelector(InvestmentVaultV1.initialize.selector, vaultInitData);
        investmentVaultProxy = new ERC1967Proxy(address(investmentVaultV1Impl), invInitData);
        investmentVaultV1 = InvestmentVaultV1(address(investmentVaultProxy));

        // Capture state before upgrade
        address mainVaultBefore = address(investmentVaultV1.mainVault());
        (
            IERC20 tokenMIBefore,
            IERC20 tokenMVBefore,
            uint256 initDepositBefore,
            uint256 mvBoughtBefore,
            uint256 shareMIBefore,
            uint256 depositInMvBefore,
            uint256 timestampBefore,
            DataTypesV1.ProfitType profitTypeBefore,
            uint256 stepBefore,
            ,
        ) = investmentVaultV1.tokenData();

        (
            uint256 profitMVBefore,
            uint256 earntProfitInvestorBefore,
            uint256 earntProfitFeeBefore,
            uint256 earntProfitTotalBefore,
            uint256 withdrawnProfitInvestorBefore,
            uint256 withdrawnProfitFeeBefore
        ) = investmentVaultV1.profitData();

        (
            bool closedBefore,
            uint256 assetsDataLengthBefore,
            ,
            DataTypesV1.SwapInitState swapInitStateBefore
        ) = investmentVaultV1.vaultState();

        // Get asset data
        (
            uint256 asset1ShareBefore,
            uint256 asset1StepBefore,
            DataTypesV1.Strategy asset1StrategyBefore,
            ,
            ,
            ,
            ,
            ,
        ) = investmentVaultV1.assetsData(IERC20(address(tokenAsset1)));

        console.log("State before upgrade captured");
        console.log("Init deposit:", initDepositBefore);
        console.log("Assets count:", assetsDataLengthBefore);

        // Verify non-zero values
        assertTrue(address(tokenMIBefore) != address(0), "tokenMI is zero");
        assertTrue(address(tokenMVBefore) != address(0), "tokenMV is zero");
        assertTrue(initDepositBefore > 0, "initDeposit is zero");
        assertTrue(shareMIBefore > 0, "shareMI is zero");
        assertTrue(timestampBefore > 0, "timestamp is zero");
        assertTrue(stepBefore > 0, "step is zero");
        assertTrue(assetsDataLengthBefore > 0, "assetsDataLength is zero");
        assertTrue(asset1ShareBefore > 0, "asset1 share is zero");
        assertTrue(asset1StepBefore > 0, "asset1 step is zero");

        // Perform upgrade
        // First, we need to set currentImplementationOfInvestmentVault in mainVault to V2
        // Using direct storage manipulation like we did for MainVault
        
        // Get implementation slot for InvestmentVault proxy
        bytes32 IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        
        // Set the currentImplementationOfInvestmentVault in mainVaultV1 to investmentVaultV2Impl
        // This field is at a specific storage slot in MainVault
        // We need to find the slot for currentImplementationOfInvestmentVault
        // It's slot 6 in MainVault storage layout (after mappings)
        vm.store(
            address(mainVaultProxy),
            bytes32(uint256(6)), // Slot for currentImplementationOfInvestmentVault
            bytes32(uint256(uint160(address(investmentVaultV2Impl))))
        );
        
        // Now directly change the implementation of InvestmentVault proxy
        vm.store(
            address(investmentVaultProxy),
            IMPLEMENTATION_SLOT,
            bytes32(uint256(uint160(address(investmentVaultV2Impl))))
        );

        console.log("Upgrade completed");

        // Wrap with V2 interface
        InvestmentVault investmentVaultV2 = InvestmentVault(address(investmentVaultProxy));

        // Verify state after upgrade
        address mainVaultAfter = address(investmentVaultV2.mainVault());
        (
            IERC20 tokenMIAfter,
            IERC20 tokenMVAfter,
            uint256 capitalOfMiAfter,
            uint256 mvBoughtAfter,
            uint256 shareMVAfter,
            uint256 depositInMvAfter,
            uint256 timestampAfter,
            DataTypes.ProfitType profitTypeAfter,
            uint256 stepAfter,
            ,
        ) = investmentVaultV2.tokenData();

        (
            uint256 profitMVAfter,
            uint256 earntProfitInvestorAfter,
            uint256 earntProfitFeeAfter,
            uint256 earntProfitTotalAfter,
            uint256 withdrawnProfitInvestorAfter,
            uint256 withdrawnProfitFeeAfter
        ) = investmentVaultV2.profitData();

        (
            bool closedAfter,
            uint256 assetsDataLengthAfter,
            ,
            DataTypes.SwapInitState swapInitStateAfter
        ) = investmentVaultV2.vaultState();

        (
            uint256 asset1ShareAfter,
            uint256 asset1StepAfter,
            DataTypes.Strategy asset1StrategyAfter,
            ,
            ,
            ,
            ,
            ,
        ) = investmentVaultV2.assetsData(IERC20(address(tokenAsset1)));

        console.log("State after upgrade:");
        console.log("Capital of MI:", capitalOfMiAfter);
        console.log("Assets count:", assetsDataLengthAfter);

        // Assert state preserved
        assertEq(mainVaultAfter, mainVaultBefore, "mainVault not preserved");
        assertEq(address(tokenMIAfter), address(tokenMIBefore), "tokenMI not preserved");
        assertEq(address(tokenMVAfter), address(tokenMVBefore), "tokenMV not preserved");
        assertEq(capitalOfMiAfter, initDepositBefore, "capitalOfMi/initDeposit not preserved");
        assertEq(mvBoughtAfter, mvBoughtBefore, "mvBought not preserved");
        assertEq(shareMVAfter, shareMIBefore, "shareMV/shareMI not preserved");
        assertEq(depositInMvAfter, depositInMvBefore, "depositInMv not preserved");
        assertEq(timestampAfter, timestampBefore, "timestamp not preserved");
        assertEq(uint8(profitTypeAfter), uint8(profitTypeBefore), "profitType not preserved");
        assertEq(stepAfter, stepBefore, "step not preserved");
        
        assertEq(profitMVAfter, profitMVBefore, "profitMV not preserved");
        assertEq(earntProfitInvestorAfter, earntProfitInvestorBefore, "earntProfitInvestor not preserved");
        assertEq(earntProfitFeeAfter, earntProfitFeeBefore, "earntProfitFee not preserved");
        assertEq(earntProfitTotalAfter, earntProfitTotalBefore, "earntProfitTotal not preserved");
        assertEq(withdrawnProfitInvestorAfter, withdrawnProfitInvestorBefore, "withdrawnProfitInvestor not preserved");
        assertEq(withdrawnProfitFeeAfter, withdrawnProfitFeeBefore, "withdrawnProfitFee not preserved");
        
        assertEq(closedAfter, closedBefore, "closed not preserved");
        assertEq(assetsDataLengthAfter, assetsDataLengthBefore, "assetsDataLength not preserved");
        assertEq(uint8(swapInitStateAfter), uint8(swapInitStateBefore), "swapInitState not preserved");
        
        assertEq(asset1ShareAfter, asset1ShareBefore, "asset1 share not preserved");
        assertEq(asset1StepAfter, asset1StepBefore, "asset1 step not preserved");
        assertEq(uint8(asset1StrategyAfter), uint8(asset1StrategyBefore), "asset1 strategy not preserved");

        console.log("=== InvestmentVault state migration test PASSED ===");
    }

}

