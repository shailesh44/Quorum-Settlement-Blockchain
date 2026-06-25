#!/bin/bash

# ============================================================
# VittaGems — Proper Network Initialization
# ============================================================
# This script:
#   1. Generates REAL node keys using geth inside Docker
#   2. Derives correct enode public keys and addresses
#   3. Builds proper IBFT genesis with encoded validator set
#   4. Creates valid static-nodes.json
#   5. Initializes all nodes with the genesis
#   6. Starts the network
# ============================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

print_step()  { echo -e "\n${GREEN}━━━ [STEP] $1 ━━━${NC}"; }
print_info()  { echo -e "  ${CYAN}→${NC} $1"; }
print_warn()  { echo -e "  ${YELLOW}⚠${NC} $1"; }
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
echo ""

# --------------------------------------------------
# 0. Pre-flight
# --------------------------------------------------
print_step "Pre-flight checks"

if ! command -v docker &>/dev/null; then
    print_error "Docker not found. Install Docker first."
    exit 1
fi

if ! docker info &>/dev/null 2>&1; then
    print_error "Docker daemon not running or no permissions. Try: sudo systemctl start docker"
    exit 1
fi

# Pull image if needed
print_info "Ensuring Quorum Docker image is available..."
docker pull "$QUORUM_IMAGE" 2>/dev/null || true
print_done "Docker ready"

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
# 3. Generate real node keys for every node
# --------------------------------------------------
print_step "Generating real node keys (using geth inside Docker)"

declare -A NODE_PUBKEYS
declare -A NODE_ADDRESSES

