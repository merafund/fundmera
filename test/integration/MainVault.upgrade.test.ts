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
      meraPriceOracle: await meraPriceOracle.getAddress()
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
    
    // Prepare upgrade data and get signature from main investor
    const deadline = Math.floor(Date.now() / 1000) + 3600; // 1 hour from now
    
    const domain = {
      name: "MainVault",
      version: "1",
      chainId: (await ethers.provider.getNetwork()).chainId,
      verifyingContract: await mainVault.getAddress(),
    };
    
    const types = {
      FutureMainVaultImplementation: [
        { name: "implementation", type: "address" },
        { name: "deadline", type: "uint64" },
      ],
    };
    
    const value = {
      implementation: newImplementationAddress,
      deadline: deadline,
    };
    
    // Get signature from main investor
    const signature = await mainInvestor.signTypedData(domain, types, value);
    
    // Admin sets the future implementation with main investor's signature
    await mainVault.connect(admin).setFutureMainVaultImplementation(
      {
        implementation: newImplementationAddress,
        deadline: deadline,
      },
      signature
    );
    
    // Verify future implementation is set correctly
    expect(await mainVault.nextFutureImplementationOfMainVault()).to.equal(newImplementationAddress);
    expect(await mainVault.nextFutureImplementationOfMainVaultDeadline()).to.equal(deadline);
    
    // Admin performs the upgrade
    await mainVault.connect(admin).upgradeToAndCall(newImplementationAddress, "0x");
    
    // Verify upgrade was successful
    const newImplAddress = await ethers.provider.getStorage(await mainVault.getAddress(), "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc");
    expect(newImplAddress).to.not.equal(currentImplAddress);
    expect(newImplAddress.slice(-40).toLowerCase()).to.equal(newImplementationAddress.slice(2).toLowerCase());
    
    // Verify roles are preserved after upgrade
    expect(await mainVault.hasRole(await mainVault.MAIN_INVESTOR_ROLE(), await mainInvestor.getAddress())).to.be.true;
    expect(await mainVault.hasRole(await mainVault.ADMIN_ROLE(), await admin.getAddress())).to.be.true;
  });

  it("Should fail to upgrade with invalid signature", async function () {
    // Deploy MainVaultSwapLibrary first for the new implementation
    const MainVaultSwapLibrary = await ethers.getContractFactory("MainVaultSwapLibrary");
    const mainVaultSwapLibrary = await MainVaultSwapLibrary.deploy();

    const MainVaultV2 = await ethers.getContractFactory("MainVault", {
      libraries: {
        MainVaultSwapLibrary: await mainVaultSwapLibrary.getAddress(),
      },
    });
    const implementation = await MainVaultV2.deploy();
    
    const deadline = Math.floor(Date.now() / 1000) + 3600;
    
    // Create invalid signature (signed by wrong account)
    const domain = {
      name: "MainVault",
      version: "1",
      chainId: (await ethers.provider.getNetwork()).chainId,
      verifyingContract: await mainVault.getAddress(),
    };
    
    const types = {
      FutureMainVaultImplementation: [
        { name: "implementation", type: "address" },
        { name: "deadline", type: "uint64" },
      ],
    };
    
    const value = {
      implementation: await implementation.getAddress(),
      deadline: deadline,
    };
    
    // Sign with wrong account (admin instead of main investor)
    const signature = await admin.signTypedData(domain, types, value);
    
    // Attempt to set future implementation should fail
    await expect(
      mainVault.connect(admin).setFutureMainVaultImplementation(
        {
          implementation: await implementation.getAddress(),
          deadline: deadline,
        },
        signature
      )
    ).to.be.revertedWithCustomError(mainVault, "InvalidSigner");
  });

  it("Should fail to upgrade with expired deadline", async function () {
    // Deploy MainVaultSwapLibrary first for the new implementation
    const MainVaultSwapLibrary = await ethers.getContractFactory("MainVaultSwapLibrary");
    const mainVaultSwapLibrary = await MainVaultSwapLibrary.deploy();

    const MainVaultV2 = await ethers.getContractFactory("MainVault", {
      libraries: {
        MainVaultSwapLibrary: await mainVaultSwapLibrary.getAddress(),
      },
    });
    const implementation = await MainVaultV2.deploy();
    
    // Set deadline in the past
    const deadline = Math.floor(Date.now() / 1000) - 3600; // 1 hour ago
    
    const domain = {
      name: "MainVault",
      version: "1",
      chainId: (await ethers.provider.getNetwork()).chainId,
      verifyingContract: await mainVault.getAddress(),
    };
    
    const types = {
      FutureMainVaultImplementation: [
        { name: "implementation", type: "address" },
        { name: "deadline", type: "uint64" },
      ],
    };
    
    const value = {
      implementation: await implementation.getAddress(),
      deadline: deadline,
    };
    
    const signature = await mainInvestor.signTypedData(domain, types, value);
    
    // Attempt to set future implementation should fail
    await expect(
      mainVault.connect(admin).setFutureMainVaultImplementation(
        {
          implementation: await implementation.getAddress(),
          deadline: deadline,
        },
        signature
      )
    ).to.be.revertedWithCustomError(mainVault, "TimestampMustBeInTheFuture");
  });
}); 