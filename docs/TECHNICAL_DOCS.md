# VittaGems Settlement Blockchain — Technical Documentation

**Version:** 1.0
**Last Updated:** June 2026
**Audience:** Blockchain Engineering Team
**Network:** GoQuorum (IBFT Consensus) | Chain ID: 7001

---

## Table of Contents

1. Project Overview
2. Architecture
3. Prerequisites & Environment Setup
4. Network Deployment
5. Smart Contracts
6. Testing Guide
7. Node Onboarding Runbook
8. Monitoring & Observability
9. Operational Procedures
10. Port Reference
11. Troubleshooting
12. AWS Deployment (Week 3)

---

## 1. Project Overview

VittaGems is a permissioned B2B settlement network built on Quorum that serves as the invisible infrastructure layer between U.S. dollar funding sources and authorized regional payout partners in destination countries. The blockchain layer provides deterministic transaction finality, reserve-backed token issuance, and immutable auditability for every settlement event.

### What This Network Does

The blockchain handles steps 2 and 3 of the VittaGems settlement flow:

1. **USD On-Ramp** (off-chain) — US provider collects USD from sender
2. **Mint & Compliance** (on-chain) — Treasury checks, KYC/AML controls, settlement value issued on-chain
3. **Near Real-Time Settlement** (on-chain) — Value transferred to regional partner on the permissioned ledger
4. **Final Local Payout** (off-chain) — Regional partner executes bank deposit, mobile wallet, or cash pickup

### Settlement Lifecycle States

Every settlement moves through these deterministic states:

```
CREATED → COMPLIANCE_APPROVED → MINTED → TRANSFERRED → PAYOUT_CONFIRMED → CLOSED
```

Exception states: `ON_HOLD` (compliance review), `FROZEN` (sanctions hit)

### Technology Stack

- **Blockchain:** GoQuorum (Go-Ethereum fork for enterprise)
- **Consensus:** IBFT (Istanbul Byzantine Fault Tolerance)
- **Smart Contracts:** Solidity 0.8.20 with OpenZeppelin
- **Development Framework:** Hardhat
- **Container Orchestration:** Docker Compose
- **Monitoring:** Prometheus + Grafana
- **Language/Runtime:** Node.js 20+, Go 1.22+

---

## 2. Architecture

### Network Topology

```
┌─────────────────────────────────────────────────────────┐
│                    Docker Network                        │
│                                                         │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐    │
│  │ Validator 1  │  │ Validator 2  │  │ Validator 3  │    │
│  │ IBFT Mining  │  │ IBFT Mining  │  │ IBFT Mining  │    │
│  │ RPC: 8545   │  │ RPC: 8547   │  │ RPC: 8549   │    │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘    │
│         │                │                │             │
│         └────────────────┼────────────────┘             │
│                          │                              │
│  ┌─────────────┐  ┌─────┴───────┐  ┌─────────────┐    │
│  │   RPC 1     │  │  Boot Node  │  │   RPC 2     │    │
│  │ API Access  │  │  Discovery  │  │ API Access  │    │
│  │ RPC: 8551   │  │             │  │ RPC: 8553   │    │
│  └─────────────┘  └─────────────┘  └─────────────┘    │
│                                                         │
│  ┌─────────────┐  ┌─────────────┐                      │
│  │ Prometheus  │  │  Grafana    │                      │
│  │ Port: 9090  │  │ Port: 3000  │                      │
│  └─────────────┘  └─────────────┘                      │
└─────────────────────────────────────────────────────────┘
```

### Node Types Explained

**Validator Nodes (3):** Participate in IBFT consensus. They propose blocks, vote on proposals, and sign blocks. Validators are the only nodes that run `--mine`. With 3 validators, the network tolerates 1 failure (IBFT requires ⌈2N/3⌉ validators online). If 2 validators go down, block production halts but no data is lost — it resumes automatically when quorum is restored.

**RPC Nodes (2):** Serve the JSON-RPC API to external applications (the settlement engine, compliance system, etc). They sync the blockchain but do not participate in consensus. Having 2 provides redundancy — if one goes down, applications can failover to the other.