for node in "${NODES[@]}"; do
    print_info "Generating key for ${node}..."

    # Generate nodekey using geth
    docker run --rm \
        -v "${NETWORK_DIR}/${node}/data:/data" \
        "$QUORUM_IMAGE" \
        sh -c "cd /data && geth account new --datadir /tmp/acct --password /dev/null 2>/dev/null; \
               if [ ! -f /data/nodekey ]; then \
                   bootnode --genkey=/data/nodekey 2>/dev/null || \
                   geth --datadir /tmp/keydir init /dev/null 2>/dev/null; \
               fi; \
               # Ensure we have a nodekey
               if [ ! -f /data/nodekey ]; then \
                   head -c 32 /dev/urandom | xxd -p -c 32 > /data/nodekey; \
               fi"

    # Some quorum images don't have bootnode, so let's use a Python fallback
    if [ ! -f "${NETWORK_DIR}/${node}/data/nodekey" ] || [ ! -s "${NETWORK_DIR}/${node}/data/nodekey" ]; then
        print_info "  Using fallback key generation for ${node}..."
        python3 -c "import secrets; print(secrets.token_hex(32))" > "${NETWORK_DIR}/${node}/data/nodekey"
    fi

    # Get the enode public key from the nodekey
    PUBKEY=$(docker run --rm \
        -v "${NETWORK_DIR}/${node}/data:/data" \
        "$QUORUM_IMAGE" \
        sh -c "bootnode --nodekey=/data/nodekey --writeaddress 2>/dev/null || \
               geth --nodekey /data/nodekey --exec 'console.log(admin.nodeInfo.enode)' console 2>/dev/null | grep -oP '(?<=enode://)[a-f0-9]+'" \
        2>/dev/null | tr -d '[:space:]')

    # If we still don't have a pubkey, use the js console method
    if [ -z "$PUBKEY" ] || [ ${#PUBKEY} -ne 128 ]; then
        print_info "  Extracting pubkey via geth for ${node}..."
        PUBKEY=$(docker run --rm \
            -v "${NETWORK_DIR}/${node}/data:/data" \
            --entrypoint="" \
            "$QUORUM_IMAGE" \
            sh -c "bootnode -nodekey /data/nodekey -writeaddress" \
            2>/dev/null | tr -d '[:space:]')
    fi

    if [ -z "$PUBKEY" ] || [ ${#PUBKEY} -ne 128 ]; then
        print_error "Failed to generate pubkey for ${node}. Pubkey length: ${#PUBKEY}"
        print_info "  Trying alternate method..."

        # Last resort: use geth's built-in
        PUBKEY=$(docker run --rm \
            -v "${NETWORK_DIR}/${node}/data:/data" \
            --entrypoint="" \
            "$QUORUM_IMAGE" \
            bootnode -nodekey /data/nodekey -writeaddress \
            2>&1 | tail -1 | tr -d '[:space:]')

        if [ -z "$PUBKEY" ] || [ ${#PUBKEY} -ne 128 ]; then
            print_error "Cannot generate pubkey for ${node}. Check Docker image."
            exit 1
        fi
    fi

    NODE_PUBKEYS[$node]="$PUBKEY"
    print_done "${node}: ${PUBKEY:0:16}...${PUBKEY: -16}"
done

# --------------------------------------------------
# 4. Get validator addresses (needed for genesis extraData)
# --------------------------------------------------
print_step "Deriving validator addresses from node keys"

for val in "${VALIDATORS[@]}"; do
    # The address is derived from the public key
    # We create a temp account to get the address
    ADDRESS=$(docker run --rm \
        -v "${NETWORK_DIR}/${val}/data:/data" \
        --entrypoint="" \
        "$QUORUM_IMAGE" \
        sh -c "
            # Create a password file
            echo '' > /tmp/pass.txt
            # Import the nodekey as an account to derive address
            geth account import --datadir /tmp/addr --password /tmp/pass.txt /data/nodekey 2>&1 | grep -oP '0x[a-fA-F0-9]{40}' | head -1
        " 2>/dev/null | tr -d '[:space:]')

    if [ -z "$ADDRESS" ]; then
        print_error "Failed to derive address for ${val}"
        exit 1
    fi

    NODE_ADDRESSES[$val]="$ADDRESS"
    print_done "${val}: ${ADDRESS}"
done

# --------------------------------------------------
# 5. Generate IBFT genesis with proper extraData
# --------------------------------------------------
print_step "Generating IBFT genesis file"

# IBFT extraData format:
# 32 bytes vanity + RLP([validators], seal, committed_seals)
# We use istanbul extra-data encoder via python

ADDR1="${NODE_ADDRESSES[validator1]#0x}"
ADDR2="${NODE_ADDRESSES[validator2]#0x}"
ADDR3="${NODE_ADDRESSES[validator3]#0x}"

# Generate the extraData using Python RLP encoding
EXTRA_DATA=$(python3 << PYEOF
import struct

def encode_length(length, offset):
    if length < 56:
        return bytes([length + offset])
    elif length < 256**8:
        bl = length.to_bytes((length.bit_length() + 7) // 8, 'big')
        return bytes([len(bl) + offset + 55]) + bl
    else:
        raise ValueError("Input too long")

def encode_string(s):
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

# Validator addresses (sorted)
validators = sorted([
    bytes.fromhex("${ADDR1}"),
    bytes.fromhex("${ADDR2}"),
    bytes.fromhex("${ADDR3}"),
])

# Encode validators as list of strings
encoded_validators = encode_list([encode_string(v) for v in validators])

# IBFT extra: vanity + RLP([validators], seal, committed_seals)
# seal = empty (65 bytes of zeros for genesis)
seal = encode_string(b'\x00' * 65)
# committed_seals = empty list
committed_seals = encode_list([])

# Full RLP: list of [validators_list, seal, committed_seals]
# Actually for Istanbul/IBFT, the extraData is:
# vanity (32 bytes) + istanbul_extra_rlp
# where istanbul_extra_rlp = RLP([validators, seal, committed_seals])

istanbul_extra = encode_list([encoded_validators, seal, committed_seals])

extra_data = vanity + istanbul_extra
print("0x" + extra_data.hex())
PYEOF
)

print_info "ExtraData generated (${#EXTRA_DATA} chars)"

# Pre-fund all validator and rpc accounts
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
    "${ADDR1}": {
      "balance": "1000000000000000000000000000"
    },
    "${ADDR2}": {
      "balance": "1000000000000000000000000000"
    },
    "${ADDR3}": {
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

print_done "Genesis file created with proper validator set"

# --------------------------------------------------
# 6. Create static-nodes.json with real enode URLs
# --------------------------------------------------
print_step "Creating static-nodes.json with real enode URLs"

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
print_done "static-nodes.json created with real public keys"

# --------------------------------------------------
# 7. Distribute config to all nodes
# --------------------------------------------------
print_step "Distributing configuration to all nodes"

for node in "${NODES[@]}"; do
    cp "${CONFIG_DIR}/genesis.json"           "${NETWORK_DIR}/${node}/data/"
    cp "${CONFIG_DIR}/static-nodes.json"      "${NETWORK_DIR}/${node}/data/"
    cp "${CONFIG_DIR}/permissioned-nodes.json" "${NETWORK_DIR}/${node}/data/"
    print_info "Configured ${node}"
done

print_done "All nodes configured"

# --------------------------------------------------
# 8. Initialize geth on each node
# --------------------------------------------------
print_step "Initializing geth on each node (genesis block)"

for node in "${NODES[@]}"; do
    print_info "Initializing ${node}..."

    docker run --rm \
        -v "${NETWORK_DIR}/${node}/data:/data" \
        --entrypoint="" \
        "$QUORUM_IMAGE" \
        geth --datadir /data init /data/genesis.json \
        2>&1 | tail -2

    # Copy static-nodes into geth directory (geth looks here after init)
    cp "${CONFIG_DIR}/static-nodes.json"      "${NETWORK_DIR}/${node}/data/geth/"
    cp "${CONFIG_DIR}/permissioned-nodes.json" "${NETWORK_DIR}/${node}/data/geth/"

    print_done "${node} initialized"
done

# --------------------------------------------------
# 9. Update docker-compose to NOT re-init (already done)
# --------------------------------------------------
print_step "Creating updated docker-compose.yml (pre-initialized nodes)"

cat > "${DOCKER_DIR}/docker-compose.yml" << 'DOCKERCOMPOSE'
x-quorum-defaults: &quorum-defaults
  image: quorumengineering/quorum:latest
  restart: unless-stopped
  healthcheck:
    test: ["CMD-SHELL", "geth attach /data/geth.ipc --exec eth.blockNumber || exit 1"]
    interval: 10s
    timeout: 5s
    retries: 10
    start_period: 30s

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

  # ── VALIDATOR 1 ──────────────────────────────────
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
          --verbosity 3 \
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

  # ── VALIDATOR 2 ──────────────────────────────────
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
      validator1:
        condition: service_started
    entrypoint:
      - /bin/sh
      - -c
      - |
        sleep 3
        geth \
          --datadir /data \
          --networkid 7001 \
          --nodiscover \
          --verbosity 3 \
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

  # ── VALIDATOR 3 ──────────────────────────────────
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
      validator1:
        condition: service_started
    entrypoint:
      - /bin/sh
      - -c
      - |
        sleep 5
        geth \
          --datadir /data \
          --networkid 7001 \
          --nodiscover \
          --verbosity 3 \
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

  # ── RPC NODE 1 ───────────────────────────────────
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
      validator1:
        condition: service_started
      validator2:
        condition: service_started
      validator3:
        condition: service_started
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

  # ── RPC NODE 2 ───────────────────────────────────
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
      validator1:
        condition: service_started
      validator2:
        condition: service_started
      validator3:
        condition: service_started
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

  # ── BOOTNODE ─────────────────────────────────────
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

  # ── PROMETHEUS ───────────────────────────────────
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

  # ── GRAFANA ──────────────────────────────────────
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

print_done "Docker Compose updated (no re-init on start)"

# --------------------------------------------------
# 10. Save key info for Hardhat config
# --------------------------------------------------
print_step "Saving network info for development"

# Get the first validator's private key for use in Hardhat
VAL1_NODEKEY=$(cat "${NETWORK_DIR}/validator1/data/nodekey")

cat > "${CONFIG_DIR}/network-info.json" << NETINFO
{
  "_WARNING": "DEVELOPMENT KEYS ONLY — DO NOT USE IN PRODUCTION",
  "chainId": 7001,
  "networkId": 7001,
  "validators": {
    "validator1": {
      "address": "${NODE_ADDRESSES[validator1]}",
      "rpc": "http://localhost:8545",
      "ws": "ws://localhost:8546",
      "enode": "enode://${NODE_PUBKEYS[validator1]}@validator1:30303"
    },
    "validator2": {
      "address": "${NODE_ADDRESSES[validator2]}",
      "rpc": "http://localhost:8547",
      "ws": "ws://localhost:8548",
      "enode": "enode://${NODE_PUBKEYS[validator2]}@validator2:30303"
    },
    "validator3": {
      "address": "${NODE_ADDRESSES[validator3]}",
      "rpc": "http://localhost:8549",
      "ws": "ws://localhost:8550",
      "enode": "enode://${NODE_PUBKEYS[validator3]}@validator3:30303"
    }
  },
  "rpcNodes": {
    "rpc1": "http://localhost:8551",
    "rpc2": "http://localhost:8553"
  },
  "deployerKey": "0x${VAL1_NODEKEY}"
}
NETINFO

# Update hardhat.config.js with the real key
cat > "${PROJECT_DIR}/hardhat.config.js" << HARDHAT
require("@nomicfoundation/hardhat-toolbox");

/** @type import('hardhat/config').HardhatUserConfig */
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

# Update test transaction script with the real key
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

  const wallet = new ethers.Wallet(
    "0x${VAL1_NODEKEY}",
    provider
  );
  console.log("  Sender:", wallet.address);

  const balance = await provider.getBalance(wallet.address);
  console.log("  Balance:", ethers.formatEther(balance), "ETH");

  if (balance === 0n) {
    console.log("\\n  ⚠ Balance is zero. Check that the genesis allocated to this address.");
    console.log("  Expected address in genesis: ${NODE_ADDRESSES[validator1]}");
    return;
  }

  // Send a zero-gas test transaction to validator2's address
  const testAddr = "${NODE_ADDRESSES[validator2]}";
  console.log("\\n  Sending 1 ETH (zero gas) to", testAddr, "...");

  const tx = await wallet.sendTransaction({
    to: testAddr,
    value: ethers.parseEther("1.0"),
    gasPrice: 0,
    gasLimit: 21000,
    type: 0,  // Legacy transaction (required for Quorum)
  });

  console.log("  TX hash:", tx.hash);
  const receipt = await tx.wait();
  console.log("  Confirmed in block:", receipt.blockNumber);
  console.log("  Gas used:", receipt.gasUsed.toString());
  console.log("\\n  ✓ Zero-gas transaction successful!");
  console.log("============================================================");
}

main().catch((err) => {
  console.error("\\n  ✗ Transaction failed:", err.message);
  if (err.message.includes("block not found")) {
    console.error("  → The network may not be producing blocks yet.");
    console.error("  → Run: npm run network:status");
    console.error("  → Check logs: docker logs vittagems-validator1 --tail 50");
  }
});
TESTSCRIPT

print_done "Network info and configs updated with real keys"

# --------------------------------------------------
# 11. Start the network
# --------------------------------------------------
print_step "Starting VittaGems network"

cd "${DOCKER_DIR}"
docker compose up -d

echo ""
print_info "Waiting 20 seconds for nodes to start and peer..."
sleep 20

# --------------------------------------------------
# 12. Verify
# --------------------------------------------------
print_step "Verifying network status"

echo ""
bash "${PROJECT_DIR}/scripts/utils/network-status.sh"

echo ""
echo "============================================================"
echo "  Initialization Complete!"
echo "============================================================"
echo ""
echo "  If blocks are being produced (block > 0), run:"
echo ""
echo "    cd ${PROJECT_DIR}"
echo "    node scripts/utils/test-transaction.js"
echo "    npm run compile"
echo "    npm run deploy:local"
echo ""
echo "  If blocks are still at 0, check validator logs:"
echo ""
echo "    docker logs vittagems-validator1 --tail 100"
echo "    docker logs vittagems-validator2 --tail 100"
echo ""
echo "============================================================"