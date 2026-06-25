const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();

  console.log("============================================================");
  console.log("  VittaGems Settlement Contract — Deployment");
  console.log("============================================================");
  console.log("  Deployer:", deployer.address);
  console.log("  Network:", hre.network.name);
  console.log("  Chain ID:", (await hre.ethers.provider.getNetwork()).chainId.toString());
  console.log("");

  // Deploy parameters
  const reserveLimit          = hre.ethers.parseEther("10000000");   // 10M initial reserve limit
  const perTransactionLimit   = hre.ethers.parseEther("1000000");    // 1M per transaction
  const dailyLimit            = hre.ethers.parseEther("5000000");    // 5M daily
  const multiSigThreshold     = hre.ethers.parseEther("500000");     // 500K multi-sig threshold

  console.log("  Reserve Limit:          10,000,000");
  console.log("  Per-Transaction Limit:   1,000,000");
  console.log("  Daily Limit:             5,000,000");
  console.log("  Multi-Sig Threshold:       500,000");
  console.log("");

  // Deploy contract
  console.log("  Deploying VittaGemsSettlement...");
  const Settlement = await hre.ethers.getContractFactory("VittaGemsSettlement");
  const settlement = await Settlement.deploy(
    reserveLimit, perTransactionLimit, dailyLimit, multiSigThreshold
);

  await settlement.waitForDeployment();
  const address = await settlement.getAddress();

  console.log("");
  console.log("  ✓ VittaGemsSettlement deployed to:", address);
  console.log("");

  // Verify roles
  const TREASURY_ADMIN = await settlement.TREASURY_ADMIN();
  const hasTreasury = await settlement.hasRole(TREASURY_ADMIN, deployer.address);
  console.log("  ✓ Deployer has TREASURY_ADMIN:", hasTreasury);

  const DEFAULT_ADMIN = await settlement.DEFAULT_ADMIN_ROLE();
  const hasAdmin = await settlement.hasRole(DEFAULT_ADMIN, deployer.address);
  console.log("  ✓ Deployer has DEFAULT_ADMIN:", hasAdmin);

  console.log("");
  console.log("============================================================");
  console.log("  Deployment complete. Save the contract address above.");
  console.log("============================================================");

  // Save deployment info
  const fs = require("fs");
  const deploymentInfo = {
    network: hre.network.name,
    chainId: (await hre.ethers.provider.getNetwork()).chainId.toString(),
    contract: "VittaGemsSettlement",
    address: address,
    deployer: deployer.address,
    deployedAt: new Date().toISOString(),
    parameters: {
      reserveLimit: reserveLimit.toString(),
      perTransactionLimit: perTransactionLimit.toString(),
      dailyLimit: dailyLimit.toString(),
      multiSigThreshold: multiSigThreshold.toString(),
    },
  };

  const deployDir = "./deployments";
  if (!fs.existsSync(deployDir)) fs.mkdirSync(deployDir, { recursive: true });
  fs.writeFileSync(
    `${deployDir}/${hre.network.name}-deployment.json`,
    JSON.stringify(deploymentInfo, null, 2)
  );
  console.log(`  Saved to ${deployDir}/${hre.network.name}-deployment.json`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
