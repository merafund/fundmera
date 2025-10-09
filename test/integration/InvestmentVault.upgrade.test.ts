import { expect } from "chai";
import { ethers } from "hardhat";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { InvestmentVault, MainVault, IERC20, MockToken } from "../../typechain-types";

describe("InvestmentVault Upgrade Tests", function () {
  let mainVault: MainVault;
  let investmentVault: InvestmentVault;
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
  let tokenMI: MockToken;
  let tokenMV: MockToken;

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
    ] = await ethers.getSigners();

    // Deploy mock tokens
    console.log("Deploying mock tokens...");
    const MockToken = await ethers.getContractFactory("MockToken");
    tokenMI = (await MockToken.deploy("Mock Token MI", "MTI", 18)) as unknown as MockToken;
    await tokenMI.waitForDeployment();
    const tokenMIAddress = await tokenMI.getAddress();
    console.log("TokenMI deployed at:", tokenMIAddress);

    tokenMV = (await MockToken.deploy("Mock Token MV", "MTV", 18)) as unknown as MockToken;
    await tokenMV.waitForDeployment();
    const tokenMVAddress = await tokenMV.getAddress();
    console.log("TokenMV deployed at:", tokenMVAddress);

    // Deploy PauserList
    console.log("Deploying PauserList...");
    const PauserList = await ethers.getContractFactory("MockPauserList");
    const pauserList = await PauserList.deploy();
    await pauserList.waitForDeployment();
    const pauserListAddress = await pauserList.getAddress();
    console.log("PauserList deployed at:", pauserListAddress);

    // Deploy MainVaultSwapLibrary
    console.log("Deploying MainVaultSwapLibrary...");
    const MainVaultSwapLibrary = await ethers.getContractFactory("MainVaultSwapLibrary");
    const mainVaultSwapLibrary = await MainVaultSwapLibrary.deploy();
    await mainVaultSwapLibrary.waitForDeployment();
    const mainVaultSwapLibraryAddress = await mainVaultSwapLibrary.getAddress();
    console.log("MainVaultSwapLibrary deployed at:", mainVaultSwapLibraryAddress);

    // Deploy SwapLibrary
    console.log("Deploying SwapLibrary...");
    const SwapLibrary = await ethers.getContractFactory("SwapLibrary");
    const swapLibrary = await SwapLibrary.deploy();
    await swapLibrary.waitForDeployment();
    const swapLibraryAddress = await swapLibrary.getAddress();
    console.log("SwapLibrary deployed at:", swapLibraryAddress);

    // Deploy MeraPriceOracle
    console.log("Deploying MeraPriceOracle...");
    const MeraPriceOracle = await ethers.getContractFactory("MockMeraPriceOracle");
    const meraPriceOracle = await MeraPriceOracle.deploy();
    await meraPriceOracle.waitForDeployment();
    const meraPriceOracleAddress = await meraPriceOracle.getAddress();
    console.log("MeraPriceOracle deployed at:", meraPriceOracleAddress);

    // Deploy MainVault implementation
    console.log("Deploying MainVault implementation...");
    const MainVault = await ethers.getContractFactory("MainVault", {
      libraries: {
        MainVaultSwapLibrary: mainVaultSwapLibraryAddress,
      },
    });
    const mainVaultImpl = await MainVault.deploy();
    await mainVaultImpl.waitForDeployment();
    const mainVaultImplAddress = await mainVaultImpl.getAddress();
    console.log("MainVault implementation deployed at:", mainVaultImplAddress);

    // Deploy InvestmentVault implementation
    console.log("Deploying InvestmentVault implementation...");
    const InvestmentVault = await ethers.getContractFactory("InvestmentVault", {
      libraries: {
        SwapLibrary: swapLibraryAddress,
      },
    });
    const investmentVaultImpl = await InvestmentVault.deploy();
    await investmentVaultImpl.waitForDeployment();
    const investmentVaultImplAddress = await investmentVaultImpl.getAddress();
    console.log("InvestmentVault implementation deployed at:", investmentVaultImplAddress);

    // Get all required addresses
    console.log("Getting signer addresses...");
    const mainInvestorAddress = await mainInvestor.getAddress();
    const backupInvestorAddress = await backupInvestor.getAddress();
    const emergencyInvestorAddress = await emergencyInvestor.getAddress();
    const managerAddress = await manager.getAddress();
    const adminAddress = await admin.getAddress();
    const backupAdminAddress = await backupAdmin.getAddress();
    const emergencyAdminAddress = await emergencyAdmin.getAddress();
    const feeWalletAddress = await feeWallet.getAddress();
    const profitWalletAddress = await profitWallet.getAddress();

    console.log("Preparing MainVault initialization data...");
    const mainVaultParams = {
      mainInvestor: mainInvestorAddress,
      backupInvestor: backupInvestorAddress,
      emergencyInvestor: emergencyInvestorAddress,
      manager: managerAddress,
      admin: adminAddress,
      backupAdmin: backupAdminAddress,
      emergencyAdmin: emergencyAdminAddress,
      feeWallet: feeWalletAddress,
      profitWallet: profitWalletAddress,
      feePercentage: BigInt(100), // 1%
      currentImplementationOfInvestmentVault: investmentVaultImplAddress,
      pauserList: pauserListAddress,
      meraPriceOracle: meraPriceOracleAddress,
      lockPeriod: BigInt(0) // No lock period for test
    };
    console.log("MainVault initialization params:", mainVaultParams);

    // Prepare initialization data for MainVault
    const mainVaultInitData = MainVault.interface.encodeFunctionData("initialize", [mainVaultParams]);
    console.log("MainVault initialization data encoded");

    // Deploy MainVault proxy
    console.log("Deploying MainVault proxy...");
    const ERC1967Proxy = await ethers.getContractFactory("ERC1967Proxy");
    const mainVaultProxy = await ERC1967Proxy.deploy(
      mainVaultImplAddress,
      mainVaultInitData
    );
    await mainVaultProxy.waitForDeployment();
    const mainVaultProxyAddress = await mainVaultProxy.getAddress();
    console.log("MainVault proxy deployed at:", mainVaultProxyAddress);
    mainVault = MainVault.attach(mainVaultProxyAddress) as unknown as MainVault;

    // Mint some tokens for testing
    console.log("Minting test tokens...");
    await tokenMI.mint(mainInvestorAddress, ethers.parseEther("10000"));
    await tokenMV.mint(mainVaultProxyAddress, ethers.parseEther("10000"));
    console.log("Tokens minted");

    // Prepare initialization data for InvestmentVault
    console.log("Preparing InvestmentVault initialization data...");
    const investmentVaultParams = {
      mainVault: mainVaultProxyAddress,
      tokenMI: await tokenMI.getAddress(),
      tokenMV: await tokenMV.getAddress(),
      capitalOfMi: ethers.parseEther("1000"),
      shareMI: ethers.parseEther("0.5"),
      step: ethers.parseEther("0.1"),
      assets: []
    };
    console.log("InvestmentVault initialization params:", investmentVaultParams);

    const investmentVaultInitData = InvestmentVault.interface.encodeFunctionData("initialize", [investmentVaultParams]);
    console.log("InvestmentVault initialization data encoded");

    // Deploy InvestmentVault proxy
    console.log("Deploying InvestmentVault proxy...");
    const investmentVaultProxy = await ERC1967Proxy.deploy(
      investmentVaultImplAddress,
      investmentVaultInitData
    );
    await investmentVaultProxy.waitForDeployment();
    const investmentVaultProxyAddress = await investmentVaultProxy.getAddress();
    console.log("InvestmentVault proxy deployed at:", investmentVaultProxyAddress);
    investmentVault = InvestmentVault.attach(investmentVaultProxyAddress) as unknown as InvestmentVault;
  });

  it("Should set up initial state correctly", async function () {
    expect(await investmentVault.mainVault()).to.equal(await mainVault.getAddress());
    const tokenData = await investmentVault.tokenData();
    expect(tokenData.tokenMI).to.equal(await tokenMI.getAddress());
    expect(tokenData.tokenMV).to.equal(await tokenMV.getAddress());
  });

  it("Should upgrade contract successfully", async function () {
    // Deploy SwapLibrary for new implementation
    const SwapLibrary = await ethers.getContractFactory("SwapLibrary");
    const swapLibrary = await SwapLibrary.deploy();

    // Deploy new implementation
    const InvestmentVaultV2 = await ethers.getContractFactory("InvestmentVault", {
      libraries: {
        SwapLibrary: await swapLibrary.getAddress(),
      },
    });
    const newImplementation = await InvestmentVaultV2.deploy();
    const newImplAddress = await newImplementation.getAddress();
    
    // Get current implementation address for comparison
    const currentImplAddress = await ethers.provider.getStorage(await investmentVault.getAddress(), "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc");
    
    // Admin approves the new InvestorVault implementation
    await mainVault.connect(admin).approveInvestorVaultUpgrade(newImplAddress);
    
    // Main investor approves the new InvestorVault implementation
    await mainVault.connect(mainInvestor).approveInvestorVaultUpgrade(newImplAddress);
    
    // Verify approvals are set
    expect(await mainVault.adminApprovedInvestorVaultImpl()).to.equal(newImplAddress);
    expect(await mainVault.investorApprovedInvestorVaultImpl()).to.equal(newImplAddress);
    
    // Admin sets the current implementation (requires both approvals)
    await mainVault.connect(admin).setCurrentImplementationOfInvestmentVault(newImplAddress);
    
    // Verify MainVault has the correct implementation set
    expect(await mainVault.currentImplementationOfInvestmentVault()).to.equal(newImplAddress);
    
    // Verify approval state is cleared
    expect(await mainVault.adminApprovedInvestorVaultImpl()).to.equal(ethers.ZeroAddress);
    expect(await mainVault.investorApprovedInvestorVaultImpl()).to.equal(ethers.ZeroAddress);
    
    // Verify mainInvestor does not have ADMIN_ROLE
    expect(await mainVault.hasRole(await mainVault.ADMIN_ROLE(), await mainInvestor.getAddress())).to.be.false;
    
    // Upgrade InvestmentVault
    await investmentVault.connect(admin).upgradeToAndCall(newImplAddress, "0x");
    
    // Verify upgrade was successful
    const finalImplAddress = await ethers.provider.getStorage(await investmentVault.getAddress(), "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc");
    expect(finalImplAddress).to.not.equal(currentImplAddress);
    expect(finalImplAddress.slice(-40).toLowerCase()).to.equal(newImplAddress.slice(2).toLowerCase());
    
    // Verify state is preserved
    expect(await investmentVault.mainVault()).to.equal(await mainVault.getAddress());
    const tokenData = await investmentVault.tokenData();
    expect(tokenData.tokenMI).to.equal(await tokenMI.getAddress());
    expect(tokenData.tokenMV).to.equal(await tokenMV.getAddress());
  });

  it("Should fail to upgrade with invalid implementation", async function () {
    // Deploy SwapLibrary for new implementation
    const SwapLibrary = await ethers.getContractFactory("SwapLibrary");
    const swapLibrary = await SwapLibrary.deploy();

    // Deploy new implementation without setting it in MainVault
    const InvestmentVaultV2 = await ethers.getContractFactory("InvestmentVault", {
      libraries: {
        SwapLibrary: await swapLibrary.getAddress(),
      },
    });
    const invalidImplementation = await InvestmentVaultV2.deploy();
    
    // Attempt to upgrade should fail
    await expect(
      investmentVault.connect(admin).upgradeToAndCall(await invalidImplementation.getAddress(), "0x")
    ).to.be.revertedWithCustomError(investmentVault, "InvalidImplementationAddress");
  });

  it("Should fail to upgrade if not admin", async function () {
    // Deploy SwapLibrary for new implementation
    const SwapLibrary = await ethers.getContractFactory("SwapLibrary");
    const swapLibrary = await SwapLibrary.deploy();

    // Deploy new implementation
    const InvestmentVaultV2 = await ethers.getContractFactory("InvestmentVault", {
      libraries: {
        SwapLibrary: await swapLibrary.getAddress(),
      },
    });
    const newImplementation = await InvestmentVaultV2.deploy();
    const newImplAddress = await newImplementation.getAddress();
    
    // Admin and investor approve the upgrade
    await mainVault.connect(admin).approveInvestorVaultUpgrade(newImplAddress);
    await mainVault.connect(mainInvestor).approveInvestorVaultUpgrade(newImplAddress);
    
    // Admin sets the current implementation
    await mainVault.connect(admin).setCurrentImplementationOfInvestmentVault(newImplAddress);
    
    // Verify mainInvestor does not have ADMIN_ROLE
    expect(await mainVault.hasRole(await mainVault.ADMIN_ROLE(), await mainInvestor.getAddress())).to.be.false;
    
    // Attempt to upgrade from non-admin account should fail
    await expect(
      investmentVault.connect(mainInvestor).upgradeToAndCall(newImplAddress, "0x")
    ).to.be.reverted;
  });
}); 