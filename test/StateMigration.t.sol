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

    // Temporary storage variables for state migration tests to avoid stack too deep
    address private _mainVaultBefore;
    address private _tokenMIAddrBefore;
    address private _tokenMVAddrBefore;
    uint256 private _initDepositBefore;
    uint256 private _mvBoughtBefore;
    uint256 private _shareMIBefore;
    uint256 private _depositInMvBefore;
    uint256 private _timestampBefore;
    uint8 private _profitTypeBefore;
    uint256 private _stepBefore;
    uint256 private _profitMVBefore;
    uint256 private _earntProfitInvestorBefore;
    uint256 private _earntProfitFeeBefore;
    uint256 private _earntProfitTotalBefore;
    uint256 private _withdrawnProfitInvestorBefore;
    uint256 private _withdrawnProfitFeeBefore;
    bool private _closedBefore;
    uint256 private _assetsDataLengthBefore;
    uint8 private _swapInitStateBefore;
    uint256 private _asset1ShareBefore;
    uint256 private _asset1StepBefore;
    uint8 private _asset1StrategyBefore;

    // Temporary storage variables for MainVault state migration test
    uint256 private _mvFeePercentageBefore;
    address private _mvFeeWalletBefore;
    address private _mvProfitWalletBefore;
    uint64 private _mvProfitLockedUntilBefore;
    uint64 private _mvWithdrawalLockedUntilBefore;
    bool private _mvAutoRenewBefore;
    address private _mvCurrentInvestmentVaultImplBefore;
    uint8 private _mvProfitTypeBefore;
    uint32 private _mvCurrentFixedProfitPercentBefore;
    uint32 private _mvProposedFixedProfitPercentBefore;
    address private _mvProposedOracleBefore;
    bool private _mvInvestorCanceledOracleBefore;
    bool private _mvAdminCanceledOracleBefore;
    address private _mvPauserListBefore;
    address private _mvOracleBefore;
    bool private _mvTokenMIAvailableByInvestorBefore;
    bool private _mvTokenMIAvailableByAdminBefore;
    bool private _mvRouterAvailableByInvestorBefore;
    bool private _mvRouterAvailableByAdminBefore;
    bool private _mvLockPeriodAvailableBefore;

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
            router: address(0x2222222222222222222222222222222222222222), isAvailable: true
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

        // Capture state before upgrade - using storage variables to avoid stack too deep
        {
            _mvFeePercentageBefore = mainVaultV1.feePercentage();
            _mvFeeWalletBefore = mainVaultV1.feeWallet();
            _mvProfitWalletBefore = mainVaultV1.profitWallet();
            _mvProfitLockedUntilBefore = mainVaultV1.profitLockedUntil();
            _mvWithdrawalLockedUntilBefore = mainVaultV1.withdrawalLockedUntil();
            _mvAutoRenewBefore = mainVaultV1.autoRenewWithdrawalLock();
            _mvCurrentInvestmentVaultImplBefore = mainVaultV1.currentImplementationOfInvestmentVault();
            _mvProfitTypeBefore = uint8(mainVaultV1.profitType());
            _mvCurrentFixedProfitPercentBefore = mainVaultV1.currentFixedProfitPercent();
            _mvProposedFixedProfitPercentBefore = mainVaultV1.proposedFixedProfitPercentByAdmin();
            _mvProposedOracleBefore = mainVaultV1.proposedMeraPriceOracleByAdmin();
            _mvInvestorCanceledOracleBefore = mainVaultV1.investorIsCanceledOracleCheck();
            _mvAdminCanceledOracleBefore = mainVaultV1.adminIsCanceledOracleCheck();
            _mvPauserListBefore = address(mainVaultV1.pauserList());
            _mvOracleBefore = address(mainVaultV1.meraPriceOracle());

            // Check token and router availability
            _mvTokenMIAvailableByInvestorBefore = mainVaultV1.availableTokensByInvestor(address(tokenMI));
            _mvTokenMIAvailableByAdminBefore = mainVaultV1.availableTokensByAdmin(address(tokenMI));
            _mvRouterAvailableByInvestorBefore = mainVaultV1.availableRouterByInvestor(routers[0]);
            _mvRouterAvailableByAdminBefore = mainVaultV1.availableRouterByAdmin(routerConfigs[0].router);
            _mvLockPeriodAvailableBefore = mainVaultV1.availableLock(30 days);
        }

        {
            console.log("State before upgrade captured");
            console.log("Fee percentage:", _mvFeePercentageBefore);
            console.log("Profit type (0=Dynamic, 1=Fixed):", _mvProfitTypeBefore);
        }

        // Verify all values are non-zero
        {
            assertTrue(_mvFeePercentageBefore > 0, "feePercentage is zero");
            assertTrue(_mvFeeWalletBefore != address(0), "feeWallet is zero");
            assertTrue(_mvProfitWalletBefore != address(0), "profitWallet is zero");
            assertTrue(_mvWithdrawalLockedUntilBefore > 0, "withdrawalLockedUntil is zero");
            assertTrue(
                _mvCurrentInvestmentVaultImplBefore != address(0), "currentImplementationOfInvestmentVault is zero"
            );
            assertTrue(_mvCurrentFixedProfitPercentBefore > 0, "currentFixedProfitPercent is zero");
            assertTrue(_mvProposedFixedProfitPercentBefore > 0, "proposedFixedProfitPercent is zero");
            assertTrue(_mvProposedOracleBefore != address(0), "proposedOracle is zero");
            assertTrue(_mvPauserListBefore != address(0), "pauserList is zero");
            assertTrue(_mvOracleBefore != address(0), "oracle is zero");
            assertTrue(_mvTokenMIAvailableByInvestorBefore, "tokenMI not available by investor");
            assertTrue(_mvTokenMIAvailableByAdminBefore, "tokenMI not available by admin");
            assertTrue(_mvRouterAvailableByInvestorBefore, "router not available by investor");
            assertTrue(_mvRouterAvailableByAdminBefore, "router not available by admin");
            assertTrue(_mvLockPeriodAvailableBefore, "lock period not available");
            assertTrue(_mvInvestorCanceledOracleBefore, "investor oracle check not canceled");
            assertTrue(_mvAdminCanceledOracleBefore, "admin oracle check not canceled");
        }

        // Now perform the upgrade
        // Update factory to V2 implementations
        factory.setMainVaultImplementation(address(mainVaultV2Impl));

        // Temporarily upgrade to V2 to set approval (V1 doesn't have approveMainVaultUpgrade method)
        // Get implementation slot (EIP-1967: keccak256("eip1967.proxy.implementation") - 1)
        bytes32 IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        bytes32 currentImpl = vm.load(address(mainVaultProxy), IMPLEMENTATION_SLOT);

        // Temporarily set V2 implementation
        vm.store(address(mainVaultProxy), IMPLEMENTATION_SLOT, bytes32(uint256(uint160(address(mainVaultV2Impl)))));

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

        // Verify state after upgrade - check values immediately after reading to minimize stack usage
        {
            uint256 feePercentageAfter = mainVaultV2.feePercentage();
            assertEq(feePercentageAfter, _mvFeePercentageBefore, "feePercentage not preserved");
        }
        {
            address feeWalletAfter = mainVaultV2.feeWallet();
            address profitWalletAfter = mainVaultV2.profitWallet();
            assertEq(feeWalletAfter, _mvFeeWalletBefore, "feeWallet not preserved");
            assertEq(profitWalletAfter, _mvProfitWalletBefore, "profitWallet not preserved");
        }
        {
            uint64 profitLockedUntilAfter = mainVaultV2.profitLockedUntil();
            uint64 withdrawalLockedUntilAfter = mainVaultV2.withdrawalLockedUntil();
            bool autoRenewAfter = mainVaultV2.autoRenewWithdrawalLock();
            assertEq(profitLockedUntilAfter, _mvProfitLockedUntilBefore, "profitLockedUntil not preserved");
            assertEq(withdrawalLockedUntilAfter, _mvWithdrawalLockedUntilBefore, "withdrawalLockedUntil not preserved");
            assertEq(autoRenewAfter, _mvAutoRenewBefore, "autoRenewWithdrawalLock not preserved");
        }
        {
            address currentInvestmentVaultImplAfter = mainVaultV2.currentImplementationOfInvestmentVault();
            assertEq(
                currentInvestmentVaultImplAfter,
                _mvCurrentInvestmentVaultImplBefore,
                "currentImplementationOfInvestmentVault not preserved"
            );
        }
        {
            uint8 profitTypeAfter = uint8(mainVaultV2.profitType());
            assertEq(profitTypeAfter, _mvProfitTypeBefore, "profitType not preserved");
            console.log("State after upgrade:");
            console.log("Fee percentage:", _mvFeePercentageBefore);
            console.log("Profit type:", profitTypeAfter);
        }
        {
            uint32 currentFixedProfitPercentAfter = mainVaultV2.currentFixedProfitPercent();
            uint32 proposedFixedProfitPercentAfter = mainVaultV2.proposedFixedProfitPercentByAdmin();
            assertEq(
                currentFixedProfitPercentAfter,
                _mvCurrentFixedProfitPercentBefore,
                "currentFixedProfitPercent not preserved"
            );
            assertEq(
                proposedFixedProfitPercentAfter,
                _mvProposedFixedProfitPercentBefore,
                "proposedFixedProfitPercent not preserved"
            );
        }
        {
            address proposedOracleAfter = mainVaultV2.proposedMeraPriceOracleByAdmin();
            assertEq(proposedOracleAfter, _mvProposedOracleBefore, "proposedOracle not preserved");
        }
        {
            bool investorCanceledOracleAfter = mainVaultV2.investorIsCanceledOracleCheck();
            bool adminCanceledOracleAfter = mainVaultV2.adminIsCanceledOracleCheck();
            assertEq(
                investorCanceledOracleAfter, _mvInvestorCanceledOracleBefore, "investorCanceledOracle not preserved"
            );
            assertEq(adminCanceledOracleAfter, _mvAdminCanceledOracleBefore, "adminCanceledOracle not preserved");
        }
        {
            address pauserListAfter = address(mainVaultV2.pauserList());
            address oracleAfter = address(mainVaultV2.meraPriceOracle());
            assertEq(pauserListAfter, _mvPauserListBefore, "pauserList not preserved");
            assertEq(oracleAfter, _mvOracleBefore, "oracle not preserved");
        }

        {
            bool tokenMIAvailableByInvestorAfter = mainVaultV2.availableTokensByInvestor(address(tokenMI));
            bool tokenMIAvailableByAdminAfter = mainVaultV2.availableTokensByAdmin(address(tokenMI));
            bool routerAvailableByInvestorAfter = mainVaultV2.availableRouterByInvestor(routers[0]);
            bool routerAvailableByAdminAfter = mainVaultV2.availableRouterByAdmin(routerConfigs[0].router);
            bool lockPeriodAvailableAfter = mainVaultV2.availableLock(30 days);
            address factoryAfter = address(mainVaultV2.factory());

            assertEq(
                tokenMIAvailableByInvestorAfter,
                _mvTokenMIAvailableByInvestorBefore,
                "tokenMI availability by investor not preserved"
            );
            assertEq(
                tokenMIAvailableByAdminAfter,
                _mvTokenMIAvailableByAdminBefore,
                "tokenMI availability by admin not preserved"
            );
            assertEq(
                routerAvailableByInvestorAfter,
                _mvRouterAvailableByInvestorBefore,
                "router availability by investor not preserved"
            );
            assertEq(
                routerAvailableByAdminAfter,
                _mvRouterAvailableByAdminBefore,
                "router availability by admin not preserved"
            );
            assertEq(lockPeriodAvailableAfter, _mvLockPeriodAvailableBefore, "lock period availability not preserved");
            assertEq(factoryAfter, address(factory), "factory not set");
        }

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

        // Capture state before upgrade - using storage variables to avoid stack too deep
        {
            _mainVaultBefore = address(investmentVaultV1.mainVault());
            (
                IERC20 tokenMIBefore,
                IERC20 tokenMVBefore,
                uint256 initDeposit,
                uint256 mvBought,
                uint256 shareMI,
                uint256 depositInMv,
                uint256 timestamp,
                DataTypesV1.ProfitType profitTypeEnum,
                uint256 step,,
            ) = investmentVaultV1.tokenData();
            _tokenMIAddrBefore = address(tokenMIBefore);
            _tokenMVAddrBefore = address(tokenMVBefore);
            _initDepositBefore = initDeposit;
            _mvBoughtBefore = mvBought;
            _shareMIBefore = shareMI;
            _depositInMvBefore = depositInMv;
            _timestampBefore = timestamp;
            _profitTypeBefore = uint8(profitTypeEnum);
            _stepBefore = step;

            (
                uint256 profitMV,
                uint256 earntProfitInvestor,
                uint256 earntProfitFee,
                uint256 earntProfitTotal,
                uint256 withdrawnProfitInvestor,
                uint256 withdrawnProfitFee
            ) = investmentVaultV1.profitData();
            _profitMVBefore = profitMV;
            _earntProfitInvestorBefore = earntProfitInvestor;
            _earntProfitFeeBefore = earntProfitFee;
            _earntProfitTotalBefore = earntProfitTotal;
            _withdrawnProfitInvestorBefore = withdrawnProfitInvestor;
            _withdrawnProfitFeeBefore = withdrawnProfitFee;

            (bool closed, uint256 assetsDataLength,, DataTypesV1.SwapInitState swapInitStateEnum) =
                investmentVaultV1.vaultState();
            _closedBefore = closed;
            _assetsDataLengthBefore = assetsDataLength;
            _swapInitStateBefore = uint8(swapInitStateEnum);

            // Get asset data
            (uint256 asset1Share, uint256 asset1Step, DataTypesV1.Strategy asset1StrategyEnum,,,,,,) =
                investmentVaultV1.assetsData(IERC20(address(tokenAsset1)));
            _asset1ShareBefore = asset1Share;
            _asset1StepBefore = asset1Step;
            _asset1StrategyBefore = uint8(asset1StrategyEnum);
        }

        // Verify non-zero values
        {
            assertTrue(_tokenMIAddrBefore != address(0), "tokenMI is zero");
            assertTrue(_tokenMVAddrBefore != address(0), "tokenMV is zero");
            assertTrue(_initDepositBefore > 0, "initDeposit is zero");
            assertTrue(_shareMIBefore > 0, "shareMI is zero");
            assertTrue(_timestampBefore > 0, "timestamp is zero");
            assertTrue(_stepBefore > 0, "step is zero");
            assertTrue(_assetsDataLengthBefore > 0, "assetsDataLength is zero");
            assertTrue(_asset1ShareBefore > 0, "asset1 share is zero");
            assertTrue(_asset1StepBefore > 0, "asset1 step is zero");
        }

        // Perform upgrade
        {
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
        }

        // Wrap with V2 interface and capture state after upgrade
        InvestmentVault investmentVaultV2 = InvestmentVault(address(investmentVaultProxy));

        // Assert state preserved - check values immediately after reading to minimize stack usage
        {
            address mainVaultAfter = address(investmentVaultV2.mainVault());
            assertEq(mainVaultAfter, _mainVaultBefore, "mainVault not preserved");
        }

        {
            (
                IERC20 tokenMIAfter,
                IERC20 tokenMVAfter,
                uint256 capitalOfMiAfter,
                uint256 mvBoughtAfter,
                uint256 shareMVAfter,
                uint256 depositInMvAfter,
                uint256 timestampAfter,
                DataTypes.ProfitType profitTypeAfterEnum,
                uint256 stepAfter,,
            ) = investmentVaultV2.tokenData();
            assertEq(address(tokenMIAfter), _tokenMIAddrBefore, "tokenMI not preserved");
            assertEq(address(tokenMVAfter), _tokenMVAddrBefore, "tokenMV not preserved");
            assertEq(capitalOfMiAfter, _initDepositBefore, "capitalOfMi/initDeposit not preserved");
            assertEq(mvBoughtAfter, _mvBoughtBefore, "mvBought not preserved");
            assertEq(shareMVAfter, _shareMIBefore, "shareMV/shareMI not preserved");
            assertEq(depositInMvAfter, _depositInMvBefore, "depositInMv not preserved");
            assertEq(timestampAfter, _timestampBefore, "timestamp not preserved");
            assertEq(uint8(profitTypeAfterEnum), _profitTypeBefore, "profitType not preserved");
            assertEq(stepAfter, _stepBefore, "step not preserved");
        }

        {
            (
                uint256 profitMVAfter,
                uint256 earntProfitInvestorAfter,
                uint256 earntProfitFeeAfter,
                uint256 earntProfitTotalAfter,
                uint256 withdrawnProfitInvestorAfter,
                uint256 withdrawnProfitFeeAfter
            ) = investmentVaultV2.profitData();
            assertEq(profitMVAfter, _profitMVBefore, "profitMV not preserved");
            assertEq(earntProfitInvestorAfter, _earntProfitInvestorBefore, "earntProfitInvestor not preserved");
            assertEq(earntProfitFeeAfter, _earntProfitFeeBefore, "earntProfitFee not preserved");
            assertEq(earntProfitTotalAfter, _earntProfitTotalBefore, "earntProfitTotal not preserved");
            assertEq(
                withdrawnProfitInvestorAfter, _withdrawnProfitInvestorBefore, "withdrawnProfitInvestor not preserved"
            );
            assertEq(withdrawnProfitFeeAfter, _withdrawnProfitFeeBefore, "withdrawnProfitFee not preserved");
        }

        {
            (bool closedAfter, uint256 assetsDataLengthAfter,, DataTypes.SwapInitState swapInitStateAfterEnum) =
                investmentVaultV2.vaultState();
            assertEq(closedAfter, _closedBefore, "closed not preserved");
            assertEq(assetsDataLengthAfter, _assetsDataLengthBefore, "assetsDataLength not preserved");
            assertEq(uint8(swapInitStateAfterEnum), _swapInitStateBefore, "swapInitState not preserved");
        }

        {
            (uint256 asset1ShareAfter, uint256 asset1StepAfter, DataTypes.Strategy asset1StrategyAfterEnum,,,,,,) =
                investmentVaultV2.assetsData(IERC20(address(tokenAsset1)));
            assertEq(asset1ShareAfter, _asset1ShareBefore, "asset1 share not preserved");
            assertEq(asset1StepAfter, _asset1StepBefore, "asset1 step not preserved");
            assertEq(uint8(asset1StrategyAfterEnum), _asset1StrategyBefore, "asset1 strategy not preserved");
        }
    }
}