**Boot Node (1):** Helps new nodes discover peers when they first join the network. Uses the `static-nodes.json` file. Not critical for ongoing operation — if the bootnode goes down, existing peers remain connected.

### Consensus: IBFT (Istanbul BFT)

IBFT is a Byzantine Fault Tolerant consensus mechanism. Key properties:

- **Immediate finality:** Once a block is added, it cannot be reverted. No forks, no reorgs. This is critical for settlement — when a transfer is confirmed, it is final.
- **Block period:** 5 seconds (configurable via `--istanbul.blockperiod`)
- **Fault tolerance:** Tolerates ⌊(N-1)/3⌋ faulty validators. With 3 validators, tolerates 1 failure.
- **Zero gas:** Transactions cost nothing. Configured via `--miner.gasprice 0` on all nodes.

### Smart Contract Architecture

```
OpenZeppelin AccessControl
        │
        ├── VittaGemsRBAC
        │   ├── TREASURY_ADMIN
        │   ├── COMPLIANCE_OPERATOR
        │   ├── SETTLEMENT_AGENT
        │   ├── AUDITOR
        │   └── PARTNER
        │
        ├── VittaGemsSettlement (inherits VittaGemsRBAC)
        │   ├── mintWithTreasuryApproval()    → TREASURY_ADMIN only
        │   ├── transfer()                    → SETTLEMENT_AGENT only
        │   ├── burn()                        → SETTLEMENT_AGENT only
        │   ├── hold() / release()            → COMPLIANCE_OPERATOR only
        │   ├── freeze() / unfreeze()         → COMPLIANCE_OPERATOR only
        │   ├── reconcile()                   → SETTLEMENT_AGENT only
        │   └── View functions                → Any role
        │
        ├── VittaGemsNodePermissioning
        │   ├── connectionAllowed()           → Called by GoQuorum P2P layer
        │   ├── addNode() / removeNode()      → NODE_ADMIN only
        │   └── updateNode()                  → NODE_ADMIN only
        │
        └── VittaGemsAccountPermissioning
            ├── transactionAllowed()          → Called by GoQuorum before every tx
            ├── addAccount() / removeAccount() → ACCOUNT_ADMIN only
            └── changeAccountType()           → ACCOUNT_ADMIN only
```

---

## 3. Prerequisites & Environment Setup

### System Requirements

- **OS:** Ubuntu 22.04 LTS (tested and verified)
- **RAM:** Minimum 8 GB (16 GB recommended)
- **Disk:** Minimum 50 GB free
- **CPU:** 2+ cores

### Step 1: Install System Dependencies

If you already have the project cloned, there is a setup script `vittagems-env-setup.sh` that installs everything. Otherwise, install manually:

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl wget git build-essential jq tree python3
```

### Step 2: Install Docker & Docker Compose

Docker runs all Quorum nodes as containers. Docker Compose orchestrates them.

```bash
# Add Docker's official repository
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Allow your user to run Docker without sudo
sudo usermod -aG docker $USER
newgrp docker

# Verify
docker --version
docker compose version
```

### Step 3: Install Node.js (v20)

Node.js runs Hardhat (our smart contract framework) and all deployment/test scripts.

```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
source ~/.bashrc
nvm install 20
nvm use 20
node --version   # Should show v20.x
```

### Step 4: Install Go 1.22

Go is needed for some Quorum tooling and if you ever need to build GoQuorum from source.

```bash
wget https://go.dev/dl/go1.22.4.linux-amd64.tar.gz
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf go1.22.4.linux-amd64.tar.gz
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
source ~/.bashrc
go version   # Should show go1.22.x
```

### Step 5: Clone & Install Project

```bash
git clone <your-repo-url> vittagems-blockchain
cd vittagems-blockchain
npm install
```

This installs Hardhat, OpenZeppelin, ethers.js, and all other project dependencies.

---

## 4. Network Deployment

### Quick Start (One Command)

The parameterized deployment script handles everything: key generation, genesis creation, node initialization, and Docker startup.

```bash
cd ~/vittagems-blockchain
sudo bash deploy-network.sh --reset
```

**What this command does internally:**

1. **Generates 6 node keys** — Uses the GoQuorum Docker image's `bootnode` tool to create a cryptographic keypair for each node. The private key (`nodekey`) identifies the node on the network. The public key becomes part of the `enode://` URL.

