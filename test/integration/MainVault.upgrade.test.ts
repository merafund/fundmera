import { expect } from "chai";
import { ethers } from "hardhat";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { MainVault, IERC20 } from "../typechain-types";

describe("MainVault Upgrade Tests", function () {
  let mainVault: MainVault;
  let owner: HardhatEthersSigner;
  let mainInvestor: HardhatEthersSigner;
  let backupInvestor: HardhatEthersSigner;
  let emergencyInvestor: HardhatEthersSigner;
  let manager: HardhatEthersSigner;
  let admin: HardhatEthersSigner;
  let backupAdmin: HardhatEthersSigner;
  let emergencyAdmin: HardhatEthersSigner;
  let feeWallet: HardhatEthersSigner;
  let profitWallet: HardhatEthersSigner;
  let pauserList: HardhatEthersSigner;

  beforeEach(async function () {
    // Get signers
    [
      owner,
      mainInvestor,
      backupInvestor,
      emergencyInvestor,
      manager,
      admin,
      backupAdmin,
      emergencyAdmin,
      feeWallet,
      profitWallet,
      pauserList,
    ] = await ethers.getSigners();

    // Deploy MainVaultSwapLibrary first
    const MainVaultSwapLibrary = await ethers.getContractFactory("MainVaultSwapLibrary");
    const mainVaultSwapLibrary = await MainVaultSwapLibrary.deploy();

    // Deploy MainVault implementation
    const MainVault = await ethers.getContractFactory("MainVault", {
      libraries: {
        MainVaultSwapLibrary: await mainVaultSwapLibrary.getAddress(),
      },
    });
    const mainVaultImpl = await MainVault.deploy();

    // Deploy MeraPriceOracle
    const MeraPriceOracle = await ethers.getContractFactory("MockMeraPriceOracle");
    const meraPriceOracle = await MeraPriceOracle.deploy();
    await meraPriceOracle.waitForDeployment();

    // Prepare initialization data
    const initData = MainVault.interface.encodeFunctionData("initialize", [{
      mainInvestor: await mainInvestor.getAddress(),
      backupInvestor: await backupInvestor.getAddress(),
      emergencyInvestor: await emergencyInvestor.getAddress(),
      manager: await manager.getAddress(),
      admin: await admin.getAddress(),
      backupAdmin: await backupAdmin.getAddress(),
      emergencyAdmin: await emergencyAdmin.getAddress(),
      feeWallet: await feeWallet.getAddress(),
      profitWallet: await profitWallet.getAddress(),
      feePercentage: 100, // 1%
      currentImplementationOfInvestmentVault: ethers.ZeroAddress,
      pauserList: await pauserList.getAddress(),
      meraPriceOracle: await meraPriceOracle.getAddress(),
      lockPeriod: 0 // No lock period for test
    }]);

    // Deploy proxy
    const ERC1967Proxy = await ethers.getContractFactory("ERC1967Proxy");
    const proxy = await ERC1967Proxy.deploy(
      await mainVaultImpl.getAddress(),
      initData
    );
    mainVault = MainVault.attach(await proxy.getAddress()) as unknown as MainVault;
  });

  it("Should set up roles correctly after deployment", async function () {
    expect(await mainVault.hasRole(await mainVault.MAIN_INVESTOR_ROLE(), await mainInvestor.getAddress())).to.be.true;
    expect(await mainVault.hasRole(await mainVault.BACKUP_INVESTOR_ROLE(), await backupInvestor.getAddress())).to.be.true;
    expect(await mainVault.hasRole(await mainVault.EMERGENCY_INVESTOR_ROLE(), await emergencyInvestor.getAddress())).to.be.true;
    expect(await mainVault.hasRole(await mainVault.MANAGER_ROLE(), await manager.getAddress())).to.be.true;
    expect(await mainVault.hasRole(await mainVault.ADMIN_ROLE(), await admin.getAddress())).to.be.true;
    expect(await mainVault.hasRole(await mainVault.BACKUP_ADMIN_ROLE(), await backupAdmin.getAddress())).to.be.true;
    expect(await mainVault.hasRole(await mainVault.EMERGENCY_ADMIN_ROLE(), await emergencyAdmin.getAddress())).to.be.true;
  });

  it("Should upgrade contract successfully", async function () {
    // Deploy MainVaultSwapLibrary first for the new implementation
    const MainVaultSwapLibrary = await ethers.getContractFactory("MainVaultSwapLibrary");
    const mainVaultSwapLibrary = await MainVaultSwapLibrary.deploy();

    // Deploy new implementation
    const MainVaultV2 = await ethers.getContractFactory("MainVault", {
      libraries: {
        MainVaultSwapLibrary: await mainVaultSwapLibrary.getAddress(),
      },
    });
    
    // Get current implementation address for later comparison
    const currentImplAddress = await ethers.provider.getStorage(await mainVault.getAddress(), "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc");
    
    // Deploy the new implementation contract
    const newImplementation = await MainVaultV2.deploy();
    const newImplementationAddress = await newImplementation.getAddress();
    
    // Admin approves the upgrade
    await mainVault.connect(admin).approveMainVaultUpgrade(newImplementationAddress);
    
    // Main investor approves the upgrade
    await mainVault.connect(mainInvestor).approveMainVaultUpgrade(newImplementationAddress);
    
    // Verify approvals are set correctly
    expect(await mainVault.adminApprovedMainVaultImpl()).to.equal(newImplementationAddress);
    expect(await mainVault.investorApprovedMainVaultImpl()).to.equal(newImplementationAddress);
    
    // Admin performs the upgrade
    await mainVault.connect(admin).upgradeToAndCall(newImplementationAddress, "0x");
    
    // Verify upgrade was successful
    const newImplAddress = await ethers.provider.getStorage(await mainVault.getAddress(), "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc");
    expect(newImplAddress).to.not.equal(currentImplAddress);
    expect(newImplAddress.slice(-40).toLowerCase()).to.equal(newImplementationAddress.slice(2).toLowerCase());
    
    // Verify approval state is cleared
    expect(await mainVault.adminApprovedMainVaultImpl()).to.equal(ethers.ZeroAddress);
    expect(await mainVault.investorApprovedMainVaultImpl()).to.equal(ethers.ZeroAddress);
    
    // Verify roles are preserved after upgrade
    expect(await mainVault.hasRole(await mainVault.MAIN_INVESTOR_ROLE(), await mainInvestor.getAddress())).to.be.true;
    expect(await mainVault.hasRole(await mainVault.ADMIN_ROLE(), await admin.getAddress())).to.be.true;
  });

  it("Should fail to upgrade with only admin approval", async function () {
    // Deploy MainVaultSwapLibrary first for the new implementation
    const MainVaultSwapLibrary = await ethers.getContractFactory("MainVaultSwapLibrary");
    const mainVaultSwapLibrary = await MainVaultSwapLibrary.deploy();

    const MainVaultV2 = await ethers.getContractFactory("MainVault", {
      libraries: {
        MainVaultSwapLibrary: await mainVaultSwapLibrary.getAddress(),
      },
    });
    const implementation = await MainVaultV2.deploy();
    const implementationAddress = await implementation.getAddress();
    
    // Only admin approves
    await mainVault.connect(admin).approveMainVaultUpgrade(implementationAddress);
    
    // Attempt to upgrade should fail
    await expect(
      mainVault.connect(admin).upgradeToAndCall(implementationAddress, "0x")
    ).to.be.revertedWithCustomError(mainVault, "ImplementationNotApprovedByInvestor");
  });

  it("Should fail to upgrade with expired approval", async function () {
    // Deploy MainVaultSwapLibrary first for the new implementation
    const MainVaultSwapLibrary = await ethers.getContractFactory("MainVaultSwapLibrary");
    const mainVaultSwapLibrary = await MainVaultSwapLibrary.deploy();

    const MainVaultV2 = await ethers.getContractFactory("MainVault", {
      libraries: {
        MainVaultSwapLibrary: await mainVaultSwapLibrary.getAddress(),
      },
    });
    const implementation = await MainVaultV2.deploy();
    const implementationAddress = await implementation.getAddress();
    
    // Both approve
    await mainVault.connect(admin).approveMainVaultUpgrade(implementationAddress);
    await mainVault.connect(mainInvestor).approveMainVaultUpgrade(implementationAddress);
    
    // Increase time by more than UPGRADE_TIME_LIMIT (1 day)
    await ethers.provider.send("evm_increaseTime", [86401]); // 1 day + 1 second
    await ethers.provider.send("evm_mine", []);
    
    // Attempt to upgrade should fail
    await expect(
      mainVault.connect(admin).upgradeToAndCall(implementationAddress, "0x")
    ).to.be.revertedWithCustomError(mainVault, "UpgradeDeadlineExpired");
  });

  it("Should fail to upgrade with different approvals", async function () {
    // Deploy MainVaultSwapLibrary first
    const MainVaultSwapLibrary = await ethers.getContractFactory("MainVaultSwapLibrary");
    const mainVaultSwapLibrary = await MainVaultSwapLibrary.deploy();

    const MainVaultV2 = await ethers.getContractFactory("MainVault", {
      libraries: {
        MainVaultSwapLibrary: await mainVaultSwapLibrary.getAddress(),
      },
    });
    
    // Deploy two different implementations
    const implementation1 = await MainVaultV2.deploy();
    const implementation2 = await MainVaultV2.deploy();
    const impl1Address = await implementation1.getAddress();
    const impl2Address = await implementation2.getAddress();
    
    // Admin approves one, investor approves another
    await mainVault.connect(admin).approveMainVaultUpgrade(impl1Address);
    await mainVault.connect(mainInvestor).approveMainVaultUpgrade(impl2Address);
    
    // Attempt to upgrade to either should fail
    await expect(
      mainVault.connect(admin).upgradeToAndCall(impl1Address, "0x")
    ).to.be.revertedWithCustomError(mainVault, "ImplementationNotApprovedByInvestor");
    
    await expect(
      mainVault.connect(admin).upgradeToAndCall(impl2Address, "0x")
    ).to.be.revertedWithCustomError(mainVault, "ImplementationNotApprovedByAdmin");
  });
}); 