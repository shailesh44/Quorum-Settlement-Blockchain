#!/bin/bash

# ============================================================
# VittaGems — Parameterized Network Deployment
# ============================================================
# Usage:
#   ./deploy-network.sh [OPTIONS]
#
# Options:
#   --validators N        Number of validator nodes (default: 3, min: 1)
#   --rpc-nodes N         Number of RPC nodes (default: 2, min: 1)
#   --chain-id N          Chain ID (default: 7001)
#   --network-id N        Network ID (default: same as chain-id)
#   --block-period N      Block period in seconds (default: 5)
#   --gas-limit HEX       Gas limit in hex (default: 0xFFFFFFFF)
#   --project-dir PATH    Project directory (default: current dir)
#   --network-name NAME   Docker network/project name (default: vittagems)
#   --org-name NAME       Organization name (default: VittaGems)
#   --subnet CIDR         Docker subnet (default: 172.16.239.0/24)
#   --base-rpc-port N     Starting RPC port (default: 8545)
#   --base-p2p-port N     Starting P2P port (default: 30303)
#   --base-metrics-port N Starting metrics port (default: 9545)
#   --monitoring          Enable Prometheus+Grafana (default: enabled)
#   --no-monitoring       Disable monitoring
#   --no-start            Generate configs only, don't start
#   --reset               Clean all data before deploying
#   --verbose             Show detailed output
#   --help                Show this help
#
# Examples:
#   ./deploy-network.sh
#   ./deploy-network.sh --validators 4 --rpc-nodes 3 --chain-id 8001
#   ./deploy-network.sh --validators 5 --block-period 2 --network-name testnet
#   ./deploy-network.sh --reset --validators 3
# ============================================================

set -e

# ── Defaults ────────────────────────────────────────
NUM_VALIDATORS=3
NUM_RPC_NODES=2
CHAIN_ID=7001
NETWORK_ID=""
BLOCK_PERIOD=5
GAS_LIMIT="0xFFFFFFFF"
PROJECT_DIR="$(pwd)"
NETWORK_NAME="vittagems"
ORG_NAME="VittaGems"
SUBNET="172.16.239.0/24"
BASE_RPC_PORT=8545
BASE_P2P_PORT=30303
BASE_METRICS_PORT=9545
MONITORING=true
AUTO_START=true
RESET=false
VERBOSE=false

QUORUM_IMAGE="quorumengineering/quorum:latest"

# ── Colors ──────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

print_step()  { echo -e "\n${GREEN}━━━ [STEP] $1 ━━━${NC}"; }
print_info()  { echo -e "  ${CYAN}→${NC} $1"; }
print_done()  { echo -e "  ${GREEN}✓${NC} $1"; }
print_warn()  { echo -e "  ${YELLOW}⚠${NC} $1"; }
print_error() { echo -e "  ${RED}✗${NC} $1"; }

# ── Parse Arguments ─────────────────────────────────
show_help() {
    head -35 "$0" | tail -32
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --validators)       NUM_VALIDATORS="$2"; shift 2 ;;
        --rpc-nodes)        NUM_RPC_NODES="$2"; shift 2 ;;
        --chain-id)         CHAIN_ID="$2"; shift 2 ;;
        --network-id)       NETWORK_ID="$2"; shift 2 ;;
        --block-period)     BLOCK_PERIOD="$2"; shift 2 ;;
        --gas-limit)        GAS_LIMIT="$2"; shift 2 ;;
        --project-dir)      PROJECT_DIR="$2"; shift 2 ;;
        --network-name)     NETWORK_NAME="$2"; shift 2 ;;
        --org-name)         ORG_NAME="$2"; shift 2 ;;
        --subnet)           SUBNET="$2"; shift 2 ;;
        --base-rpc-port)    BASE_RPC_PORT="$2"; shift 2 ;;
        --base-p2p-port)    BASE_P2P_PORT="$2"; shift 2 ;;
        --base-metrics-port) BASE_METRICS_PORT="$2"; shift 2 ;;
        --monitoring)       MONITORING=true; shift ;;
        --no-monitoring)    MONITORING=false; shift ;;
        --no-start)         AUTO_START=false; shift ;;
        --reset)            RESET=true; shift ;;
        --verbose)          VERBOSE=true; shift ;;
        --help|-h)          show_help ;;
        *) print_error "Unknown option: $1"; echo "Use --help for usage."; exit 1 ;;
    esac
done