2. **Derives validator addresses** — Imports each validator's nodekey into geth to get its Ethereum address. These addresses are needed for the genesis file.

3. **Creates the genesis file** — The genesis block is the starting point of the blockchain. It contains:
   - `chainId: 7001` — Unique identifier for our network
   - `extraData` — RLP-encoded list of validator addresses (tells IBFT who can produce blocks)
   - `alloc` — Pre-funded accounts (each validator gets initial balance)
   - `gasLimit: 0xFFFFFFFF` — Maximum gas per block (set high because gas is free)
   - `istanbul` config — Block period, epoch length

4. **Creates static-nodes.json** — A list of all node `enode://` URLs. Each node reads this to know who to connect to. Also copied as `permissioned-nodes.json` (controls who CAN connect).

5. **Runs `geth init`** — Initializes each node's database with the genesis block. After this, every node has identical block 0.

6. **Generates docker-compose.yml** — Creates the Docker Compose configuration with all 6 nodes, correct port mappings, startup delays (so validators start in order), and monitoring services.

7. **Starts the network** — Runs `docker compose up -d` and waits for all nodes to peer and start producing blocks.

### Deployment Parameters

```bash
# Default (same as what we've been using)
sudo bash deploy-network.sh --reset

# Custom: 4 validators, faster blocks
sudo bash deploy-network.sh --reset --validators 4 --block-period 2

# Custom: different chain ID and network name
sudo bash deploy-network.sh --reset --chain-id 9001 --network-name vittagems-staging

# Generate configs only, don't auto-start
sudo bash deploy-network.sh --reset --no-start

# All options
sudo bash deploy-network.sh --help
```

### Verify the Network

```bash
# Check all nodes are online and producing blocks
npm run network:status

# Expected output: all nodes at same block number, 5 peers each, 3 validators listed
```

### Stop / Start / Reset

```bash
# Stop the network (preserves chain data)
npm run network:stop

# Start the network (resumes from last block)
npm run network:start

# View live logs
npm run network:logs

# Full reset (destroys all chain data, fresh start)
sudo bash deploy-network.sh --reset
```

---

## 5. Smart Contracts

### Contract Files

| File | Purpose |
|---|---|
| `contracts/VittaGemsRBAC.sol` | Role-based access control. Defines 5 roles: TREASURY_ADMIN, COMPLIANCE_OPERATOR, SETTLEMENT_AGENT, AUDITOR, PARTNER. Inherits OpenZeppelin AccessControl. |
| `contracts/VittaGemsSettlement.sol` | Core settlement contract. Implements mint, transfer, burn, hold, freeze, release, reconcile. All functions are role-gated. Every action emits an on-chain event. |
| `contracts/VittaGemsNodePermissioning.sol` | On-chain node allowlist. GoQuorum calls `connectionAllowed()` at the P2P layer to decide whether to accept a peer connection. |
| `contracts/VittaGemsAccountPermissioning.sol` | On-chain account allowlist. GoQuorum calls `transactionAllowed()` before accepting any transaction. Accounts are typed (ADMIN, TREASURY, COMPLIANCE, etc). |

### Compile

```bash
npm run compile
```

This compiles all Solidity files and produces ABI + bytecode in `artifacts/`. If you get errors, check that `@openzeppelin/contracts` is installed (`npm install`).

### Deploy Settlement Contract

```bash
npm run deploy:local
```

**What this does:**

1. Connects to the local Quorum network via validator1's RPC port (8545)
2. Deploys the `VittaGemsSettlement` contract (which inherits `VittaGemsRBAC`)
3. The deployer address automatically gets `DEFAULT_ADMIN` and `TREASURY_ADMIN` roles
4. Saves deployment info (contract address, deployer, parameters) to `deployments/quorum_local-deployment.json`

