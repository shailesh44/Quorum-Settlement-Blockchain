#!/bin/bash

# ============================================================
# VittaGems — Network Initialization (Fixed)
# ============================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

print_step()  { echo -e "\n${GREEN}━━━ [STEP] $1 ━━━${NC}"; }
print_info()  { echo -e "  ${CYAN}→${NC} $1"; }
print_done()  { echo -e "  ${GREEN}✓${NC} $1"; }
print_error() { echo -e "  ${RED}✗${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NETWORK_DIR="${PROJECT_DIR}/network"
CONFIG_DIR="${PROJECT_DIR}/config"
DOCKER_DIR="${PROJECT_DIR}/docker"

QUORUM_IMAGE="quorumengineering/quorum:latest"
NODES=("validator1" "validator2" "validator3" "rpc1" "rpc2" "bootnode")
VALIDATORS=("validator1" "validator2" "validator3")

echo "============================================================"
echo "  VittaGems — Network Initialization"
echo "============================================================"

# --------------------------------------------------
# 0. Pre-flight
# --------------------------------------------------
print_step "Pre-flight checks"

if ! command -v docker &>/dev/null; then
    print_error "Docker not found."
    exit 1
fi

if ! docker info &>/dev/null 2>&1; then
    print_error "Docker daemon not running or no permissions."
    exit 1
fi

print_info "Ensuring Quorum Docker image is available..."
docker pull "$QUORUM_IMAGE" 2>/dev/null || true

# Verify the image entrypoint so we know what we're dealing with
print_info "Checking image entrypoint..."
ENTRYPOINT=$(docker inspect --format='{{json .Config.Entrypoint}}' "$QUORUM_IMAGE" 2>/dev/null)
echo "  Image entrypoint: $ENTRYPOINT"

# Test that --entrypoint="" works
docker run --rm --entrypoint="" "$QUORUM_IMAGE" sh -c "echo 'Shell access works'" 2>/dev/null
print_done "Docker ready, shell override confirmed"

# --------------------------------------------------
# 1. Stop any existing network
# --------------------------------------------------
print_step "Stopping any existing network"
cd "${DOCKER_DIR}" && docker compose down -v 2>/dev/null || true
print_done "Clean state"

# --------------------------------------------------
# 2. Clean old data
# --------------------------------------------------
print_step "Cleaning old chain data and keys"

for node in "${NODES[@]}"; do
    rm -rf "${NETWORK_DIR}/${node}/data/geth"
    rm -rf "${NETWORK_DIR}/${node}/data/keystore"
    rm -rf "${NETWORK_DIR}/${node}/data/nodekey"
    rm -rf "${NETWORK_DIR}/${node}/data/static-nodes.json"
    rm -rf "${NETWORK_DIR}/${node}/data/permissioned-nodes.json"
    rm -rf "${NETWORK_DIR}/${node}/data/genesis.json"
    rm -rf "${NETWORK_DIR}/${node}/logs/"*
    mkdir -p "${NETWORK_DIR}/${node}/data"
    mkdir -p "${NETWORK_DIR}/${node}/logs"
done

print_done "Old data cleaned"

# --------------------------------------------------
# 3. Generate real node keys
# --------------------------------------------------
print_step "Generating real node keys"

declare -A NODE_PUBKEYS

for node in "${NODES[@]}"; do
    print_info "Generating key for ${node}..."

    # Generate nodekey using bootnode inside the container
    # CRITICAL: --entrypoint="" overrides the default geth entrypoint
    docker run --rm \
        --entrypoint="" \
        -v "${NETWORK_DIR}/${node}/data:/data" \
        "$QUORUM_IMAGE" \
        bootnode --genkey=/data/nodekey

    # Verify key was created
    if [ ! -f "${NETWORK_DIR}/${node}/data/nodekey" ]; then
        print_error "Failed to generate nodekey for ${node}"
        exit 1
    fi

    # Extract public key from nodekey
    PUBKEY=$(docker run --rm \
        --entrypoint="" \
        -v "${NETWORK_DIR}/${node}/data:/data" \
        "$QUORUM_IMAGE" \
        bootnode --nodekey=/data/nodekey --writeaddress 2>/dev/null)

    # Clean whitespace
    PUBKEY=$(echo "$PUBKEY" | tr -d '[:space:]')

    if [ -z "$PUBKEY" ] || [ ${#PUBKEY} -ne 128 ]; then
        print_error "Invalid pubkey for ${node} (length: ${#PUBKEY})"
        exit 1
    fi

    NODE_PUBKEYS[$node]="$PUBKEY"
    print_done "${node}: ${PUBKEY:0:16}...${PUBKEY: -16}"
done

# --------------------------------------------------
# 4. Derive validator addresses from node keys
# --------------------------------------------------
print_step "Deriving validator addresses"

declare -A NODE_ADDRESSES

for val in "${VALIDATORS[@]}"; do
    # Import the nodekey as an account to get the address
    ADDRESS=$(docker run --rm \
        --entrypoint="" \
        -v "${NETWORK_DIR}/${val}/data:/data" \
        "$QUORUM_IMAGE" \
        sh -c "echo '' > /tmp/pass.txt && geth account import --datadir /tmp/addr --password /tmp/pass.txt /data/nodekey 2>&1" \
        | grep -oP '0x[a-fA-F0-9]{40}' | head -1)

    if [ -z "$ADDRESS" ]; then
        print_error "Failed to derive address for ${val}"
        # Try alternate parsing
        print_info "Trying alternate method..."
        IMPORT_OUTPUT=$(docker run --rm \
            --entrypoint="" \
            -v "${NETWORK_DIR}/${val}/data:/data" \
            "$QUORUM_IMAGE" \
            sh -c "echo '' > /tmp/pass.txt && geth account import --datadir /tmp/addr --password /tmp/pass.txt /data/nodekey 2>&1")
        echo "  Import output: $IMPORT_OUTPUT"

        ADDRESS=$(echo "$IMPORT_OUTPUT" | grep -oiP '[a-fA-F0-9]{40}' | head -1)
        if [ -n "$ADDRESS" ]; then
            ADDRESS="0x${ADDRESS}"
        else
            print_error "Cannot derive address for ${val}. Exiting."
            exit 1
        fi
    fi

    NODE_ADDRESSES[$val]="$ADDRESS"
    print_done "${val}: ${ADDRESS}"
done

# --------------------------------------------------
# 5. Generate IBFT genesis with proper extraData
# --------------------------------------------------
print_step "Generating IBFT genesis file"

ADDR1="${NODE_ADDRESSES[validator1]#0x}"
ADDR2="${NODE_ADDRESSES[validator2]#0x}"
ADDR3="${NODE_ADDRESSES[validator3]#0x}"

# Build extraData using Python RLP encoding
EXTRA_DATA=$(python3 << PYEOF
def encode_length(length, offset):
    if length < 56:
        return bytes([length + offset])
    else:
        bl = length.to_bytes((length.bit_length() + 7) // 8, 'big')
        return bytes([len(bl) + offset + 55]) + bl

def encode_string(s):
    if len(s) == 0:
        return bytes([0x80])
    if len(s) == 1 and s[0] < 0x80:
        return s
    return encode_length(len(s), 0x80) + s

def encode_list(items):
    output = b''
    for item in items:
        output += item
    return encode_length(len(output), 0xc0) + output

# 32 bytes vanity
vanity = b'\x00' * 32

# Validator addresses (sorted, lowercase)
addrs = sorted([
    "${ADDR1}".lower(),
    "${ADDR2}".lower(),
    "${ADDR3}".lower(),
])
validators = [bytes.fromhex(a) for a in addrs]

encoded_validators = encode_list([encode_string(v) for v in validators])
seal = encode_string(b'\x00' * 65)
committed_seals = encode_list([])

istanbul_extra = encode_list([encoded_validators, seal, committed_seals])
extra_data = vanity + istanbul_extra

print("0x" + extra_data.hex())
PYEOF
)

if [ -z "$EXTRA_DATA" ] || [ ${#EXTRA_DATA} -lt 70 ]; then
    print_error "Failed to generate extraData"
    exit 1
fi

print_info "ExtraData: ${EXTRA_DATA:0:40}...${EXTRA_DATA: -20}"

# Lowercase addresses for alloc (without 0x prefix)
ADDR1_LOWER=$(echo "$ADDR1" | tr '[:upper:]' '[:lower:]')
ADDR2_LOWER=$(echo "$ADDR2" | tr '[:upper:]' '[:lower:]')
ADDR3_LOWER=$(echo "$ADDR3" | tr '[:upper:]' '[:lower:]')

cat > "${CONFIG_DIR}/genesis.json" << GENESIS
{
  "nonce": "0x0",
  "timestamp": "0x0",
  "extraData": "${EXTRA_DATA}",
  "gasLimit": "0xFFFFFFFF",
  "difficulty": "0x1",
  "mixHash": "0x63746963616c2062797a616e74696e65206661756c7420746f6c6572616e6365",
  "coinbase": "0x0000000000000000000000000000000000000000",
  "alloc": {
    "${ADDR1_LOWER}": {
      "balance": "1000000000000000000000000000"
    },
    "${ADDR2_LOWER}": {
      "balance": "1000000000000000000000000000"
    },
    "${ADDR3_LOWER}": {
      "balance": "1000000000000000000000000000"
    }
  },
  "config": {
    "chainId": 7001,
    "homesteadBlock": 0,
    "eip150Block": 0,
    "eip150Hash": "0x0000000000000000000000000000000000000000000000000000000000000000",
    "eip155Block": 0,
    "eip158Block": 0,
    "byzantiumBlock": 0,
    "constantinopleBlock": 0,
    "petersburgBlock": 0,
    "istanbulBlock": 0,
    "istanbul": {
      "epoch": 30000,
      "policy": 0,
      "ceil2Nby3Block": 0
    },
    "txnSizeLimit": 64,
    "maxCodeSize": 0,
    "isQuorum": true
  }
}
GENESIS

print_done "Genesis created with validators: ${NODE_ADDRESSES[validator1]}, ${NODE_ADDRESSES[validator2]}, ${NODE_ADDRESSES[validator3]}"

# --------------------------------------------------
# 6. Create static-nodes.json
# --------------------------------------------------
print_step "Creating static-nodes.json"

cat > "${CONFIG_DIR}/static-nodes.json" << STATICNODES
[
  "enode://${NODE_PUBKEYS[validator1]}@validator1:30303?discport=0",
  "enode://${NODE_PUBKEYS[validator2]}@validator2:30303?discport=0",
  "enode://${NODE_PUBKEYS[validator3]}@validator3:30303?discport=0",
  "enode://${NODE_PUBKEYS[rpc1]}@rpc1:30303?discport=0",
  "enode://${NODE_PUBKEYS[rpc2]}@rpc2:30303?discport=0",
  "enode://${NODE_PUBKEYS[bootnode]}@bootnode:30303?discport=0"
]
STATICNODES

cp "${CONFIG_DIR}/static-nodes.json" "${CONFIG_DIR}/permissioned-nodes.json"
print_done "static-nodes.json created"

# Print for verification
echo ""
cat "${CONFIG_DIR}/static-nodes.json"
echo ""

# --------------------------------------------------
# 7. Distribute configs and initialize each node
# --------------------------------------------------
print_step "Initializing all nodes"

for node in "${NODES[@]}"; do
    print_info "Initializing ${node}..."

    # Copy configs to node data dir
    cp "${CONFIG_DIR}/genesis.json"           "${NETWORK_DIR}/${node}/data/"
    cp "${CONFIG_DIR}/static-nodes.json"      "${NETWORK_DIR}/${node}/data/"
    cp "${CONFIG_DIR}/permissioned-nodes.json" "${NETWORK_DIR}/${node}/data/"

    # Run geth init
    docker run --rm \
        --entrypoint="" \
        -v "${NETWORK_DIR}/${node}/data:/data" \
        "$QUORUM_IMAGE" \
        geth --datadir /data init /data/genesis.json

    # CRITICAL: Copy static-nodes.json into geth/ subdir
    # (geth reads from <datadir>/geth/static-nodes.json after initialization)
    if [ -d "${NETWORK_DIR}/${node}/data/geth" ]; then
        cp "${CONFIG_DIR}/static-nodes.json"      "${NETWORK_DIR}/${node}/data/geth/"
        cp "${CONFIG_DIR}/permissioned-nodes.json" "${NETWORK_DIR}/${node}/data/geth/"
    fi

    print_done "${node} initialized"
done

# --------------------------------------------------
# 8. Write docker-compose.yml
# --------------------------------------------------
print_step "Writing docker-compose.yml"

cat > "${DOCKER_DIR}/docker-compose.yml" << 'DOCKERCOMPOSE'
x-quorum-defaults: &quorum-defaults
  image: quorumengineering/quorum:latest
  restart: unless-stopped

x-quorum-env: &quorum-env
  PRIVATE_CONFIG: ignore

networks:
  vittagems-net:
    driver: bridge
    ipam:
      config:
        - subnet: 172.16.239.0/24

volumes:
  prometheus-data:
  grafana-data:

services:

  validator1:
    <<: *quorum-defaults
    container_name: vittagems-validator1
    hostname: validator1
    ports:
      - "8545:8545"
      - "8546:8546"
      - "30303:30303"
      - "9545:9545"
    volumes:
      - ../network/validator1/data:/data
      - ../network/validator1/logs:/logs
    networks:
      vittagems-net:
        ipv4_address: 172.16.239.11
    entrypoint:
      - /bin/sh
      - -c
      - |
        geth \
          --datadir /data \
          --networkid 7001 \
          --nodiscover \
          --verbosity 4 \
          --syncmode full \
          --istanbul.blockperiod 5 \
          --mine \
          --miner.threads 1 \
          --miner.gasprice 0 \
          --emitcheckpoints \
          --http \
          --http.addr 0.0.0.0 \
          --http.port 8545 \
          --http.corsdomain "*" \
          --http.vhosts "*" \
          --http.api admin,eth,debug,miner,net,txpool,personal,web3,istanbul \
          --ws \
          --ws.addr 0.0.0.0 \
          --ws.port 8546 \
          --ws.origins "*" \
          --ws.api admin,eth,debug,miner,net,txpool,personal,web3,istanbul \
          --port 30303 \
          --allow-insecure-unlock \
          --metrics \
          --metrics.addr 0.0.0.0 \
          --metrics.port 9545 \
        2>&1 | tee /logs/validator1.log
    environment:
      <<: *quorum-env

  validator2:
    <<: *quorum-defaults
    container_name: vittagems-validator2
    hostname: validator2
    ports:
      - "8547:8545"
      - "8548:8546"
      - "30304:30303"
      - "9546:9545"
    volumes:
      - ../network/validator2/data:/data
      - ../network/validator2/logs:/logs
    networks:
      vittagems-net:
        ipv4_address: 172.16.239.12
    depends_on:
      - validator1
    entrypoint:
      - /bin/sh
      - -c
      - |
        sleep 3
        geth \
          --datadir /data \
          --networkid 7001 \
          --nodiscover \
          --verbosity 4 \
          --syncmode full \
          --istanbul.blockperiod 5 \
          --mine \
          --miner.threads 1 \
          --miner.gasprice 0 \
          --emitcheckpoints \
          --http \
          --http.addr 0.0.0.0 \
          --http.port 8545 \
          --http.corsdomain "*" \
          --http.vhosts "*" \
          --http.api admin,eth,debug,miner,net,txpool,personal,web3,istanbul \
          --ws \
          --ws.addr 0.0.0.0 \
          --ws.port 8546 \
          --ws.origins "*" \
          --ws.api admin,eth,debug,miner,net,txpool,personal,web3,istanbul \
          --port 30303 \
          --allow-insecure-unlock \
          --metrics \
          --metrics.addr 0.0.0.0 \
          --metrics.port 9545 \
        2>&1 | tee /logs/validator2.log
    environment:
      <<: *quorum-env

  validator3:
    <<: *quorum-defaults
    container_name: vittagems-validator3
    hostname: validator3
    ports:
      - "8549:8545"
      - "8550:8546"
      - "30305:30303"
      - "9547:9545"
    volumes:
      - ../network/validator3/data:/data
      - ../network/validator3/logs:/logs
    networks:
      vittagems-net:
        ipv4_address: 172.16.239.13
    depends_on:
      - validator1
    entrypoint:
      - /bin/sh
      - -c
      - |
        sleep 5
        geth \
          --datadir /data \
          --networkid 7001 \
          --nodiscover \
          --verbosity 4 \
          --syncmode full \
          --istanbul.blockperiod 5 \
          --mine \
          --miner.threads 1 \
          --miner.gasprice 0 \
          --emitcheckpoints \
          --http \
          --http.addr 0.0.0.0 \
          --http.port 8545 \
          --http.corsdomain "*" \
          --http.vhosts "*" \
          --http.api admin,eth,debug,miner,net,txpool,personal,web3,istanbul \
          --ws \
          --ws.addr 0.0.0.0 \
          --ws.port 8546 \
          --ws.origins "*" \
          --ws.api admin,eth,debug,miner,net,txpool,personal,web3,istanbul \
          --port 30303 \
          --allow-insecure-unlock \
          --metrics \
          --metrics.addr 0.0.0.0 \
          --metrics.port 9545 \
        2>&1 | tee /logs/validator3.log
    environment:
      <<: *quorum-env

  rpc1:
    <<: *quorum-defaults
    container_name: vittagems-rpc1
    hostname: rpc1
    ports:
      - "8551:8545"
      - "8552:8546"
      - "30306:30303"
      - "9548:9545"
    volumes:
      - ../network/rpc1/data:/data
      - ../network/rpc1/logs:/logs
    networks:
      vittagems-net:
        ipv4_address: 172.16.239.14
    depends_on:
      - validator1
      - validator2
      - validator3
    entrypoint:
      - /bin/sh
      - -c
      - |
        sleep 10
        geth \
          --datadir /data \
          --networkid 7001 \
          --nodiscover \
          --verbosity 3 \
          --syncmode full \
          --miner.gasprice 0 \
          --http \
          --http.addr 0.0.0.0 \
          --http.port 8545 \
          --http.corsdomain "*" \
          --http.vhosts "*" \
          --http.api admin,eth,debug,miner,net,txpool,personal,web3,istanbul \
          --ws \
          --ws.addr 0.0.0.0 \
          --ws.port 8546 \
          --ws.origins "*" \
          --ws.api admin,eth,debug,miner,net,txpool,personal,web3,istanbul \
          --port 30303 \
          --allow-insecure-unlock \
          --metrics \
          --metrics.addr 0.0.0.0 \
          --metrics.port 9545 \
        2>&1 | tee /logs/rpc1.log
    environment:
      <<: *quorum-env

  rpc2:
    <<: *quorum-defaults
    container_name: vittagems-rpc2
    hostname: rpc2
    ports:
      - "8553:8545"
      - "8554:8546"
      - "30307:30303"
      - "9549:9545"
    volumes:
      - ../network/rpc2/data:/data
      - ../network/rpc2/logs:/logs
    networks:
      vittagems-net:
        ipv4_address: 172.16.239.15
    depends_on:
      - validator1
      - validator2
      - validator3
    entrypoint:
      - /bin/sh
      - -c
      - |
        sleep 12
        geth \
          --datadir /data \
          --networkid 7001 \
          --nodiscover \
          --verbosity 3 \
          --syncmode full \
          --miner.gasprice 0 \
          --http \
          --http.addr 0.0.0.0 \
          --http.port 8545 \
          --http.corsdomain "*" \
          --http.vhosts "*" \
          --http.api admin,eth,debug,miner,net,txpool,personal,web3,istanbul \
          --ws \
          --ws.addr 0.0.0.0 \
          --ws.port 8546 \
          --ws.origins "*" \
          --ws.api admin,eth,debug,miner,net,txpool,personal,web3,istanbul \
          --port 30303 \
          --allow-insecure-unlock \
          --metrics \
          --metrics.addr 0.0.0.0 \
          --metrics.port 9545 \
        2>&1 | tee /logs/rpc2.log
    environment:
      <<: *quorum-env

  bootnode:
    <<: *quorum-defaults
    container_name: vittagems-bootnode
    hostname: bootnode
    ports:
      - "30301:30303"
    volumes:
      - ../network/bootnode/data:/data
      - ../network/bootnode/logs:/logs
    networks:
      vittagems-net:
        ipv4_address: 172.16.239.10
    entrypoint:
      - /bin/sh
      - -c
      - |
        geth \
          --datadir /data \
          --networkid 7001 \
          --nodiscover \
          --verbosity 3 \
          --syncmode full \
          --miner.gasprice 0 \
          --http \
          --http.addr 0.0.0.0 \
          --http.port 8545 \
          --http.corsdomain "*" \
          --http.vhosts "*" \
          --http.api admin,eth,debug,miner,net,txpool,personal,web3,istanbul \
          --port 30303 \
          --allow-insecure-unlock \
        2>&1 | tee /logs/bootnode.log
    environment:
      <<: *quorum-env

  prometheus:
    image: prom/prometheus:latest
    container_name: vittagems-prometheus
    restart: unless-stopped
    ports:
      - "9090:9090"
    volumes:
      - ../monitoring/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus-data:/prometheus
    networks:
      vittagems-net:
        ipv4_address: 172.16.239.20

  grafana:
    image: grafana/grafana:latest
    container_name: vittagems-grafana
    restart: unless-stopped
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=vittagems
      - GF_USERS_ALLOW_SIGN_UP=false
    volumes:
      - grafana-data:/var/lib/grafana
      - ../monitoring/grafana/provisioning:/etc/grafana/provisioning
      - ../monitoring/grafana/dashboards:/var/lib/grafana/dashboards
    depends_on:
      - prometheus
    networks:
      vittagems-net:
        ipv4_address: 172.16.239.21
DOCKERCOMPOSE

print_done "docker-compose.yml written"

# --------------------------------------------------
# 9. Save deployer key info and update hardhat config
# --------------------------------------------------
print_step "Updating Hardhat config with real keys"

VAL1_NODEKEY=$(cat "${NETWORK_DIR}/validator1/data/nodekey")

cat > "${CONFIG_DIR}/network-info.json" << NETINFO
{
  "_WARNING": "DEVELOPMENT KEYS ONLY",
  "chainId": 7001,
  "validators": {
    "validator1": { "address": "${NODE_ADDRESSES[validator1]}", "rpc": "http://localhost:8545" },
    "validator2": { "address": "${NODE_ADDRESSES[validator2]}", "rpc": "http://localhost:8547" },
    "validator3": { "address": "${NODE_ADDRESSES[validator3]}", "rpc": "http://localhost:8549" }
  },
  "rpcNodes": {
    "rpc1": "http://localhost:8551",
    "rpc2": "http://localhost:8553"
  },
  "deployerKey": "0x${VAL1_NODEKEY}"
}
NETINFO

cat > "${PROJECT_DIR}/hardhat.config.js" << HARDHAT
require("@nomicfoundation/hardhat-toolbox");

module.exports = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: { enabled: true, runs: 200 },
      evmVersion: "istanbul"
    },
  },
  networks: {
    quorum_local: {
      url: "http://localhost:8545",
      chainId: 7001,
      gasPrice: 0,
      gas: 8000000,
      hardfork: "istanbul",
      accounts: ["0x${VAL1_NODEKEY}"],
    },
    quorum_rpc1: {
      url: "http://localhost:8551",
      chainId: 7001,
      gasPrice: 0,
      gas: 8000000,
      hardfork: "istanbul",
      accounts: ["0x${VAL1_NODEKEY}"],
    },
    quorum_rpc2: {
      url: "http://localhost:8553",
      chainId: 7001,
      gasPrice: 0,
      gas: 8000000,
      hardfork: "istanbul",
      accounts: ["0x${VAL1_NODEKEY}"],
    },
  },
};
HARDHAT

# Update test transaction script
cat > "${PROJECT_DIR}/scripts/utils/test-transaction.js" << TESTSCRIPT
const { ethers } = require("ethers");

async function main() {
  console.log("============================================================");
  console.log("  VittaGems — Quick Transaction Test");
  console.log("============================================================\\n");

  const provider = new ethers.JsonRpcProvider("http://localhost:8545");

  const network = await provider.getNetwork();
  console.log("  Chain ID:", network.chainId.toString());

  const blockNum = await provider.getBlockNumber();
  console.log("  Current block:", blockNum);

  if (blockNum === 0) {
    console.log("\\n  ⚠ Network is at block 0 — validators may not be producing blocks yet.");
    console.log("  Check: docker logs vittagems-validator1 --tail 50");
    return;
  }

  const wallet = new ethers.Wallet("0x${VAL1_NODEKEY}", provider);
  console.log("  Sender:", wallet.address);

  const balance = await provider.getBalance(wallet.address);
  console.log("  Balance:", ethers.formatEther(balance), "ETH");

  const testAddr = "${NODE_ADDRESSES[validator2]}";
  console.log("\\n  Sending 1 ETH (zero gas) to", testAddr, "...");

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
  console.log("\\n  ✓ Zero-gas transaction successful!");
  console.log("============================================================");
}

main().catch((err) => {
  console.error("\\n  ✗ Error:", err.message);
  console.error("  → Check: npm run network:status");
});
TESTSCRIPT

print_done "Hardhat config and scripts updated"

# --------------------------------------------------
# 10. Start the network
# --------------------------------------------------
print_step "Starting VittaGems network"

cd "${DOCKER_DIR}"
docker compose up -d

echo ""
print_info "Waiting 25 seconds for nodes to start and peer..."
for i in $(seq 25 -1 1); do
    printf "\r  Countdown: %2d seconds remaining..." "$i"
    sleep 1
done
echo ""

# --------------------------------------------------
# 11. Verify
# --------------------------------------------------
print_step "Verifying network status"
echo ""
bash "${PROJECT_DIR}/scripts/utils/network-status.sh"

echo ""
print_step "Checking validator logs for errors"
echo ""
echo "  --- Validator 1 (last 5 lines) ---"
docker logs vittagems-validator1 --tail 5 2>&1 | head -5
echo ""
echo "  --- Validator 2 (last 5 lines) ---"
docker logs vittagems-validator2 --tail 5 2>&1 | head -5
echo ""

echo "============================================================"
echo "  Initialization Complete!"
echo "============================================================"
echo ""
echo "  Validator addresses:"
echo "    V1: ${NODE_ADDRESSES[validator1]}"
echo "    V2: ${NODE_ADDRESSES[validator2]}"
echo "    V3: ${NODE_ADDRESSES[validator3]}"
echo ""
echo "  Deployer key (validator1 nodekey): 0x${VAL1_NODEKEY}"
echo ""
echo "  If blocks > 0 and peers > 0, you're ready:"
echo ""
echo "    cd ${PROJECT_DIR}"
echo "    node scripts/utils/test-transaction.js"
echo "    npm run compile"
echo "    npm run deploy:local"
echo ""
echo "  If still at block 0, debug with:"
echo ""
echo "    docker logs vittagems-validator1 --tail 100"
echo "    docker logs vittagems-validator2 --tail 100"
echo "    docker logs vittagems-validator3 --tail 100"
echo ""
echo "============================================================"