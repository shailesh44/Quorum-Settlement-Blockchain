const { ethers } = require("ethers");

async function main() {
  console.log("============================================================");
  console.log("  VittaGems — Quick Transaction Test");
  console.log("============================================================\n");

  const provider = new ethers.JsonRpcProvider("http://localhost:8545");

  const network = await provider.getNetwork();
  console.log("  Chain ID:", network.chainId.toString());

  const blockNum = await provider.getBlockNumber();
  console.log("  Current block:", blockNum);

  if (blockNum === 0) {
    console.log("\n  ⚠ Network is at block 0 — validators may not be producing blocks yet.");
    console.log("  Check: docker logs vittagems-validator1 --tail 50");
    return;
  }

  const wallet = new ethers.Wallet("0x16db8ff1ac1bfb1831db9a328c2181a84c4cde715ced0767afb9fe95e7c3378b", provider);
  console.log("  Sender:", wallet.address);

  const balance = await provider.getBalance(wallet.address);
  console.log("  Balance:", ethers.formatEther(balance), "ETH");

  const testAddr = "0xb20b61434544abb5add8999c0a1209f8326d570a";
  console.log("\n  Sending 1 ETH (zero gas) to", testAddr, "...");

  const tx = await wallet.sendTransaction({
    to: testAddr,
    value: ethers.parseEther("1.0"),
    gasPrice: 0,
    gasLimit: 21000,
    type: 0,
  });

  console.log("  TX hash:", tx.hash);
  const receipt = await tx.wait();
  console.log("  Confirmed in block:", receipt.blockNumber);
  console.log("  Gas used:", receipt.gasUsed.toString());
  console.log("\n  ✓ Zero-gas transaction successful!");
  console.log("============================================================");
}

main().catch((err) => {
  console.error("\n  ✗ Error:", err.message);
  console.error("  → Check: npm run network:status");
});