[ -z "$NETWORK_ID" ] && NETWORK_ID="$CHAIN_ID"

# ── Validation ──────────────────────────────────────
if [ "$NUM_VALIDATORS" -lt 1 ]; then
    print_error "Need at least 1 validator"; exit 1
fi
if [ "$NUM_RPC_NODES" -lt 1 ]; then
    print_error "Need at least 1 RPC node"; exit 1
fi

# IBFT fault tolerance info
FAULT_TOLERANCE=$(( (NUM_VALIDATORS - 1) / 3 ))
QUORUM_NEEDED=$(( NUM_VALIDATORS - FAULT_TOLERANCE ))

# ── Directories ─────────────────────────────────────
NETWORK_DIR="${PROJECT_DIR}/network"
CONFIG_DIR="${PROJECT_DIR}/config"
DOCKER_DIR="${PROJECT_DIR}/docker"
MONITORING_DIR="${PROJECT_DIR}/monitoring"

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  ${BOLD}VittaGems — Parameterized Network Deployment${NC}              ║"
echo "╠════════════════════════════════════════════════════════════╣"
echo "║                                                          ║"
echo "║  Validators:    ${NUM_VALIDATORS}                                        ║"
echo "║  RPC Nodes:     ${NUM_RPC_NODES}                                        ║"
echo "║  Chain ID:      ${CHAIN_ID}                                     ║"
echo "║  Block Period:  ${BLOCK_PERIOD}s                                       ║"
echo "║  Gas Limit:     ${GAS_LIMIT}                             ║"
echo "║  Network:       ${NETWORK_NAME}                                 ║"
echo "║  Monitoring:    ${MONITORING}                                     ║"
echo "║  Fault Tol:     ${FAULT_TOLERANCE} (need ${QUORUM_NEEDED}/${NUM_VALIDATORS} validators for consensus) ║"
echo "║                                                          ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# ── Pre-flight ──────────────────────────────────────
print_step "Pre-flight checks"

if ! command -v docker &>/dev/null; then
    print_error "Docker not found"; exit 1
fi
if ! docker info &>/dev/null 2>&1; then
    print_error "Docker daemon not running"; exit 1
fi
if ! command -v python3 &>/dev/null; then
    print_error "Python3 not found (needed for genesis generation)"; exit 1
fi
if ! command -v jq &>/dev/null; then
    print_error "jq not found (sudo apt install jq)"; exit 1
fi

docker pull "$QUORUM_IMAGE" 2>/dev/null || true
docker run --rm --entrypoint="" "$QUORUM_IMAGE" sh -c "echo OK" >/dev/null 2>&1
print_done "All checks passed"

# ── Reset ───────────────────────────────────────────
if [ "$RESET" = true ]; then
    print_step "Resetting existing network"
    cd "${DOCKER_DIR}" 2>/dev/null && docker compose down -v 2>/dev/null || true
    rm -rf "${NETWORK_DIR}"
    print_done "Old network data removed"
fi

# ── Stop Existing ───────────────────────────────────
print_step "Stopping any existing network"
cd "${DOCKER_DIR}" 2>/dev/null && docker compose down -v 2>/dev/null || true
print_done "Clean state"

# ── Build Node List ─────────────────────────────────
print_step "Building node configuration"

ALL_NODES=()
VALIDATOR_NODES=()
RPC_NODES_LIST=()

for i in $(seq 1 "$NUM_VALIDATORS"); do
    ALL_NODES+=("validator${i}")
    VALIDATOR_NODES+=("validator${i}")
done

for i in $(seq 1 "$NUM_RPC_NODES"); do
    ALL_NODES+=("rpc${i}")
    RPC_NODES_LIST+=("rpc${i}")
done

ALL_NODES+=("bootnode")