**Deployment parameters (set in `scripts/deploy/deploy-settlement.js`):**

| Parameter | Value | Meaning |
|---|---|---|
| Reserve Limit | 10,000,000 | Maximum total value that can be minted (reserve coverage) |
| Per-Transaction Limit | 1,000,000 | Maximum single mint amount |
| Daily Limit | 5,000,000 | Maximum total minted per day |
| Multi-Sig Threshold | 500,000 | Mints above this need multi-sig (future feature) |

### Deploy Permissioning Contracts

```bash
npx hardhat run scripts/deploy/deploy-permissioning.js --network quorum_local
```

**What this does:**

1. Deploys `VittaGemsNodePermissioning` — then reads `config/static-nodes.json` and registers all 6 nodes on-chain
2. Deploys `VittaGemsAccountPermissioning` — registers the deployer as ADMIN
3. Saves deployment info to `deployments/permissioning-deployment.json`

After this, you have on-chain control over who can join the network and who can send transactions.

### Contract Function Reference

**Settlement Functions (VittaGemsSettlement.sol):**

| Function | Role Required | What It Does |
|---|---|---|
| `mintWithTreasuryApproval(amount, partner, refId, corridor)` | TREASURY_ADMIN | Creates settlement value for a partner. Checks: per-tx limit, daily limit, reserve coverage, no duplicate refId, partner not frozen. Emits `MintCompleted`. |
| `transfer(refId, to, amount)` | SETTLEMENT_AGENT | Moves settlement value from the minted partner to the destination partner. Both must be approved and not frozen. Emits `TransferSettled`. |
| `reconcile(refId)` | SETTLEMENT_AGENT | Marks a settlement as payout-confirmed (off-chain payout happened). Emits `SettlementReconciled`. |
| `burn(refId)` | SETTLEMENT_AGENT | Closes the settlement after payout confirmation. Deducts from partner balance, adds to totalBurned. Emits `BurnCompleted`. |
| `hold(refId, reason)` | COMPLIANCE_OPERATOR | Pauses a settlement for compliance review. Blocks transfers until released. Emits `HoldPlaced`. |
| `release(refId)` | COMPLIANCE_OPERATOR | Releases a held settlement back to MINTED status. Emits `HoldReleased`. |
| `freeze(account, reason)` | COMPLIANCE_OPERATOR | Freezes an account (e.g., sanctions hit). No mints or transfers involving this account. Emits `AccountFrozen`. |
| `unfreeze(account)` | COMPLIANCE_OPERATOR | Unfreezes an account. Emits `AccountUnfrozen`. |
| `registerPartner(address, name)` | TREASURY_ADMIN | Adds an approved counterparty. Only approved partners can receive mints/transfers. |
| `getSettlement(refId)` | Any | Returns settlement details (status, amount, partner, timestamps). |
| `getOutstandingBalance(partner)` | Any | Returns a partner's current balance. |
| `getNetCirculation()` | Any | Returns totalMinted - totalBurned. |

**Permissioning Functions:**

| Function | Role Required | What It Does |
|---|---|---|
| `addNode(enodeId, ip, port, name, orgId)` | NODE_ADMIN | Registers a node on the allowlist. GoQuorum checks this before accepting P2P connections. |
| `removeNode(enodeId)` | NODE_ADMIN | Removes a node. It will be disconnected at the next P2P check. |
| `connectionAllowed(enodeId, ip, port)` | Called by GoQuorum | Returns true/false. This is the enforcement function — GoQuorum calls it automatically. |
| `addAccount(address, type, name, orgId)` | ACCOUNT_ADMIN | Registers an account with a typed role (ADMIN, TREASURY, COMPLIANCE, etc). |
| `removeAccount(address)` | ACCOUNT_ADMIN | Removes an account. All its future transactions will be rejected. |
| `transactionAllowed(sender, target, value, ...)` | Called by GoQuorum | Returns true/false. GoQuorum calls this before every transaction. |

