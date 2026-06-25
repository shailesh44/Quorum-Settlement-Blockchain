/**
 * VittaGems Week 2 — Deploy Permissioning Contracts
 * ===================================================
 * Deploys NodePermissioning + AccountPermissioning and registers
 * all existing network nodes and operator accounts.
 *
 * Run: npx hardhat run scripts/deploy-permissioning.js --network quorum_local
 */

const hre = require("hardhat");
const fs = require("fs");

async function main() {
  const [deployer] = await hre.ethers.getSigners();

  console.log("============================================================");
  console.log("  VittaGems — Permissioning Contracts Deployment");
  console.log("============================================================");
  console.log(`  Deployer: ${deployer.address}`);
  console.log(`  Network:  ${hre.network.name}\n`);

  // Load network info for node registration
  const networkInfoPath = "./config/network-info.json";
  let networkInfo = null;
  if (fs.existsSync(networkInfoPath)) {
    networkInfo = JSON.parse(fs.readFileSync(networkInfoPath, "utf8"));
    console.log("  ✓ Loaded network-info.json for node registration\n");
  } else {
    console.log("  ⚠ No network-info.json found — skipping auto-registration\n");
  }

  // ──────────────────────────────────────────────────
  // 1. Deploy Node Permissioning
  // ──────────────────────────────────────────────────
  console.log("  Deploying VittaGemsNodePermissioning...");

  const NodePerm = await hre.ethers.getContractFactory("VittaGemsNodePermissioning");
  const nodePerm = await NodePerm.deploy();
  await nodePerm.waitForDeployment();
  const nodePermAddress = await nodePerm.getAddress();

  console.log(`  ✓ NodePermissioning deployed: ${nodePermAddress}\n`);

  // ──────────────────────────────────────────────────
  // 2. Deploy Account Permissioning
  // ──────────────────────────────────────────────────
  console.log("  Deploying VittaGemsAccountPermissioning...");

  const AcctPerm = await hre.ethers.getContractFactory("VittaGemsAccountPermissioning");
  const acctPerm = await AcctPerm.deploy();
  await acctPerm.waitForDeployment();
  const acctPermAddress = await acctPerm.getAddress();

  console.log(`  ✓ AccountPermissioning deployed: ${acctPermAddress}\n`);

  // ──────────────────────────────────────────────────
  // 3. Register existing network nodes
  // ──────────────────────────────────────────────────
  if (networkInfo) {
    console.log("  Registering network nodes...\n");

    // Read static-nodes.json to get enode IDs
    const staticNodesPath = "./config/static-nodes.json";
    if (fs.existsSync(staticNodesPath)) {
      const staticNodes = JSON.parse(fs.readFileSync(staticNodesPath, "utf8"));

      for (const enodeUrl of staticNodes) {
        // Parse enode URL: enode://PUBKEY@HOST:PORT?discport=0
        const match = enodeUrl.match(/enode:\/\/([a-f0-9]+)@([^:]+):(\d+)/);
        if (!match) {
          console.log(`    ⚠ Could not parse: ${enodeUrl.substring(0, 40)}...`);
          continue;
        }

        const [, enodeId, host, port] = match;

        // Determine node name from hostname
        const nodeName = host; // Docker hostname = node name
        const isValidator = host.startsWith("validator");
        const orgId = "VittaGems";

        try {
          const tx = await nodePerm.addNode(
            enodeId,
            host,
            parseInt(port),
            nodeName,
            orgId
          );
          await tx.wait();
          console.log(`    ✓ Registered: ${nodeName} (${enodeId.substring(0, 16)}...)`);
        } catch (err) {
          console.log(`    ⚠ Skipped ${nodeName}: ${err.message.substring(0, 60)}`);
        }
      }
    }
  }

  // ──────────────────────────────────────────────────
  // 4. Register deployer account
  // ──────────────────────────────────────────────────
  console.log("\n  Registering operator accounts...\n");

  // Deployer is already registered in constructor as ADMIN
  console.log(`    ✓ Deployer registered as ADMIN: ${deployer.address}`);

  // ──────────────────────────────────────────────────
  // 5. Verify deployment
  // ──────────────────────────────────────────────────
  console.log("\n  Verifying deployment...\n");

  const [totalNodes, activeNodesCount] = await nodePerm.getNodeCount();
  console.log(`    Nodes:    ${activeNodesCount} active / ${totalNodes} total`);

  const [totalAccts, activeAccts] = await acctPerm.getAccountCount();
  console.log(`    Accounts: ${activeAccts} active / ${totalAccts} total`);

  const deployerAllowed = await acctPerm.isAccountAllowed(deployer.address);
  console.log(`    Deployer allowed: ${deployerAllowed}`);

  // ──────────────────────────────────────────────────
  // 6. Save deployment
  // ──────────────────────────────────────────────────
  const deployDir = "./deployments";
  if (!fs.existsSync(deployDir)) fs.mkdirSync(deployDir, { recursive: true });

  const permDeployment = {
    network: hre.network.name,
    chainId: (await hre.ethers.provider.getNetwork()).chainId.toString(),
    deployedAt: new Date().toISOString(),
    deployer: deployer.address,
    contracts: {
      nodePermissioning: {
        address: nodePermAddress,
        contract: "VittaGemsNodePermissioning",
      },
      accountPermissioning: {
        address: acctPermAddress,
        contract: "VittaGemsAccountPermissioning",
      },
    },
    registeredNodes: Number(totalNodes),
    registeredAccounts: Number(totalAccts),
  };

  const permPath = `${deployDir}/permissioning-deployment.json`;
  fs.writeFileSync(permPath, JSON.stringify(permDeployment, null, 2));

  console.log(`\n  Saved to ${permPath}`);

  console.log("\n============================================================");
  console.log("  Permissioning Deployment Complete");
  console.log("============================================================");
  console.log(`\n  Node Permissioning:    ${nodePermAddress}`);
  console.log(`  Account Permissioning: ${acctPermAddress}`);
  console.log("\n  Next steps:");
  console.log("    1. Run the permissioning test:");
  console.log("       npx hardhat run scripts/test-permissioning.js --network quorum_local");
  console.log("    2. Run the validator failover test:");
  console.log("       bash scripts/test-validator-failover.sh");
  console.log("============================================================\n");
}

main().catch((error) => {
  console.error("\n  ✗ Deployment failed:", error.message);
  process.exitCode = 1;
});