TOTAL_NODES=${#ALL_NODES[@]}
print_done "Total nodes: $TOTAL_NODES (${NUM_VALIDATORS} validators + ${NUM_RPC_NODES} RPC + 1 bootnode)"

# ── Create Directories ──────────────────────────────
print_step "Creating directory structure"

for node in "${ALL_NODES[@]}"; do
    mkdir -p "${NETWORK_DIR}/${node}/data"
    mkdir -p "${NETWORK_DIR}/${node}/logs"
done
mkdir -p "${CONFIG_DIR}"
mkdir -p "${DOCKER_DIR}"
mkdir -p "${MONITORING_DIR}/prometheus"
mkdir -p "${MONITORING_DIR}/grafana/provisioning/datasources"
mkdir -p "${MONITORING_DIR}/grafana/provisioning/dashboards"
mkdir -p "${MONITORING_DIR}/grafana/dashboards"
mkdir -p "${PROJECT_DIR}/deployments"

print_done "Directories created"

# ── Generate Node Keys ──────────────────────────────
print_step "Generating node keys (${TOTAL_NODES} nodes)"

declare -A NODE_PUBKEYS

for node in "${ALL_NODES[@]}"; do
    # Clean any old key
    rm -f "${NETWORK_DIR}/${node}/data/nodekey"

    # Generate using bootnode inside the Quorum image
    docker run --rm \
        --entrypoint="" \
        -v "${NETWORK_DIR}/${node}/data:/data" \
        "$QUORUM_IMAGE" \
        bootnode --genkey=/data/nodekey 2>/dev/null

    # Extract public key
    PUBKEY=$(docker run --rm \
        --entrypoint="" \
        -v "${NETWORK_DIR}/${node}/data:/data" \
        "$QUORUM_IMAGE" \
        bootnode --nodekey=/data/nodekey --writeaddress 2>/dev/null \
        | tr -d '[:space:]')

    if [ -z "$PUBKEY" ] || [ ${#PUBKEY} -ne 128 ]; then
        print_error "Failed to generate key for ${node}"
        exit 1
    fi

    NODE_PUBKEYS[$node]="$PUBKEY"
    print_done "${node}: ${PUBKEY:0:12}...${PUBKEY: -12}"
done

# ── Derive Validator Addresses ──────────────────────
print_step "Deriving validator addresses"

declare -A NODE_ADDRESSES

for val in "${VALIDATOR_NODES[@]}"; do
    ADDRESS=$(docker run --rm \
        --entrypoint="" \
        -v "${NETWORK_DIR}/${val}/data:/data" \
        "$QUORUM_IMAGE" \
        sh -c "echo '' > /tmp/pass.txt && geth account import --datadir /tmp/addr --password /tmp/pass.txt /data/nodekey 2>&1" \
        | grep -oiP '[a-fA-F0-9]{40}' | head -1)

    if [ -n "$ADDRESS" ]; then
        ADDRESS="0x${ADDRESS}"
    else
        print_error "Failed to derive address for ${val}"
        exit 1
    fi

    NODE_ADDRESSES[$val]="$ADDRESS"
    print_done "${val}: ${ADDRESS}"
done

# ── Generate Genesis ────────────────────────────────
print_step "Generating IBFT genesis (Chain ID: ${CHAIN_ID})"

# Build validator address list for Python
VALIDATOR_ADDRS_PY=""
for val in "${VALIDATOR_NODES[@]}"; do
    addr="${NODE_ADDRESSES[$val]#0x}"
    VALIDATOR_ADDRS_PY+="\"${addr}\","
done
# Remove trailing comma
VALIDATOR_ADDRS_PY="${VALIDATOR_ADDRS_PY%,}"

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

vanity = b'\x00' * 32
addrs = sorted([${VALIDATOR_ADDRS_PY}], key=str.lower)
validators = [bytes.fromhex(a.lower()) for a in addrs]
encoded_validators = encode_list([encode_string(v) for v in validators])
seal = encode_string(b'\x00' * 65)
committed_seals = encode_list([])
istanbul_extra = encode_list([encoded_validators, seal, committed_seals])
extra_data = vanity + istanbul_extra
print("0x" + extra_data.hex())
PYEOF
)

# Build alloc JSON
ALLOC_JSON=""
for val in "${VALIDATOR_NODES[@]}"; do
    addr="${NODE_ADDRESSES[$val]#0x}"
    addr_lower=$(echo "$addr" | tr '[:upper:]' '[:lower:]')
    ALLOC_JSON+="    \"${addr_lower}\": { \"balance\": \"1000000000000000000000000000\" },"
done
ALLOC_JSON="${ALLOC_JSON%,}"

cat > "${CONFIG_DIR}/genesis.json" << GENESIS
{
  "nonce": "0x0",
  "timestamp": "0x0",
  "extraData": "${EXTRA_DATA}",
  "gasLimit": "${GAS_LIMIT}",
  "difficulty": "0x1",
  "mixHash": "0x63746963616c2062797a616e74696e65206661756c7420746f6c6572616e6365",
  "coinbase": "0x0000000000000000000000000000000000000000",
  "alloc": {
${ALLOC_JSON}
  },
  "config": {
    "chainId": ${CHAIN_ID},
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

print_done "Genesis created with ${NUM_VALIDATORS} validators"

# ── Create static-nodes.json ───────────────────────
print_step "Creating static-nodes.json"

STATIC_NODES="["
for node in "${ALL_NODES[@]}"; do
    STATIC_NODES+="\n  \"enode://${NODE_PUBKEYS[$node]}@${node}:30303?discport=0\","
done
STATIC_NODES="${STATIC_NODES%,}"
STATIC_NODES+="\n]"

echo -e "$STATIC_NODES" > "${CONFIG_DIR}/static-nodes.json"
cp "${CONFIG_DIR}/static-nodes.json" "${CONFIG_DIR}/permissioned-nodes.json"

print_done "static-nodes.json created (${TOTAL_NODES} entries)"

# ── Initialize All Nodes ───────────────────────────
print_step "Initializing nodes with genesis block"

for node in "${ALL_NODES[@]}"; do
    cp "${CONFIG_DIR}/genesis.json" "${NETWORK_DIR}/${node}/data/"
    cp "${CONFIG_DIR}/static-nodes.json" "${NETWORK_DIR}/${node}/data/"
    cp "${CONFIG_DIR}/permissioned-nodes.json" "${NETWORK_DIR}/${node}/data/"

    docker run --rm \
        --entrypoint="" \
        -v "${NETWORK_DIR}/${node}/data:/data" \
        "$QUORUM_IMAGE" \
        geth --datadir /data init /data/genesis.json 2>&1 | \
        { $VERBOSE && cat || tail -1; }

    # Copy into geth subdir (where geth reads after init)
    if [ -d "${NETWORK_DIR}/${node}/data/geth" ]; then
        cp "${CONFIG_DIR}/static-nodes.json" "${NETWORK_DIR}/${node}/data/geth/"
        cp "${CONFIG_DIR}/permissioned-nodes.json" "${NETWORK_DIR}/${node}/data/geth/"
    fi

    print_done "${node} initialized"
done

# ── Generate docker-compose.yml ─────────────────────
print_step "Generating docker-compose.yml"

# Calculate IP addresses
SUBNET_PREFIX=$(echo "$SUBNET" | sed 's|\.[0-9]*/.*||')
IP_COUNTER=10

# Port tracking
RPC_PORT=$BASE_RPC_PORT
WS_PORT=$((BASE_RPC_PORT + 1))
P2P_PORT=$BASE_P2P_PORT
METRICS_PORT=$BASE_METRICS_PORT

# Start composing
cat > "${DOCKER_DIR}/docker-compose.yml" << 'HEADER'
x-quorum-defaults: &quorum-defaults
  image: quorumengineering/quorum:latest
  restart: unless-stopped

x-quorum-env: &quorum-env
  PRIVATE_CONFIG: ignore

HEADER

# Network section
cat >> "${DOCKER_DIR}/docker-compose.yml" << NETWORK
networks:
  ${NETWORK_NAME}-net:
    driver: bridge
    ipam:
      config:
        - subnet: ${SUBNET}

volumes:
  prometheus-data:
  grafana-data:

services:
NETWORK

# Port mapping tracker for documentation
declare -A PORT_MAP

# ── Validator services ──
for i in $(seq 1 "$NUM_VALIDATORS"); do
    NODE_NAME="validator${i}"
    NODE_IP="${SUBNET_PREFIX}.${IP_COUNTER}"; IP_COUNTER=$((IP_COUNTER + 1))
    SLEEP_TIME=$(( (i - 1) * 2 ))

    PORT_MAP[$NODE_NAME]="RPC:${RPC_PORT} WS:${WS_PORT} P2P:${P2P_PORT} Metrics:${METRICS_PORT}"

    MINE_FLAGS="--mine --miner.threads 1"

    cat >> "${DOCKER_DIR}/docker-compose.yml" << VALIDATOR

  ${NODE_NAME}:
    <<: *quorum-defaults
    container_name: ${NETWORK_NAME}-${NODE_NAME}
    hostname: ${NODE_NAME}
    ports:
      - "${RPC_PORT}:8545"
      - "${WS_PORT}:8546"
      - "${P2P_PORT}:30303"
      - "${METRICS_PORT}:9545"
    volumes:
      - ../network/${NODE_NAME}/data:/data
      - ../network/${NODE_NAME}/logs:/logs
    networks:
      ${NETWORK_NAME}-net:
        ipv4_address: ${NODE_IP}
VALIDATOR

    # Add depends_on for validators after the first
    if [ "$i" -gt 1 ]; then
        cat >> "${DOCKER_DIR}/docker-compose.yml" << DEP
    depends_on:
      - validator1
DEP
    fi

    cat >> "${DOCKER_DIR}/docker-compose.yml" << ENTRYPOINT
    entrypoint:
      - /bin/sh
      - -c
      - |
        sleep ${SLEEP_TIME}
        geth \\
          --datadir /data \\
          --networkid ${NETWORK_ID} \\
          --nodiscover \\
          --verbosity 3 \\
          --syncmode full \\
          --istanbul.blockperiod ${BLOCK_PERIOD} \\
          ${MINE_FLAGS} \\
          --miner.gasprice 0 \\
          --emitcheckpoints \\
          --http \\
          --http.addr 0.0.0.0 \\
          --http.port 8545 \\
          --http.corsdomain "*" \\
          --http.vhosts "*" \\
          --http.api admin,eth,debug,miner,net,txpool,personal,web3,istanbul \\
          --ws \\
          --ws.addr 0.0.0.0 \\
          --ws.port 8546 \\
          --ws.origins "*" \\
          --ws.api admin,eth,debug,miner,net,txpool,personal,web3,istanbul \\
          --port 30303 \\
          --allow-insecure-unlock \\
          --metrics \\
          --metrics.addr 0.0.0.0 \\
          --metrics.port 9545 \\
        2>&1 | tee /logs/${NODE_NAME}.log
    environment:
      <<: *quorum-env
ENTRYPOINT

    RPC_PORT=$((RPC_PORT + 2))
    WS_PORT=$((WS_PORT + 2))
    P2P_PORT=$((P2P_PORT + 1))
    METRICS_PORT=$((METRICS_PORT + 1))
done

# ── RPC Node services ──
for i in $(seq 1 "$NUM_RPC_NODES"); do
    NODE_NAME="rpc${i}"
    NODE_IP="${SUBNET_PREFIX}.${IP_COUNTER}"; IP_COUNTER=$((IP_COUNTER + 1))
    SLEEP_TIME=$(( NUM_VALIDATORS * 2 + i * 2 ))

    PORT_MAP[$NODE_NAME]="RPC:${RPC_PORT} WS:${WS_PORT} P2P:${P2P_PORT} Metrics:${METRICS_PORT}"

    # Build depends_on list for all validators
    DEPENDS_LIST=""
    for v in $(seq 1 "$NUM_VALIDATORS"); do
        DEPENDS_LIST+="      - validator${v}\n"
    done

    cat >> "${DOCKER_DIR}/docker-compose.yml" << RPCNODE

  ${NODE_NAME}:
    <<: *quorum-defaults
    container_name: ${NETWORK_NAME}-${NODE_NAME}
    hostname: ${NODE_NAME}
    ports:
      - "${RPC_PORT}:8545"
      - "${WS_PORT}:8546"
      - "${P2P_PORT}:30303"
      - "${METRICS_PORT}:9545"
    volumes:
      - ../network/${NODE_NAME}/data:/data
      - ../network/${NODE_NAME}/logs:/logs
    networks:
      ${NETWORK_NAME}-net:
        ipv4_address: ${NODE_IP}
    depends_on:
$(echo -e "$DEPENDS_LIST")
    entrypoint:
      - /bin/sh
      - -c
      - |
        sleep ${SLEEP_TIME}
        geth \\
          --datadir /data \\
          --networkid ${NETWORK_ID} \\
          --nodiscover \\
          --verbosity 3 \\
          --syncmode full \\
          --miner.gasprice 0 \\
          --http \\
          --http.addr 0.0.0.0 \\
          --http.port 8545 \\
          --http.corsdomain "*" \\
          --http.vhosts "*" \\
          --http.api admin,eth,debug,miner,net,txpool,personal,web3,istanbul \\
          --ws \\
          --ws.addr 0.0.0.0 \\
          --ws.port 8546 \\
          --ws.origins "*" \\
          --ws.api admin,eth,debug,miner,net,txpool,personal,web3,istanbul \\
          --port 30303 \\
          --allow-insecure-unlock \\
          --metrics \\
          --metrics.addr 0.0.0.0 \\
          --metrics.port 9545 \\
        2>&1 | tee /logs/${NODE_NAME}.log
    environment:
      <<: *quorum-env
RPCNODE

    RPC_PORT=$((RPC_PORT + 2))
    WS_PORT=$((WS_PORT + 2))
    P2P_PORT=$((P2P_PORT + 1))
    METRICS_PORT=$((METRICS_PORT + 1))
done

# ── Bootnode service ──
BOOTNODE_IP="${SUBNET_PREFIX}.${IP_COUNTER}"; IP_COUNTER=$((IP_COUNTER + 1))
cat >> "${DOCKER_DIR}/docker-compose.yml" << BOOTNODE

  bootnode:
    <<: *quorum-defaults
    container_name: ${NETWORK_NAME}-bootnode
    hostname: bootnode
    ports:
      - "${P2P_PORT}:30303"
    volumes:
      - ../network/bootnode/data:/data
      - ../network/bootnode/logs:/logs
    networks:
      ${NETWORK_NAME}-net:
        ipv4_address: ${BOOTNODE_IP}
    entrypoint:
      - /bin/sh
      - -c
      - |
        geth \\
          --datadir /data \\
          --networkid ${NETWORK_ID} \\
          --nodiscover \\
          --verbosity 3 \\
          --syncmode full \\
          --miner.gasprice 0 \\
          --http \\
          --http.addr 0.0.0.0 \\
          --http.port 8545 \\
          --http.corsdomain "*" \\
          --http.vhosts "*" \\
          --http.api admin,eth,debug,miner,net,txpool,personal,web3,istanbul \\
          --port 30303 \\
          --allow-insecure-unlock \\
        2>&1 | tee /logs/bootnode.log
    environment:
      <<: *quorum-env
BOOTNODE

# ── Monitoring services ──
if [ "$MONITORING" = true ]; then
    PROM_IP="${SUBNET_PREFIX}.${IP_COUNTER}"; IP_COUNTER=$((IP_COUNTER + 1))
    GRAF_IP="${SUBNET_PREFIX}.${IP_COUNTER}"; IP_COUNTER=$((IP_COUNTER + 1))

    cat >> "${DOCKER_DIR}/docker-compose.yml" << MONITORING_SERVICES

  prometheus:
    image: prom/prometheus:latest
    container_name: ${NETWORK_NAME}-prometheus
    restart: unless-stopped
    ports:
      - "9090:9090"
    volumes:
      - ../monitoring/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus-data:/prometheus
    networks:
      ${NETWORK_NAME}-net:
        ipv4_address: ${PROM_IP}

  grafana:
    image: grafana/grafana:latest
    container_name: ${NETWORK_NAME}-grafana
    restart: unless-stopped
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=${NETWORK_NAME}
      - GF_USERS_ALLOW_SIGN_UP=false
    volumes:
      - grafana-data:/var/lib/grafana
      - ../monitoring/grafana/provisioning:/etc/grafana/provisioning
      - ../monitoring/grafana/dashboards:/var/lib/grafana/dashboards
    depends_on:
      - prometheus
    networks:
      ${NETWORK_NAME}-net:
        ipv4_address: ${GRAF_IP}
MONITORING_SERVICES

    # Generate Prometheus config
    PROM_TARGETS_VAL=""
    for i in $(seq 1 "$NUM_VALIDATORS"); do
        PROM_TARGETS_VAL+="          - 'validator${i}:9545'\n"
    done

    PROM_TARGETS_RPC=""
    for i in $(seq 1 "$NUM_RPC_NODES"); do
        PROM_TARGETS_RPC+="          - 'rpc${i}:9545'\n"
    done

    cat > "${MONITORING_DIR}/prometheus/prometheus.yml" << PROMCFG
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: '${NETWORK_NAME}-validators'
    static_configs:
      - targets:
$(echo -e "$PROM_TARGETS_VAL")        labels:
          role: 'validator'

  - job_name: '${NETWORK_NAME}-rpc'
    static_configs:
      - targets:
$(echo -e "$PROM_TARGETS_RPC")        labels:
          role: 'rpc'

  - job_name: '${NETWORK_NAME}-bootnode'
    static_configs:
      - targets:
          - 'bootnode:9545'
        labels:
          role: 'bootnode'
PROMCFG

    cat > "${MONITORING_DIR}/grafana/provisioning/datasources/prometheus.yml" << GRAFDS
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: true
GRAFDS

fi

print_done "docker-compose.yml generated"

# ── Save Network Info ───────────────────────────────
print_step "Saving network configuration"

VAL1_KEY=$(cat "${NETWORK_DIR}/validator1/data/nodekey")

# Build JSON for network info
VALIDATORS_JSON="{"
for val in "${VALIDATOR_NODES[@]}"; do
    idx=${val#validator}
    rpc_p=$((BASE_RPC_PORT + (idx - 1) * 2))
    VALIDATORS_JSON+="\"${val}\": {\"address\": \"${NODE_ADDRESSES[$val]}\", \"rpc\": \"http://localhost:${rpc_p}\"},"
done
VALIDATORS_JSON="${VALIDATORS_JSON%,}}"

RPC_JSON="{"
for rpc in "${RPC_NODES_LIST[@]}"; do
    idx=${rpc#rpc}
    rpc_p=$((BASE_RPC_PORT + NUM_VALIDATORS * 2 + (idx - 1) * 2))
    RPC_JSON+="\"${rpc}\": \"http://localhost:${rpc_p}\","
done
RPC_JSON="${RPC_JSON%,}}"

cat > "${CONFIG_DIR}/network-info.json" << NETINFO
{
  "_WARNING": "DEVELOPMENT KEYS ONLY",
  "chainId": ${CHAIN_ID},
  "networkId": ${NETWORK_ID},
  "blockPeriod": ${BLOCK_PERIOD},
  "numValidators": ${NUM_VALIDATORS},
  "numRpcNodes": ${NUM_RPC_NODES},
  "faultTolerance": ${FAULT_TOLERANCE},
  "quorumNeeded": ${QUORUM_NEEDED},
  "networkName": "${NETWORK_NAME}",
  "orgName": "${ORG_NAME}",
  "validators": ${VALIDATORS_JSON},
  "rpcNodes": ${RPC_JSON},
  "deployerKey": "0x${VAL1_KEY}",
  "generatedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
NETINFO

# Update hardhat.config.js
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
HARDHAT

# Add validator networks
for val in "${VALIDATOR_NODES[@]}"; do
    idx=${val#validator}
    rpc_p=$((BASE_RPC_PORT + (idx - 1) * 2))
    cat >> "${PROJECT_DIR}/hardhat.config.js" << VALNET
    quorum_${val}: {
      url: "http://localhost:${rpc_p}",
      chainId: ${CHAIN_ID},
      gasPrice: 0,
      gas: 8000000,
      hardfork: "istanbul",
      accounts: ["0x${VAL1_KEY}"],
    },
VALNET
done

# Add RPC networks
for rpc in "${RPC_NODES_LIST[@]}"; do
    idx=${rpc#rpc}
    rpc_p=$((BASE_RPC_PORT + NUM_VALIDATORS * 2 + (idx - 1) * 2))
    cat >> "${PROJECT_DIR}/hardhat.config.js" << RPCNET
    quorum_${rpc}: {
      url: "http://localhost:${rpc_p}",
      chainId: ${CHAIN_ID},
      gasPrice: 0,
      gas: 8000000,
      hardfork: "istanbul",
      accounts: ["0x${VAL1_KEY}"],
    },
RPCNET
done

# Add default quorum_local pointing to validator1
cat >> "${PROJECT_DIR}/hardhat.config.js" << LOCALNET
    quorum_local: {
      url: "http://localhost:${BASE_RPC_PORT}",
      chainId: ${CHAIN_ID},
      gasPrice: 0,
      gas: 8000000,
      hardfork: "istanbul",
      accounts: ["0x${VAL1_KEY}"],
    },
  },
};
LOCALNET

# Generate network-status.sh
cat > "${PROJECT_DIR}/scripts/utils/network-status.sh" << 'STATUS_HEADER'
#!/bin/bash
GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
echo "============================================================"
echo "  Network Status"
echo "============================================================"
STATUS_HEADER

for val in "${VALIDATOR_NODES[@]}"; do
    idx=${val#validator}
    rpc_p=$((BASE_RPC_PORT + (idx - 1) * 2))
    cat >> "${PROJECT_DIR}/scripts/utils/network-status.sh" << STATUS_NODE
BLOCK=\$(curl -s -m 3 -X POST "http://localhost:${rpc_p}" --header "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' 2>/dev/null | jq -r '.result // empty' 2>/dev/null)
PEERS=\$(curl -s -m 3 -X POST "http://localhost:${rpc_p}" --header "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' 2>/dev/null | jq -r '.result // empty' 2>/dev/null)
if [ -n "\$BLOCK" ]; then echo -e "  \${GREEN}●\${NC} ${val}: Block #\$((16#\${BLOCK#0x})) | Peers: \$((16#\${PEERS#0x}))"; else echo -e "  \${RED}●\${NC} ${val}: OFFLINE"; fi
STATUS_NODE
done

for rpc in "${RPC_NODES_LIST[@]}"; do
    idx=${rpc#rpc}
    rpc_p=$((BASE_RPC_PORT + NUM_VALIDATORS * 2 + (idx - 1) * 2))
    cat >> "${PROJECT_DIR}/scripts/utils/network-status.sh" << STATUS_RPC
BLOCK=\$(curl -s -m 3 -X POST "http://localhost:${rpc_p}" --header "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' 2>/dev/null | jq -r '.result // empty' 2>/dev/null)
PEERS=\$(curl -s -m 3 -X POST "http://localhost:${rpc_p}" --header "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' 2>/dev/null | jq -r '.result // empty' 2>/dev/null)
if [ -n "\$BLOCK" ]; then echo -e "  \${GREEN}●\${NC} ${rpc}: Block #\$((16#\${BLOCK#0x})) | Peers: \$((16#\${PEERS#0x}))"; else echo -e "  \${RED}●\${NC} ${rpc}: OFFLINE"; fi
STATUS_RPC
done

cat >> "${PROJECT_DIR}/scripts/utils/network-status.sh" << 'STATUS_FOOTER'
echo ""
echo "  IBFT Validators:"
VALS=$(curl -s -X POST http://localhost:8545 --header "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"istanbul_getValidators","params":["latest"],"id":1}' 2>/dev/null | jq -r '.result[]?' 2>/dev/null)
if [ -n "$VALS" ]; then echo "$VALS" | while read -r addr; do echo -e "    ${GREEN}✓${NC} $addr"; done; else echo "    Could not fetch validators"; fi
echo "============================================================"
STATUS_FOOTER

chmod +x "${PROJECT_DIR}/scripts/utils/network-status.sh"

print_done "Configuration files saved"

# ── Start Network ───────────────────────────────────
if [ "$AUTO_START" = true ]; then
    print_step "Starting network"

    cd "${DOCKER_DIR}"
    docker compose up -d

    WAIT_TIME=$((TOTAL_NODES * 3 + 10))
    print_info "Waiting ${WAIT_TIME}s for all nodes to start and peer..."
    for i in $(seq "$WAIT_TIME" -1 1); do
        printf "\r  Countdown: %2d seconds..." "$i"
        sleep 1
    done
    echo ""

    print_step "Network Status"
    bash "${PROJECT_DIR}/scripts/utils/network-status.sh"
fi

# ── Summary ─────────────────────────────────────────
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  ${BOLD}Deployment Complete${NC}                                      ║"
echo "╠════════════════════════════════════════════════════════════╣"
echo "║                                                          ║"
echo "║  Port Map:                                               ║"

for val in "${VALIDATOR_NODES[@]}"; do
    idx=${val#validator}
    rpc_p=$((BASE_RPC_PORT + (idx - 1) * 2))
    printf "║    %-12s  RPC: %-5s  Address: %-22s║\n" "$val" "$rpc_p" "${NODE_ADDRESSES[$val]:0:22}..."
done
for rpc in "${RPC_NODES_LIST[@]}"; do
    idx=${rpc#rpc}
    rpc_p=$((BASE_RPC_PORT + NUM_VALIDATORS * 2 + (idx - 1) * 2))
    printf "║    %-12s  RPC: %-5s                                ║\n" "$rpc" "$rpc_p"
done

echo "║                                                          ║"
echo "║  Deployer Key: 0x${VAL1_KEY:0:16}...                    ║"
echo "║                                                          ║"ss

if [ "$MONITORING" = true ]; then
echo "║  Monitoring:                                             ║"
echo "║    Grafana:    http://localhost:3000  (admin/${NETWORK_NAME})     ║"
echo "║    Prometheus: http://localhost:9090                      ║"
echo "║                                                          ║"
fi

echo "║  Commands:                                               ║"
echo "║    npm run network:status                                ║"
echo "║    npm run compile                                       ║"
echo "║    npm run deploy:local                                  ║"
echo "║    npm run network:stop                                  ║"
echo "║                                                          ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""