---

## 6. Testing Guide

### Test 1: Full Settlement Lifecycle

This tests the complete flow from minting to burning, including all compliance controls.

```bash
npx hardhat run scripts/test-lifecycle.js --network quorum_local
```

**What it tests (10 steps):**

- **Step 1:** Funds 5 role wallets (Compliance, Settlement Agent, Auditor, Partner 1, Partner 2)
- **Step 2:** Assigns RBAC roles and verifies each one
- **Step 3:** Registers 2 approved partners
- **Step 4:** Mints $50,000 settlement value for Partner 1, then verifies all controls:
  - Unauthorized mint attempt → rejected (AccessControl)
  - Duplicate reference ID → rejected
  - Exceeds per-transaction limit → rejected
  - Transfer to unapproved address → rejected
- **Step 5:** Transfers settlement value from Partner 1 to Partner 2
- **Step 6:** Reconciles (marks payout as confirmed off-chain)
- **Step 7:** Burns (closes the settlement, adjusts balances)
- **Step 8:** Tests hold/release workflow (compliance places hold → transfer blocked → hold released)
- **Step 9:** Tests freeze/unfreeze (account frozen → mint rejected → account unfrozen)
- **Step 10:** Queries all on-chain events for audit verification

**Expected output:** All 10 steps pass with "LIFECYCLE TEST COMPLETE — ALL STEPS PASSED"

**Note:** This script generates unique reference IDs using `Date.now()`, so it can be re-run multiple times without redeploying the contract.

### Test 2: Permissioning

This tests the on-chain node and account permissioning system.

```bash
npx hardhat run scripts/test-permissioning.js --network quorum_local
```

**What it tests (12 tests):**

- Tests 1-6: Node permissioning — add, verify, remove, reactivate, update IP, admin role enforcement
- Tests 7-8: Account permissioning — register typed accounts, verify transaction filtering
- Tests 9-10: Account lifecycle — remove, reactivate, change account type
- Tests 11-12: List active nodes/accounts, verify event audit trail

**Expected output:** "PERMISSIONING TEST COMPLETE — ALL PASSED"

### Test 3: Validator Failover

This tests IBFT consensus resilience by actually stopping and starting Docker containers.

```bash
bash scripts/test-validator-failover.sh
```

**What it tests (5 tests):**

- **Test 1:** Baseline — all 3 validators producing blocks (~1 block every 5 seconds)
- **Test 2:** Stops Validator 3 → network continues (2/3 validators = quorum met)
- **Test 3:** Stops Validator 2 → network halts (1/3 validators = no quorum)
- **Test 4:** Restarts both validators → network recovers automatically
- **Test 5:** Demonstrates IBFT `istanbul_propose` for adding/removing validators

**Expected output:** Tests 1-4 pass, Test 5 demonstrates the propose mechanism

**Important:** This test takes 2-3 minutes because it waits for block production between phases. The network is fully functional after the test — all validators are restarted.

### Running Hardhat Unit Tests

```bash
npm test
```

This runs the Hardhat test suite in `test/VittaGemsSettlement.test.js` against a local Hardhat network (not the Quorum network). Useful for rapid contract development without waiting for Quorum's 5-second block time.

---

## 7. Node Onboarding Runbook

This procedure is for adding a new node (validator or RPC) to a running VittaGems network.

### Adding a New RPC Node

**Step 1: Generate a nodekey on the new machine**

```bash
# Use the Quorum Docker image
docker run --rm --entrypoint="" \
  -v $(pwd)/new-node-data:/data \
  quorumengineering/quorum:latest \
  bootnode --genkey=/data/nodekey

# Extract the public key
docker run --rm --entrypoint="" \
  -v $(pwd)/new-node-data:/data \
  quorumengineering/quorum:latest \
  bootnode --nodekey=/data/nodekey --writeaddress
```

Save the public key output — this is the new node's enode ID.

**Step 2: Register the node on-chain (from an admin account)**

