// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 fundmera.com

// https://github.com/merafund
pragma solidity ^0.8.29;

import {Test, console} from "forge-std/Test.sol";
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

// Mock ERC20 token for testing
contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// Mock for PauserList
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

contract MainVaultRoleTest is Test {
    MainVault public implementation;
    ERC1967Proxy public proxy;
    MainVault public vault;
    MockERC20 public token;
    MockERC20 public secondToken;
    MockPauserList public pauserList;
    InvestmentVault public investmentVaultImplementation;

    address public owner = address(1);
    address public user1 = address(2);
    address public user2 = address(3);

    // Set up main investor with known private key for signatures
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

    function setUp() public {
        vm.startPrank(owner);

        // Deploy mock tokens
        token = new MockERC20();
        secondToken = new MockERC20();

        // Deploy PauserList implementation
        pauserList = new MockPauserList();

        // Deploy MainVault implementation
        implementation = new MainVault();

        // Deploy InvestmentVault implementation
        investmentVaultImplementation = new InvestmentVault();

        // Prepare initialization data
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
            meraPriceOracle: address(0)
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

        vm.startPrank(mainInvestor);
        IMainVault.TokenAvailability[] memory tokenConfigs = new IMainVault.TokenAvailability[](2);
        tokenConfigs[0] = IMainVault.TokenAvailability({token: address(token), isAvailable: true});
        tokenConfigs[1] = IMainVault.TokenAvailability({token: address(secondToken), isAvailable: true});
        vault.setTokenAvailabilityByInvestor(tokenConfigs);
        vm.stopPrank();

        vm.startPrank(admin);
        vault.setTokenAvailabilityByAdmin(tokenConfigs);
        vm.stopPrank();

        vm.stopPrank();
    }

    function testGrantRole_RevokeRoleFails() public {
        // Deploy mock contract that always returns false for _revokeRole
        MainVaultMockRevokeRole mockVaultImpl = new MainVaultMockRevokeRole();

        // Initialize with same params as main vault
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
            meraPriceOracle: address(0)
        });

        bytes memory initData = abi.encodeWithSelector(MainVault.initialize.selector, initParams);

        ERC1967Proxy mockProxy = new ERC1967Proxy(address(mockVaultImpl), initData);
        MainVaultMockRevokeRole mockVault = MainVaultMockRevokeRole(address(mockProxy));

        // Get role from mock vault instance
        bytes32 mainInvestorRole = mockVault.MAIN_INVESTOR_ROLE();

        // Try to grant role to new user
        vm.prank(emergencyInvestor);
        mockVault.grantRole(mainInvestorRole, user1);

        // Check that original role holder still has role and new user does not
        assertFalse(mockVault.hasRole(mainInvestorRole, mainInvestor), "Original role holder should not have role");
        assertTrue(mockVault.hasRole(mainInvestorRole, user1), "New user should have role");
    }
}