```javascript
// Using Hardhat console or a script
const nodePerm = await ethers.getContractAt("VittaGemsNodePermissioning", "<address>");
await nodePerm.addNode(
    "<128-char-enode-id>",
    "<ip-or-hostname>",
    30303,
    "rpc3",
    "VittaGems"
);
```

**Step 3: Add the enode URL to static-nodes.json on the new machine**

Copy the existing `config/static-nodes.json` from any running node and add the new node's entry.

**Step 4: Initialize and start the new node**

```bash
# Copy genesis.json from the network
# Initialize
docker run --rm --entrypoint="" \
  -v $(pwd)/new-node-data:/data \
  quorumengineering/quorum:latest \
  geth --datadir /data init /data/genesis.json

# Start (RPC node — no --mine flag)
docker run -d \
  -v $(pwd)/new-node-data:/data \
  -p 8555:8545 -p 30308:30303 \
  --name vittagems-rpc3 \
  quorumengineering/quorum:latest \
  --datadir /data --networkid 7001 --nodiscover \
  --syncmode full --miner.gasprice 0 \
  --http --http.addr 0.0.0.0 --http.port 8545 \
  --http.api admin,eth,debug,miner,net,txpool,personal,web3,istanbul \
  --port 30303 --allow-insecure-unlock
```

**Step 5: Verify**

```bash
# Check the node synced
curl -s -X POST http://localhost:8555 \
  --header "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | jq
```

The block number should match the other nodes.

### Adding a New Validator

Follow steps 1-4 above but with `--mine --miner.threads 1` added to the start command. Then:

**Step 5: Propose the new validator (requires majority vote)**

Each existing validator must vote to add the new address:

```bash
# From Validator 1
curl -X POST http://localhost:8545 \
  --header "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"istanbul_propose","params":["<new-validator-address>", true],"id":1}'

# From Validator 2
curl -X POST http://localhost:8547 \
  --header "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"istanbul_propose","params":["<new-validator-address>", true],"id":1}'

# Majority reached — new validator is now active
```

**Step 6: Verify**

```bash
curl -X POST http://localhost:8545 \
  --header "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"istanbul_getValidators","params":["latest"],"id":1}' | jq
```

The new address should appear in the validator list.

### Removing a Validator

Same process but with `false` instead of `true`:

```bash
curl -X POST http://localhost:8545 \
  --header "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"istanbul_propose","params":["<validator-address>", false],"id":1}'
```

---

## 8. Monitoring & Observability

### Grafana Dashboard

- **URL:** http://localhost:3000
- **Username:** admin
- **Password:** vittagems (or whatever you set via `--network-name`)

### Prometheus

- **URL:** http://localhost:9090

### Key Metrics to Monitor

| Metric | Query | What It Means |
|---|---|---|
| Block height | `chain_head_block` | Is the chain advancing? Alert if stalled > 30s |
| Peer count | `p2p_peers` | Are nodes connected? Alert if < 3 |
| Pending transactions | `txpool_pending` | Backlog building up? Alert if > 100 |
| Memory usage | `process_resident_memory_bytes` | Node memory consumption |
| CPU time | `process_cpu_seconds_total` | Node CPU load |

### Checking Node Health via CLI

```bash
# Quick status of all nodes
npm run network:status

# Detailed logs for a specific node
docker logs vittagems-validator1 --tail 100

# Check if a specific node is synced
curl -s -X POST http://localhost:8545 \
  --header "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | jq

# Check peer count
curl -s -X POST http://localhost:8545 \
  --header "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' | jq

# List current IBFT validators
curl -s -X POST http://localhost:8545 \
  --header "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"istanbul_getValidators","params":["latest"],"id":1}' | jq
```

---

## 9. Operational Procedures

### Full Network Reset

Destroys all chain data and starts fresh. Use when you need a clean state.

```bash
# Stop everything
docker stop $(docker ps -q) 2>/dev/null
docker rm $(docker ps -aq) 2>/dev/null
docker network prune -f

# Reset and redeploy
sudo bash deploy-network.sh --reset

# Redeploy contracts (chain data is gone, so contracts need redeployment)
npm run deploy:local
npx hardhat run scripts/deploy/deploy-permissioning.js --network quorum_local
```

### Backup Chain Data

```bash
# Stop the network first
npm run network:stop

# Tar the chain data
tar -czf vittagems-backup-$(date +%Y%m%d).tar.gz network/*/data/geth

# Restart
npm run network:start
```

### Restore from Backup

```bash
npm run network:stop

# Extract backup
tar -xzf vittagems-backup-20260615.tar.gz

npm run network:start
```

### View Contract Deployment Info

```bash
# Settlement contract
cat deployments/quorum_local-deployment.json | jq

# Permissioning contracts
cat deployments/permissioning-deployment.json | jq
```

### Interact with Contracts via Hardhat Console

```bash
npx hardhat console --network quorum_local
```

```javascript
// Inside the console:
const settlement = await ethers.getContractAt(
  "VittaGemsSettlement",
  "<contract-address-from-deployment.json>"
);

// Check total minted
const total = await settlement.totalMinted();
console.log(ethers.formatEther(total));

// Check a partner's balance
const balance = await settlement.getOutstandingBalance("<partner-address>");
console.log(ethers.formatEther(balance));

// Check a settlement's status
const s = await settlement.getSettlement("VG-2026-0611-001");
console.log(s);
```

---

## 10. Port Reference

### Default Port Map

| Node | RPC (HTTP) | WebSocket | P2P | Metrics |
|---|---|---|---|---|
| Validator 1 | 8545 | 8546 | 30303 | 9545 |
| Validator 2 | 8547 | 8548 | 30304 | 9546 |
| Validator 3 | 8549 | 8550 | 30305 | 9547 |
| RPC 1 | 8551 | 8552 | 30306 | 9548 |
| RPC 2 | 8553 | 8554 | 30307 | 9549 |
| Prometheus | 9090 | - | - | - |
| Grafana | 3000 | - | - | - |

### Hardhat Network Aliases

Defined in `hardhat.config.js`:

| Alias | Points To | Use For |
|---|---|---|
| `quorum_local` | localhost:8545 (validator1) | Default deployment target |
| `quorum_validator1` | localhost:8545 | Direct validator access |
| `quorum_rpc1` | localhost:8551 | API endpoint access |
| `quorum_rpc2` | localhost:8553 | API endpoint failover |

---

## 11. Troubleshooting

### "block not found" error during deployment

**Cause:** Hardhat is sending EIP-1559 transactions, which GoQuorum doesn't support.

**Fix:** Ensure `hardhat.config.js` has `hardfork: "istanbul"` and `gas: 8000000` in the network config. The `deploy-network.sh` script sets this automatically.

### Nodes at Block #0 with 0 Peers

**Cause:** `static-nodes.json` has incorrect enode URLs, or the file isn't in the right location.

**Fix:** Verify `static-nodes.json` exists in both `network/<node>/data/` AND `network/<node>/data/geth/`. Run `deploy-network.sh --reset` to regenerate everything.

### "Address already in use" when starting Docker

**Cause:** Docker containers from a previous run are still holding ports, or the Docker network subnet conflicts with existing networks.

**Fix:**
```bash
docker stop $(docker ps -q) 2>/dev/null
docker rm $(docker ps -aq) 2>/dev/null
docker network prune -f
# Then retry
```

### "execution reverted" on contract calls

**Cause:** Usually a role/permission issue or invalid state transition.

**Debug:**
```bash
# Check the deployer address matches what's in hardhat.config.js
cat config/network-info.json | jq '.deployerKey'

# Check deployment info
cat deployments/quorum_local-deployment.json | jq '.deployer'
```

### Prometheus not starting (YAML parse error)

**Cause:** The generated `prometheus.yml` has indentation issues.

**Fix:** Replace the file manually:
```bash
cat > monitoring/prometheus/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'vittagems-validators'
    static_configs:
      - targets:
          - 'validator1:9545'
          - 'validator2:9545'
          - 'validator3:9545'
        labels:
          role: 'validator'

  - job_name: 'vittagems-rpc'
    static_configs:
      - targets:
          - 'rpc1:9545'
          - 'rpc2:9545'
        labels:
          role: 'rpc'

  - job_name: 'vittagems-bootnode'
    static_configs:
      - targets:
          - 'bootnode:9545'
        labels:
          role: 'bootnode'
EOF

docker restart vittagems-prometheus
```

---

## 12. AWS Deployment (Week 3)

### Minimum Spec (Dev/Testing)

For initial testing with low transaction volume, everything runs on a single instance:

| Config | Value |
|---|---|
| Instance | t3.large (2 vCPU, 8 GB RAM) |
| Storage | 100 GB gp3 EBS |
| OS | Ubuntu 22.04 LTS |
| Elastic IP | Yes (fixed endpoint) |

**Security Group:**
- TCP 22 from office/VPN IP (SSH)
- TCP 8545 from application servers (JSON-RPC API)
- TCP 3000 from office/VPN IP (Grafana)

**Deployment is identical to local:**
```bash
ssh ubuntu@<elastic-ip>
# Install prerequisites (same env setup script)
# Clone repo, npm install
# Run deploy-network.sh --reset
```

### Production Spec (Multi-Instance)

For production with fault tolerance across availability zones, see the full AWS architecture spec in the project documentation. Key difference: each validator runs on its own EC2 instance in a private subnet, RPC nodes sit behind an Application Load Balancer with TLS, and node keys are stored in AWS Secrets Manager.

---

## Project Directory Structure

```
vittagems-blockchain/
├── contracts/                          # Solidity smart contracts
│   ├── VittaGemsSettlement.sol         # Core settlement (mint, transfer, burn, hold, freeze)
│   ├── VittaGemsRBAC.sol               # Role-based access control
│   ├── VittaGemsNodePermissioning.sol  # On-chain node allowlist
│   └── VittaGemsAccountPermissioning.sol # On-chain account allowlist
├── scripts/
│   ├── deploy/
│   │   ├── deploy-settlement.js        # Deploy settlement contract
│   │   └── deploy-permissioning.js     # Deploy permissioning contracts
│   ├── test-lifecycle.js               # Full settlement lifecycle test
│   ├── test-permissioning.js           # Permissioning integration test
│   ├── test-validator-failover.sh      # IBFT consensus resilience test
│   └── utils/
│       ├── network-status.sh           # Check all node statuses
│       ├── reset-network.sh            # Clean chain data
│       └── test-transaction.js         # Quick zero-gas transaction test
├── config/
│   ├── genesis.json                    # Genesis block (generated by deploy script)
│   ├── static-nodes.json              # Peer list (generated by deploy script)
│   ├── permissioned-nodes.json        # Node allowlist (generated by deploy script)
│   └── network-info.json              # Validator addresses, keys, RPC ports
├── docker/
│   └── docker-compose.yml             # Docker orchestration (generated by deploy script)
├── network/
│   ├── validator1/data/               # Validator 1 chain data + nodekey
│   ├── validator2/data/               # Validator 2 chain data + nodekey
│   ├── validator3/data/               # Validator 3 chain data + nodekey
│   ├── rpc1/data/                     # RPC 1 chain data + nodekey
│   ├── rpc2/data/                     # RPC 2 chain data + nodekey
│   └── bootnode/data/                 # Bootnode chain data + nodekey
├── monitoring/
│   ├── prometheus/prometheus.yml      # Prometheus scrape config
│   └── grafana/                       # Grafana provisioning + dashboards
├── deployments/
│   ├── quorum_local-deployment.json   # Settlement contract address + info
│   └── permissioning-deployment.json  # Permissioning contract addresses
├── test/
│   └── VittaGemsSettlement.test.js    # Hardhat unit tests
├── docs/
│   └── ARCHITECTURE.md                # Architecture document
├── deploy-network.sh                  # Parameterized network deployment
├── hardhat.config.js                  # Hardhat configuration (auto-updated by deploy script)
├── package.json                       # Node.js dependencies + npm scripts
└── .env                               # Environment variables
```