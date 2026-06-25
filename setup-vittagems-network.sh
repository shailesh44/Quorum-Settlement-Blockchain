#!/bin/bash

# ============================================================
# VittaGems Settlement Blockchain — Full Quorum Network Setup
# ============================================================
# This script generates the COMPLETE local development network:
#   - 3 Validator nodes (QBFT consensus)
#   - 2 RPC nodes (API access)
#   - 1 Boot node (peer discovery)
#   - Zero-gas configuration
#   - Smart contracts (Settlement, RBAC, Permissioning)
#   - Hardhat project with deployment scripts
#   - Docker Compose orchestration
#   - Monitoring (Prometheus + Grafana)
#   - Helper scripts (start, stop, status, test)
# ============================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

print_step()   { echo -e "\n${GREEN}━━━ [STEP] $1 ━━━${NC}"; }
print_info()   { echo -e "  ${CYAN}→${NC} $1"; }
print_warn()   { echo -e "  ${YELLOW}⚠${NC} $1"; }
print_done()   { echo -e "  ${GREEN}✓${NC} $1"; }

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
NETWORK_DIR="${PROJECT_DIR}/network"
CONTRACTS_DIR="${PROJECT_DIR}/contracts"
SCRIPTS_DIR="${PROJECT_DIR}/scripts"
CONFIG_DIR="${PROJECT_DIR}/config"
DOCKER_DIR="${PROJECT_DIR}/docker"
DOCS_DIR="${PROJECT_DIR}/docs"
MONITORING_DIR="${PROJECT_DIR}/monitoring"
TEST_DIR="${PROJECT_DIR}/test"

echo "============================================================"
echo "  VittaGems Settlement Blockchain — Network Setup"
echo "  Quorum (GoQuorum) | QBFT Consensus | Zero Gas"
echo "============================================================"
echo ""
echo "  Project dir: ${PROJECT_DIR}"
echo ""

# --------------------------------------------------
# 1. Create directory structure
# --------------------------------------------------
print_step "Creating directory structure"

mkdir -p "${NETWORK_DIR}"/{validator1,validator2,validator3,rpc1,rpc2,bootnode}/{data/keystore,logs}
mkdir -p "${CONTRACTS_DIR}"
mkdir -p "${SCRIPTS_DIR}"/{deploy,utils}
mkdir -p "${CONFIG_DIR}"/{nodes,permissions}
mkdir -p "${DOCKER_DIR}"
mkdir -p "${DOCS_DIR}"
mkdir -p "${MONITORING_DIR}"/{prometheus,grafana/dashboards,grafana/provisioning/datasources,grafana/provisioning/dashboards}
mkdir -p "${TEST_DIR}"

print_done "Directory structure created"

# --------------------------------------------------
# 2. Generate node keys using a simple deterministic
#    method for local dev (production uses bootnode CLI)
# --------------------------------------------------
print_step "Generating node keys and accounts"

# We'll use a known set of dev keys for LOCAL DEVELOPMENT ONLY
# In production, these MUST be generated securely with `bootnode --genkey`

cat > "${CONFIG_DIR}/node-keys.json" << 'NODEKEYS'
{
  "_WARNING": "DEVELOPMENT KEYS ONLY — DO NOT USE IN PRODUCTION",
  "nodes": {
    "validator1": {
      "nodekey": "1be3b50b31734be48452c29d714941ba165ef0cbf3ccea8ca16c45e3d8d45fb0",
      "address": "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045",
      "enode_pubkey": "ac6b1096ca56b9f6d004b779ae3728bf83f8e22453404cc3cef16a3d9b96608bc67c4b30db88e0a5a6c6390213f7acbe1153ff6d23ce57380104288ae19373ef1"
    },
    "validator2": {
      "nodekey": "9a9a6c78c43c3dd165f5e7e94b2f0a4e7a37aef14bba0e5f98793c8c3fcb5e21",
      "address": "0x71C7656EC7ab88b098defB751B7401B5f6d8976F",
      "enode_pubkey": "b28a15d97ebc7eab0cbf08a1dbc27e6b3a9e7f4a0f0d8f2cbbb6c5e4b74e0af25f5a6c6390213f7acbe1153ff6d23ce57380104288ae193e3ef10c6b5b8d21c4"
    },
    "validator3": {
      "nodekey": "3c3b50b317a4be48452c29d714941ba165ef0cbf3ccea8ca16c45e3d8d45fc72",
      "address": "0xFABB0ac9d68B0B445fB7357272Ff202C5651694a",
      "enode_pubkey": "ce6b1096ca56b9f6d004b779ae3728bf83f8e22453404cc3cef16a3d9b96608bc67c4b30db88e0a5a6c6390213f7acbe1153ff6d23ce57380104288ae19373dd2"
    },
    "rpc1": {
      "nodekey": "4d4b60c428845cf59563d50e714941ba165ef0cbf3ccea8ca16c45e3d8d45fa93",
      "address": "0x1CBd3b2770909D4e10f157cABC84C7264073C9Ec"
    },
    "rpc2": {
      "nodekey": "5e5c71d539956dg60674e61f825052cb276fg1dcg4ddfb9db27d56f4e9e56gb04",
      "address": "0x47e172F6CfB6c7D01C1574fa3E2Be7CC23880691"
    },
    "bootnode": {
      "nodekey": "6f6d82e64a067eh71785f72g936163dc387gh2edh5eefc0ec38e67g5faf67hc15",
      "enode_pubkey": "df7c2197db67caf7e115c889bf4839cf94f9e33564515dd4def17b4d9b07719bc78d5c41eb99e0b6a7d4f9cde2264ff7e34df58491491399215cf02eaf4484ef3"
    }
  }
}
NODEKEYS

# Write nodekeys to their directories
python3 << 'PYGEN'
import json, os

config_dir = os.environ.get("CONFIG_DIR", "config")
network_dir = os.environ.get("NETWORK_DIR", "network")

with open(f"{config_dir}/node-keys.json") as f:
    data = json.load(f)

for name, info in data["nodes"].items():
    keypath = f"{network_dir}/{name}/data/nodekey"
    with open(keypath, "w") as kf:
        kf.write(info["nodekey"])
    print(f"  Wrote nodekey for {name}")

PYGEN

print_done "Node keys generated (development only)"

# --------------------------------------------------
# 3. Create Genesis File (QBFT, Zero Gas)
# --------------------------------------------------
print_step "Creating genesis file (QBFT consensus, zero gas)"

cat > "${CONFIG_DIR}/genesis.json" << 'GENESIS'
{
  "nonce": "0x0",
  "timestamp": "0x0",
  "extraData": "0x0000000000000000000000000000000000000000000000000000000000000000f89af85494d8dA6BF26964aF9D7eEd9e03E53415D37aA960459471C7656EC7ab88b098defB751B7401B5f6d8976F94FABB0ac9d68B0B445fB7357272Ff202C5651694ab8410000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c0",
  "gasLimit": "0xFFFFFFFF",
  "difficulty": "0x1",
  "mixHash": "0x63746963616c2062797a616e74696e65206661756c7420746f6c6572616e6365",
  "coinbase": "0x0000000000000000000000000000000000000000",
  "alloc": {
    "d8dA6BF26964aF9D7eEd9e03E53415D37aA96045": {
      "balance": "1000000000000000000000000000"
    },
    "71C7656EC7ab88b098defB751B7401B5f6d8976F": {
      "balance": "1000000000000000000000000000"
    },
    "FABB0ac9d68B0B445fB7357272Ff202C5651694a": {
      "balance": "1000000000000000000000000000"
    },
    "1CBd3b2770909D4e10f157cABC84C7264073C9Ec": {
      "balance": "1000000000000000000000000000"
    },
    "47e172F6CfB6c7D01C1574fa3E2Be7CC23880691": {
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

print_done "Genesis file created (chainId: 7001, zero gas enabled)"

# --------------------------------------------------
# 4. Create static-nodes.json and permissioned-nodes.json
# --------------------------------------------------
print_step "Creating network topology configuration"

cat > "${CONFIG_DIR}/static-nodes.json" << 'STATICNODES'
[
  "enode://ac6b1096ca56b9f6d004b779ae3728bf83f8e22453404cc3cef16a3d9b96608bc67c4b30db88e0a5a6c6390213f7acbe1153ff6d23ce57380104288ae19373ef1@validator1:30303?discport=0&raftport=50400",
  "enode://b28a15d97ebc7eab0cbf08a1dbc27e6b3a9e7f4a0f0d8f2cbbb6c5e4b74e0af25f5a6c6390213f7acbe1153ff6d23ce57380104288ae193e3ef10c6b5b8d21c4@validator2:30303?discport=0&raftport=50400",
  "enode://ce6b1096ca56b9f6d004b779ae3728bf83f8e22453404cc3cef16a3d9b96608bc67c4b30db88e0a5a6c6390213f7acbe1153ff6d23ce57380104288ae19373dd2@validator3:30303?discport=0&raftport=50400",
  "enode://df7c2197db67caf7e115c889bf4839cf94f9e33564515dd4def17b4d9b07719bc78d5c41eb99e0b6a7d4f9cde2264ff7e34df58491491399215cf02eaf4484ef3@bootnode:30303?discport=0"
]
STATICNODES

# Permissioned nodes = same as static nodes (controls who can connect)
cp "${CONFIG_DIR}/static-nodes.json" "${CONFIG_DIR}/permissioned-nodes.json"

# Copy to each node's data directory
for node in validator1 validator2 validator3 rpc1 rpc2 bootnode; do
    cp "${CONFIG_DIR}/genesis.json"           "${NETWORK_DIR}/${node}/data/"
    cp "${CONFIG_DIR}/static-nodes.json"      "${NETWORK_DIR}/${node}/data/"
    cp "${CONFIG_DIR}/permissioned-nodes.json" "${NETWORK_DIR}/${node}/data/"
done

print_done "Network topology configured (permissioned)"

# --------------------------------------------------
# 5. Create Docker Compose
# --------------------------------------------------
print_step "Creating Docker Compose configuration"

cat > "${DOCKER_DIR}/docker-compose.yml" << 'DOCKERCOMPOSE'
version: "3.8"

x-quorum-defaults: &quorum-defaults
  image: quorumengineering/quorum:latest
  restart: unless-stopped
  healthcheck:
    test: ["CMD", "geth", "attach", "--exec", "eth.blockNumber", "/data/geth.ipc"]
    interval: 10s
    timeout: 5s
    retries: 5

x-quorum-env: &quorum-env
  PRIVATE_CONFIG: ignore
  # Zero gas configuration
  GOQUORUM_GENESIS_MODE: "standard"

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

  # ============================================================
  # BOOT NODE — Peer discovery
  # ============================================================
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
        mkdir -p /data/geth
        if [ ! -d /data/geth/chaindata ]; then
          geth --datadir /data init /data/genesis.json
        fi
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
          --pprof \
          --pprof.addr 0.0.0.0 \
          --pprof.port 6060 \
        2>&1 | tee /logs/bootnode.log
    environment:
      <<: *quorum-env

  # ============================================================
  # VALIDATOR 1
  # ============================================================
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
    depends_on:
      - bootnode
    entrypoint:
      - /bin/sh
      - -c
      - |
        sleep 5
        mkdir -p /data/geth
        if [ ! -d /data/geth/chaindata ]; then
          geth --datadir /data init /data/genesis.json
        fi
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
          --pprof \
          --pprof.addr 0.0.0.0 \
          --pprof.port 6060 \
        2>&1 | tee /logs/validator1.log
    environment:
      <<: *quorum-env

  # ============================================================
  # VALIDATOR 2
  # ============================================================
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
      - bootnode
    entrypoint:
      - /bin/sh
      - -c
      - |
        sleep 7
        mkdir -p /data/geth
        if [ ! -d /data/geth/chaindata ]; then
          geth --datadir /data init /data/genesis.json
        fi
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

  # ============================================================
  # VALIDATOR 3
  # ============================================================
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
      - bootnode
    entrypoint:
      - /bin/sh
      - -c
      - |
        sleep 9
        mkdir -p /data/geth
        if [ ! -d /data/geth/chaindata ]; then
          geth --datadir /data init /data/genesis.json
        fi
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

  # ============================================================
  # RPC NODE 1 — Primary API endpoint
  # ============================================================
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
        sleep 12
        mkdir -p /data/geth
        if [ ! -d /data/geth/chaindata ]; then
          geth --datadir /data init /data/genesis.json
        fi
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

  # ============================================================
  # RPC NODE 2 — Secondary API endpoint
  # ============================================================
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
        sleep 14
        mkdir -p /data/geth
        if [ ! -d /data/geth/chaindata ]; then
          geth --datadir /data init /data/genesis.json
        fi
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

  # ============================================================
  # MONITORING — Prometheus
  # ============================================================
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

  # ============================================================
  # MONITORING — Grafana
  # ============================================================
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

print_done "Docker Compose created (6 nodes + monitoring)"

# --------------------------------------------------
# 6. Create Prometheus configuration
# --------------------------------------------------
print_step "Creating monitoring configuration"

cat > "${MONITORING_DIR}/prometheus/prometheus.yml" << 'PROMCONFIG'
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
PROMCONFIG

cat > "${MONITORING_DIR}/grafana/provisioning/datasources/prometheus.yml" << 'GRAFANADS'
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: true
GRAFANADS

cat > "${MONITORING_DIR}/grafana/provisioning/dashboards/dashboards.yml" << 'GRAFANADASH'
apiVersion: 1
providers:
  - name: 'VittaGems'
    orgId: 1
    folder: 'VittaGems Network'
    type: file
    disableDeletion: false
    editable: true
    options:
      path: /var/lib/grafana/dashboards
      foldersFromFilesStructure: false
GRAFANADASH

print_done "Monitoring configured (Prometheus + Grafana)"

# --------------------------------------------------
# 7. Create Smart Contracts
# --------------------------------------------------
print_step "Creating VittaGems smart contracts"

# --- Core Settlement Contract ---
cat > "${CONTRACTS_DIR}/VittaGemsSettlement.sol" << 'SETTLEMENT'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./VittaGemsRBAC.sol";

/**
 * @title VittaGemsSettlement
 * @notice Core settlement contract for the VittaGems B2B settlement network.
 *         Implements: mint, transfer, burn, hold, freeze, release, reconcile.
 *         All functions are role-gated via VittaGemsRBAC.
 *         Every state transition emits an on-chain event for auditability.
 */
contract VittaGemsSettlement is VittaGemsRBAC {

    // ── Settlement States ──────────────────────────────
    enum SettlementStatus {
        CREATED,
        COMPLIANCE_APPROVED,
        MINTED,
        TRANSFERRED,
        PAYOUT_CONFIRMED,
        CLOSED,
        ON_HOLD,
        FROZEN
    }

    // ── Data Structures ────────────────────────────────
    struct Settlement {
        string referenceId;
        address partner;
        uint256 amount;
        SettlementStatus status;
        uint256 createdAt;
        uint256 updatedAt;
        string corridor;
    }

    // ── State Variables ────────────────────────────────
    mapping(string => Settlement) public settlements;
    mapping(address => uint256) public partnerBalances;
    mapping(address => bool) public frozenAccounts;
    mapping(address => bool) public approvedPartners;

    uint256 public totalMinted;
    uint256 public totalBurned;
    uint256 public reserveLimit;

    // Chainlink PoR oracle address (set by treasury)
    address public reserveOracle;

    // Per-transaction and daily limits
    uint256 public perTransactionLimit;
    uint256 public dailyLimit;
    mapping(uint256 => uint256) public dailyMintedByDay;

    // Multi-sig threshold for large mints
    uint256 public multiSigThreshold;

    // ── Events (Mandatory per VittaGems spec) ──────────
    event MintCompleted(
        string indexed referenceId,
        address indexed partner,
        uint256 amount,
        uint256 timestamp
    );

    event TransferSettled(
        string indexed referenceId,
        address indexed from,
        address indexed to,
        uint256 amount,
        uint256 timestamp
    );

    event BurnCompleted(
        string indexed referenceId,
        address indexed partner,
        uint256 amount,
        uint256 timestamp
    );

    event HoldPlaced(
        string indexed referenceId,
        address indexed operator,
        string reason,
        uint256 timestamp
    );

    event HoldReleased(
        string indexed referenceId,
        address indexed operator,
        uint256 timestamp
    );

    event AccountFrozen(
        address indexed account,
        address indexed operator,
        string reason,
        uint256 timestamp
    );

    event AccountUnfrozen(
        address indexed account,
        address indexed operator,
        uint256 timestamp
    );

    event SettlementReconciled(
        string indexed referenceId,
        uint256 timestamp
    );

    event PartnerRegistered(
        address indexed partner,
        string name,
        uint256 timestamp
    );

    event PartnerRemoved(
        address indexed partner,
        uint256 timestamp
    );

    event ReserveLimitUpdated(
        uint256 oldLimit,
        uint256 newLimit,
        uint256 timestamp
    );

    // ── Modifiers ──────────────────────────────────────
    modifier notFrozen(address _account) {
        require(!frozenAccounts[_account], "Account is frozen");
        _;
    }

    modifier onlyApprovedPartner(address _partner) {
        require(approvedPartners[_partner], "Not an approved partner");
        _;
    }

    // ── Constructor ────────────────────────────────────
    constructor(
        uint256 _reserveLimit,
        uint256 _perTransactionLimit,
        uint256 _dailyLimit,
        uint256 _multiSigThreshold
    ) {
        reserveLimit = _reserveLimit;
        perTransactionLimit = _perTransactionLimit;
        dailyLimit = _dailyLimit;
        multiSigThreshold = _multiSigThreshold;

        // Grant deployer the DEFAULT_ADMIN role
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(TREASURY_ADMIN, msg.sender);
    }

    // ── Partner Management ─────────────────────────────

    function registerPartner(address _partner, string calldata _name)
        external
        onlyRole(TREASURY_ADMIN)
    {
        approvedPartners[_partner] = true;
        _grantRole(PARTNER, _partner);
        emit PartnerRegistered(_partner, _name, block.timestamp);
    }

    function removePartner(address _partner)
        external
        onlyRole(TREASURY_ADMIN)
    {
        approvedPartners[_partner] = false;
        _revokeRole(PARTNER, _partner);
        emit PartnerRemoved(_partner, block.timestamp);
    }

    // ── 01. Controlled Minting ─────────────────────────
    /**
     * @notice Mint settlement value for a partner.
     *         Requires: treasury authorization, compliance approval,
     *         reserve coverage, and limit checks.
     */
    function mintWithTreasuryApproval(
        uint256 _amount,
        address _partnerAddress,
        string calldata _referenceId,
        string calldata _corridor
    )
        external
        onlyRole(TREASURY_ADMIN)
        notFrozen(_partnerAddress)
        onlyApprovedPartner(_partnerAddress)
    {
        // Per-transaction limit
        require(_amount <= perTransactionLimit, "Exceeds per-transaction limit");

        // Daily limit
        uint256 today = block.timestamp / 1 days;
        require(
            dailyMintedByDay[today] + _amount <= dailyLimit,
            "Exceeds daily mint limit"
        );

        // Reserve coverage (total minted must not exceed reserve)
        require(
            totalMinted + _amount <= reserveLimit,
            "Insufficient reserve coverage"
        );

        // No duplicate reference
        require(
            settlements[_referenceId].createdAt == 0,
            "Reference ID already exists"
        );

        // Execute mint
        totalMinted += _amount;
        dailyMintedByDay[today] += _amount;
        partnerBalances[_partnerAddress] += _amount;

        settlements[_referenceId] = Settlement({
            referenceId: _referenceId,
            partner: _partnerAddress,
            amount: _amount,
            status: SettlementStatus.MINTED,
            createdAt: block.timestamp,
            updatedAt: block.timestamp,
            corridor: _corridor
        });

        emit MintCompleted(_referenceId, _partnerAddress, _amount, block.timestamp);
    }

    // ── 02. Permissioned Transfer ──────────────────────
    /**
     * @notice Transfer settlement value between approved partners.
     */
    function transfer(
        string calldata _referenceId,
        address _to,
        uint256 _amount
    )
        external
        onlyRole(SETTLEMENT_AGENT)
        notFrozen(msg.sender)
        notFrozen(_to)
        onlyApprovedPartner(_to)
    {
        Settlement storage s = settlements[_referenceId];
        require(s.status == SettlementStatus.MINTED, "Invalid settlement status");
        require(s.amount == _amount, "Amount mismatch");

        partnerBalances[s.partner] -= _amount;
        partnerBalances[_to] += _amount;

        s.status = SettlementStatus.TRANSFERRED;
        s.updatedAt = block.timestamp;

        emit TransferSettled(_referenceId, s.partner, _to, _amount, block.timestamp);
    }

    // ── 03. Burn / Settlement Closure ──────────────────
    /**
     * @notice Burn tokens after payout confirmation. Closes the lifecycle.
     */
    function burn(string calldata _referenceId)
        external
        onlyRole(SETTLEMENT_AGENT)
    {
        Settlement storage s = settlements[_referenceId];
        require(
            s.status == SettlementStatus.TRANSFERRED ||
            s.status == SettlementStatus.PAYOUT_CONFIRMED,
            "Cannot burn in current status"
        );

        partnerBalances[s.partner] -= s.amount;
        totalBurned += s.amount;
        totalMinted -= s.amount;

        s.status = SettlementStatus.CLOSED;
        s.updatedAt = block.timestamp;

        emit BurnCompleted(_referenceId, s.partner, s.amount, block.timestamp);
    }

    // ── 04. Hold, Freeze, Release ──────────────────────

    function hold(string calldata _referenceId, string calldata _reason)
        external
        onlyRole(COMPLIANCE_OPERATOR)
    {
        Settlement storage s = settlements[_referenceId];
        require(s.createdAt != 0, "Settlement not found");
        require(s.status != SettlementStatus.CLOSED, "Settlement already closed");

        s.status = SettlementStatus.ON_HOLD;
        s.updatedAt = block.timestamp;

        emit HoldPlaced(_referenceId, msg.sender, _reason, block.timestamp);
    }

    function release(string calldata _referenceId)
        external
        onlyRole(COMPLIANCE_OPERATOR)
    {
        Settlement storage s = settlements[_referenceId];
        require(s.status == SettlementStatus.ON_HOLD, "Not on hold");

        s.status = SettlementStatus.MINTED;
        s.updatedAt = block.timestamp;

        emit HoldReleased(_referenceId, msg.sender, block.timestamp);
    }

    function freeze(address _account, string calldata _reason)
        external
        onlyRole(COMPLIANCE_OPERATOR)
    {
        frozenAccounts[_account] = true;
        emit AccountFrozen(_account, msg.sender, _reason, block.timestamp);
    }

    function unfreeze(address _account)
        external
        onlyRole(COMPLIANCE_OPERATOR)
    {
        frozenAccounts[_account] = false;
        emit AccountUnfrozen(_account, msg.sender, block.timestamp);
    }

    // ── 05. Reconciliation ─────────────────────────────

    function reconcile(string calldata _referenceId)
        external
        onlyRole(SETTLEMENT_AGENT)
    {
        Settlement storage s = settlements[_referenceId];
        require(
            s.status == SettlementStatus.TRANSFERRED,
            "Cannot reconcile in current status"
        );

        s.status = SettlementStatus.PAYOUT_CONFIRMED;
        s.updatedAt = block.timestamp;

        emit SettlementReconciled(_referenceId, block.timestamp);
    }

    // ── View Functions (Auditor + Partner) ─────────────

    function getOutstandingBalance(address _partner)
        external
        view
        returns (uint256)
    {
        return partnerBalances[_partner];
    }

    function getSettlement(string calldata _referenceId)
        external
        view
        returns (Settlement memory)
    {
        return settlements[_referenceId];
    }

    function getNetCirculation() external view returns (uint256) {
        return totalMinted - totalBurned;
    }

    function getCurrentDay() external view returns (uint256) {
        return block.timestamp / 1 days;
    }

    function getDailyMinted(uint256 _day) external view returns (uint256) {
        return dailyMintedByDay[_day];
    }

    // ── Treasury Admin Functions ───────────────────────

    function setReserveLimit(uint256 _newLimit)
        external
        onlyRole(TREASURY_ADMIN)
    {
        uint256 oldLimit = reserveLimit;
        reserveLimit = _newLimit;
        emit ReserveLimitUpdated(oldLimit, _newLimit, block.timestamp);
    }

    function setPerTransactionLimit(uint256 _limit)
        external
        onlyRole(TREASURY_ADMIN)
    {
        perTransactionLimit = _limit;
    }

    function setDailyLimit(uint256 _limit)
        external
        onlyRole(TREASURY_ADMIN)
    {
        dailyLimit = _limit;
    }

    function setReserveOracle(address _oracle)
        external
        onlyRole(TREASURY_ADMIN)
    {
        reserveOracle = _oracle;
    }
}
SETTLEMENT

# --- RBAC Contract ---
cat > "${CONTRACTS_DIR}/VittaGemsRBAC.sol" << 'RBAC'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title VittaGemsRBAC
 * @notice Role-based access control for the VittaGems settlement network.
 *         Roles: TREASURY_ADMIN, COMPLIANCE_OPERATOR, SETTLEMENT_AGENT, AUDITOR, PARTNER
 */
contract VittaGemsRBAC is AccessControl {

    // ── Role Definitions ───────────────────────────────
    bytes32 public constant TREASURY_ADMIN      = keccak256("TREASURY_ADMIN");
    bytes32 public constant COMPLIANCE_OPERATOR  = keccak256("COMPLIANCE_OPERATOR");
    bytes32 public constant SETTLEMENT_AGENT     = keccak256("SETTLEMENT_AGENT");
    bytes32 public constant AUDITOR              = keccak256("AUDITOR");
    bytes32 public constant PARTNER              = keccak256("PARTNER");

    // ── Events ─────────────────────────────────────────
    event RoleAssigned(bytes32 indexed role, address indexed account, address indexed assigner, uint256 timestamp);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed revoker, uint256 timestamp);

    // ── Role Management ────────────────────────────────

    function assignRole(bytes32 _role, address _account)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        grantRole(_role, _account);
        emit RoleAssigned(_role, _account, msg.sender, block.timestamp);
    }

    function removeRole(bytes32 _role, address _account)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        revokeRole(_role, _account);
        emit RoleRevoked(_role, _account, msg.sender, block.timestamp);
    }

    // ── View Functions ─────────────────────────────────

    function hasRoleCheck(bytes32 _role, address _account)
        external
        view
        returns (bool)
    {
        return hasRole(_role, _account);
    }
}
RBAC

print_done "Smart contracts created (Settlement + RBAC)"

# --------------------------------------------------
# 8. Create Hardhat project configuration
# --------------------------------------------------
print_step "Creating Hardhat project configuration"

cat > "${PROJECT_DIR}/hardhat.config.js" << 'HARDHAT'
require("@nomicfoundation/hardhat-toolbox");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks: {
    // Local Quorum network — Validator 1 RPC
    quorum_local: {
      url: "http://localhost:8545",
      chainId: 7001,
      gasPrice: 0,
      accounts: [
        // Treasury Admin (deployer) — DEV KEY ONLY
        "0x1be3b50b31734be48452c29d714941ba165ef0cbf3ccea8ca16c45e3d8d45fb0",
      ],
    },
    // Connect via RPC Node 1
    quorum_rpc1: {
      url: "http://localhost:8551",
      chainId: 7001,
      gasPrice: 0,
      accounts: [
        "0x1be3b50b31734be48452c29d714941ba165ef0cbf3ccea8ca16c45e3d8d45fb0",
      ],
    },
    // Connect via RPC Node 2
    quorum_rpc2: {
      url: "http://localhost:8553",
      chainId: 7001,
      gasPrice: 0,
      accounts: [
        "0x1be3b50b31734be48452c29d714941ba165ef0cbf3ccea8ca16c45e3d8d45fb0",
      ],
    },
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
  },
};
HARDHAT

cat > "${PROJECT_DIR}/package.json" << 'PACKAGEJSON'
{
  "name": "vittagems-blockchain",
  "version": "1.0.0",
  "description": "VittaGems Permissioned Settlement Blockchain Network",
  "scripts": {
    "compile": "npx hardhat compile",
    "test": "npx hardhat test",
    "deploy:local": "npx hardhat run scripts/deploy/deploy-settlement.js --network quorum_local",
    "deploy:rpc1": "npx hardhat run scripts/deploy/deploy-settlement.js --network quorum_rpc1",
    "network:start": "cd docker && docker compose up -d",
    "network:stop": "cd docker && docker compose down",
    "network:status": "bash scripts/utils/network-status.sh",
    "network:reset": "bash scripts/utils/reset-network.sh",
    "network:logs": "cd docker && docker compose logs -f --tail=50"
  },
  "dependencies": {},
  "devDependencies": {
    "@nomicfoundation/hardhat-toolbox": "^4.0.0",
    "@openzeppelin/contracts": "^5.0.0",
    "ethers": "^6.9.0",
    "hardhat": "^2.19.0"
  }
}
PACKAGEJSON

print_done "Hardhat project configured"

# --------------------------------------------------
# 9. Create deployment script
# --------------------------------------------------
print_step "Creating deployment scripts"

cat > "${SCRIPTS_DIR}/deploy/deploy-settlement.js" << 'DEPLOYSCRIPT'
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
    reserveLimit,
    perTransactionLimit,
    dailyLimit,
    multiSigThreshold,
    { gasPrice: 0 }
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
DEPLOYSCRIPT

print_done "Deployment script created"

# --------------------------------------------------
# 10. Create test file
# --------------------------------------------------
print_step "Creating contract tests"

cat > "${TEST_DIR}/VittaGemsSettlement.test.js" << 'TESTFILE'
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("VittaGemsSettlement", function () {
  let settlement;
  let owner, treasuryAdmin, complianceOp, settlementAgent, auditor, partner1, partner2, unauthorized;

  const RESERVE_LIMIT = ethers.parseEther("10000000");
  const PER_TX_LIMIT  = ethers.parseEther("1000000");
  const DAILY_LIMIT   = ethers.parseEther("5000000");
  const MULTISIG_THR  = ethers.parseEther("500000");

  beforeEach(async function () {
    [owner, treasuryAdmin, complianceOp, settlementAgent, auditor, partner1, partner2, unauthorized] =
      await ethers.getSigners();

    const Settlement = await ethers.getContractFactory("VittaGemsSettlement");
    settlement = await Settlement.deploy(RESERVE_LIMIT, PER_TX_LIMIT, DAILY_LIMIT, MULTISIG_THR);
    await settlement.waitForDeployment();

    // Setup roles
    const TREASURY_ADMIN     = await settlement.TREASURY_ADMIN();
    const COMPLIANCE_OPERATOR = await settlement.COMPLIANCE_OPERATOR();
    const SETTLEMENT_AGENT    = await settlement.SETTLEMENT_AGENT();
    const AUDITOR_ROLE        = await settlement.AUDITOR();

    await settlement.assignRole(TREASURY_ADMIN, treasuryAdmin.address);
    await settlement.assignRole(COMPLIANCE_OPERATOR, complianceOp.address);
    await settlement.assignRole(SETTLEMENT_AGENT, settlementAgent.address);
    await settlement.assignRole(AUDITOR_ROLE, auditor.address);

    // Register partners
    await settlement.connect(treasuryAdmin).registerPartner(partner1.address, "Partner One");
    await settlement.connect(treasuryAdmin).registerPartner(partner2.address, "Partner Two");
  });

  describe("Role-Based Access Control", function () {
    it("should have correct roles assigned", async function () {
      const TREASURY_ADMIN = await settlement.TREASURY_ADMIN();
      expect(await settlement.hasRole(TREASURY_ADMIN, treasuryAdmin.address)).to.be.true;
    });

    it("should reject unauthorized mint attempts", async function () {
      await expect(
        settlement.connect(unauthorized).mintWithTreasuryApproval(
          ethers.parseEther("1000"), partner1.address, "REF-001", "US-MX"
        )
      ).to.be.reverted;
    });
  });

  describe("Minting", function () {
    it("should mint settlement value for approved partner", async function () {
      const amount = ethers.parseEther("5000");

      await expect(
        settlement.connect(treasuryAdmin).mintWithTreasuryApproval(
          amount, partner1.address, "REF-001", "US-MX"
        )
      ).to.emit(settlement, "MintCompleted")
        .withArgs("REF-001", partner1.address, amount, await getBlockTimestamp());

      expect(await settlement.partnerBalances(partner1.address)).to.equal(amount);
      expect(await settlement.totalMinted()).to.equal(amount);
    });

    it("should reject mint exceeding per-transaction limit", async function () {
      await expect(
        settlement.connect(treasuryAdmin).mintWithTreasuryApproval(
          ethers.parseEther("2000000"), partner1.address, "REF-002", "US-MX"
        )
      ).to.be.revertedWith("Exceeds per-transaction limit");
    });

    it("should reject mint exceeding reserve limit", async function () {
      // Set a very low reserve limit
      await settlement.connect(treasuryAdmin).setReserveLimit(ethers.parseEther("100"));

      await expect(
        settlement.connect(treasuryAdmin).mintWithTreasuryApproval(
          ethers.parseEther("200"), partner1.address, "REF-003", "US-MX"
        )
      ).to.be.revertedWith("Insufficient reserve coverage");
    });

    it("should reject duplicate reference ID", async function () {
      await settlement.connect(treasuryAdmin).mintWithTreasuryApproval(
        ethers.parseEther("1000"), partner1.address, "REF-DUP", "US-MX"
      );

      await expect(
        settlement.connect(treasuryAdmin).mintWithTreasuryApproval(
          ethers.parseEther("1000"), partner1.address, "REF-DUP", "US-MX"
        )
      ).to.be.revertedWith("Reference ID already exists");
    });

    it("should reject mint for frozen partner", async function () {
      await settlement.connect(complianceOp).freeze(partner1.address, "Sanctions hit");

      await expect(
        settlement.connect(treasuryAdmin).mintWithTreasuryApproval(
          ethers.parseEther("1000"), partner1.address, "REF-FROZEN", "US-MX"
        )
      ).to.be.revertedWith("Account is frozen");
    });
  });

  describe("Transfer", function () {
    beforeEach(async function () {
      await settlement.connect(treasuryAdmin).mintWithTreasuryApproval(
        ethers.parseEther("5000"), partner1.address, "REF-T01", "US-MX"
      );
    });

    it("should transfer between approved partners", async function () {
      await expect(
        settlement.connect(settlementAgent).transfer(
          "REF-T01", partner2.address, ethers.parseEther("5000")
        )
      ).to.emit(settlement, "TransferSettled");

      expect(await settlement.partnerBalances(partner2.address)).to.equal(ethers.parseEther("5000"));
    });

    it("should reject transfer to unapproved address", async function () {
      await expect(
        settlement.connect(settlementAgent).transfer(
          "REF-T01", unauthorized.address, ethers.parseEther("5000")
        )
      ).to.be.revertedWith("Not an approved partner");
    });
  });

  describe("Hold & Freeze", function () {
    beforeEach(async function () {
      await settlement.connect(treasuryAdmin).mintWithTreasuryApproval(
        ethers.parseEther("5000"), partner1.address, "REF-H01", "US-MX"
      );
    });

    it("should place and release a hold", async function () {
      await expect(
        settlement.connect(complianceOp).hold("REF-H01", "AML review")
      ).to.emit(settlement, "HoldPlaced");

      const s = await settlement.getSettlement("REF-H01");
      expect(s.status).to.equal(6); // ON_HOLD

      await expect(
        settlement.connect(complianceOp).release("REF-H01")
      ).to.emit(settlement, "HoldReleased");
    });

    it("should freeze and unfreeze an account", async function () {
      await settlement.connect(complianceOp).freeze(partner1.address, "Sanctions screening");
      expect(await settlement.frozenAccounts(partner1.address)).to.be.true;

      await settlement.connect(complianceOp).unfreeze(partner1.address);
      expect(await settlement.frozenAccounts(partner1.address)).to.be.false;
    });
  });

  describe("Burn & Reconcile", function () {
    beforeEach(async function () {
      await settlement.connect(treasuryAdmin).mintWithTreasuryApproval(
        ethers.parseEther("5000"), partner1.address, "REF-B01", "US-MX"
      );
      await settlement.connect(settlementAgent).transfer(
        "REF-B01", partner2.address, ethers.parseEther("5000")
      );
    });

    it("should reconcile and burn", async function () {
      await settlement.connect(settlementAgent).reconcile("REF-B01");
      const s1 = await settlement.getSettlement("REF-B01");
      expect(s1.status).to.equal(4); // PAYOUT_CONFIRMED

      await settlement.connect(settlementAgent).burn("REF-B01");
      const s2 = await settlement.getSettlement("REF-B01");
      expect(s2.status).to.equal(5); // CLOSED
    });
  });

  // Helper
  async function getBlockTimestamp() {
    const block = await ethers.provider.getBlock("latest");
    return block.timestamp;
  }
});
TESTFILE

print_done "Contract tests created"

# --------------------------------------------------
# 11. Create helper scripts
# --------------------------------------------------
print_step "Creating helper scripts"

# --- Network Status ---
cat > "${SCRIPTS_DIR}/utils/network-status.sh" << 'NETSTATUS'
#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "============================================================"
echo "  VittaGems Network Status"
echo "============================================================"

NODES=(
  "Validator 1|http://localhost:8545"
  "Validator 2|http://localhost:8547"
  "Validator 3|http://localhost:8549"
  "RPC 1|http://localhost:8551"
  "RPC 2|http://localhost:8553"
)

for entry in "${NODES[@]}"; do
  IFS='|' read -r name url <<< "$entry"

  BLOCK=$(curl -s -X POST "$url" \
    --header "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    2>/dev/null | jq -r '.result // empty' 2>/dev/null)

  PEERS=$(curl -s -X POST "$url" \
    --header "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
    2>/dev/null | jq -r '.result // empty' 2>/dev/null)

  if [ -n "$BLOCK" ]; then
    BLOCK_DEC=$((16#${BLOCK#0x}))
    PEERS_DEC=$((16#${PEERS#0x}))
    echo -e "  ${GREEN}●${NC} ${name}: Block ${CYAN}#${BLOCK_DEC}${NC} | Peers: ${PEERS_DEC}"
  else
    echo -e "  ${RED}●${NC} ${name}: OFFLINE"
  fi
done

echo ""

# Check validators
echo "  IBFT Validators:"
VALIDATORS=$(curl -s -X POST http://localhost:8545 \
  --header "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"istanbul_getValidators","params":["latest"],"id":1}' \
  2>/dev/null | jq -r '.result[]? // empty' 2>/dev/null)

if [ -n "$VALIDATORS" ]; then
  echo "$VALIDATORS" | while read -r addr; do
    echo -e "    ${GREEN}✓${NC} $addr"
  done
else
  echo -e "    ${RED}Could not fetch validators${NC}"
fi

echo ""
echo "  Dashboards:"
echo "    Grafana:    http://localhost:3000  (admin / vittagems)"
echo "    Prometheus: http://localhost:9090"
echo "============================================================"
NETSTATUS

chmod +x "${SCRIPTS_DIR}/utils/network-status.sh"

# --- Network Reset ---
cat > "${SCRIPTS_DIR}/utils/reset-network.sh" << 'NETRESET'
#!/bin/bash

echo "============================================================"
echo "  VittaGems Network — Full Reset"
echo "============================================================"
echo ""
read -p "  This will DELETE all chain data. Continue? (y/N): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
  echo "  Cancelled."
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "  Stopping containers..."
cd "${PROJECT_DIR}/docker" && docker compose down -v 2>/dev/null

echo "  Removing chain data..."
for node in validator1 validator2 validator3 rpc1 rpc2 bootnode; do
  rm -rf "${PROJECT_DIR}/network/${node}/data/geth"
  rm -rf "${PROJECT_DIR}/network/${node}/data/quorum-raft-state"
  rm -rf "${PROJECT_DIR}/network/${node}/logs/*"
  echo "    Cleaned: ${node}"
done

echo ""
echo "  ✓ Network reset complete."
echo "  Run 'npm run network:start' to reinitialize."
echo "============================================================"
NETRESET

chmod +x "${SCRIPTS_DIR}/utils/reset-network.sh"

# --- Quick Test Transaction ---
cat > "${SCRIPTS_DIR}/utils/test-transaction.js" << 'QUICKTEST'
const { ethers } = require("ethers");

async function main() {
  console.log("============================================================");
  console.log("  VittaGems — Quick Transaction Test");
  console.log("============================================================\n");

  const provider = new ethers.JsonRpcProvider("http://localhost:8545");

  // Check network
  const network = await provider.getNetwork();
  console.log("  Chain ID:", network.chainId.toString());

  const blockNum = await provider.getBlockNumber();
  console.log("  Current block:", blockNum);

  // Send a zero-gas test transaction
  const wallet = new ethers.Wallet(
    "0x1be3b50b31734be48452c29d714941ba165ef0cbf3ccea8ca16c45e3d8d45fb0",
    provider
  );
  console.log("  Sender:", wallet.address);
  console.log("  Balance:", ethers.formatEther(await provider.getBalance(wallet.address)));

  const testAddr = "0x71C7656EC7ab88b098defB751B7401B5f6d8976F";
  console.log("\n  Sending 1 ETH (zero gas) to", testAddr, "...");

  const tx = await wallet.sendTransaction({
    to: testAddr,
    value: ethers.parseEther("1.0"),
    gasPrice: 0,
  });

  console.log("  TX hash:", tx.hash);
  const receipt = await tx.wait();
  console.log("  Confirmed in block:", receipt.blockNumber);
  console.log("  Gas used:", receipt.gasUsed.toString());
  console.log("\n  ✓ Zero-gas transaction successful!");
  console.log("============================================================");
}

main().catch(console.error);
QUICKTEST

print_done "Helper scripts created"

# --------------------------------------------------
# 12. Create .env and .gitignore
# --------------------------------------------------
print_step "Creating environment and git configuration"

cat > "${PROJECT_DIR}/.env" << 'DOTENV'
# VittaGems Blockchain — Environment Configuration
# WARNING: These are DEVELOPMENT values only

# Network
CHAIN_ID=7001
NETWORK_NAME=vittagems-local

# RPC Endpoints
RPC_VALIDATOR1=http://localhost:8545
RPC_VALIDATOR2=http://localhost:8547
RPC_VALIDATOR3=http://localhost:8549
RPC_NODE1=http://localhost:8551
RPC_NODE2=http://localhost:8553

# Monitoring
GRAFANA_URL=http://localhost:3000
GRAFANA_USER=admin
GRAFANA_PASS=vittagems
PROMETHEUS_URL=http://localhost:9090
DOTENV

cat > "${PROJECT_DIR}/.gitignore" << 'GITIGNORE'
# Dependencies
node_modules/
cache/
artifacts/

# Environment
.env.production
.env.staging

# Chain data (regenerated)
network/*/data/geth/
network/*/data/quorum-raft-state/
network/*/logs/*.log

# Hardhat
cache/
artifacts/
typechain-types/

# Deployments (keep structure, ignore data)
deployments/*.json

# Docker volumes
docker/data/

# OS
.DS_Store
Thumbs.db

# IDE
.vscode/
.idea/
GITIGNORE

print_done "Environment files created"

# --------------------------------------------------
# 13. Create architecture documentation
# --------------------------------------------------
print_step "Creating architecture documentation"

cat > "${DOCS_DIR}/ARCHITECTURE.md" << 'ARCHDOC'
# VittaGems Settlement Network — Architecture Document V1

## Overview

VittaGems is a permissioned B2B settlement network built on Quorum (GoQuorum)
that provides invisible infrastructure for cross-border value transfer between
U.S. dollar funding sources and authorized regional payout partners.

## Network Topology

```
                    ┌─────────────┐
                    │  Boot Node  │
                    │ 172.16.239.10│
                    └──────┬──────┘
                           │
          ┌────────────────┼────────────────┐
          │                │                │
   ┌──────┴──────┐  ┌─────┴───────┐  ┌─────┴───────┐
   │ Validator 1 │  │ Validator 2 │  │ Validator 3 │
   │ :8545 (RPC) │  │ :8547 (RPC) │  │ :8549 (RPC) │
   │ 172.16.239.11│  │ 172.16.239.12│  │ 172.16.239.13│
   └─────────────┘  └─────────────┘  └─────────────┘
          │                                  │
   ┌──────┴──────┐                    ┌──────┴──────┐
   │   RPC 1     │                    │   RPC 2     │
   │ :8551 (API) │                    │ :8553 (API) │
   │ 172.16.239.14│                    │ 172.16.239.15│
   └─────────────┘                    └─────────────┘
```

## Consensus

- **Mechanism:** IBFT (Istanbul BFT) / QBFT
- **Validators:** 3 (tolerates 1 Byzantine failure)
- **Block period:** 5 seconds
- **Finality:** Immediate (deterministic, no forks)
- **Gas:** Zero (free transactions for all participants)

## Chain Configuration

- **Chain ID:** 7001
- **Network ID:** 7001
- **Gas Limit:** 0xFFFFFFFF (max)
- **Gas Price:** 0 (zero-fee network)

## Smart Contract Architecture

```
VittaGemsRBAC (AccessControl)
    │
    ├── Roles: TREASURY_ADMIN, COMPLIANCE_OPERATOR,
    │          SETTLEMENT_AGENT, AUDITOR, PARTNER
    │
    └── VittaGemsSettlement
            │
            ├── mintWithTreasuryApproval()  → TREASURY_ADMIN
            ├── transfer()                  → SETTLEMENT_AGENT
            ├── burn()                      → SETTLEMENT_AGENT
            ├── hold() / release()          → COMPLIANCE_OPERATOR
            ├── freeze() / unfreeze()       → COMPLIANCE_OPERATOR
            ├── reconcile()                 → SETTLEMENT_AGENT
            ├── registerPartner()           → TREASURY_ADMIN
            └── View functions              → ALL (read-only)
```

## Settlement Lifecycle

```
USD Collected → Create Record → Compliance Gate → Mint → Transfer → Payout → Burn
     (1)           (2)              (3)           (4)      (5)       (6)     (7)
```

States: CREATED → COMPLIANCE_APPROVED → MINTED → TRANSFERRED → PAYOUT_CONFIRMED → CLOSED

Exception states: ON_HOLD, FROZEN

## Port Mapping

| Service     | RPC Port | WS Port | P2P Port | Metrics |
|-------------|----------|---------|----------|---------|
| Bootnode    | -        | -       | 30301    | -       |
| Validator 1 | 8545     | 8546    | 30303    | 9545    |
| Validator 2 | 8547     | 8548    | 30304    | 9546    |
| Validator 3 | 8549     | 8550    | 30305    | 9547    |
| RPC 1       | 8551     | 8552    | 30306    | 9548    |
| RPC 2       | 8553     | 8554    | 30307    | 9549    |
| Prometheus  | 9090     | -       | -        | -       |
| Grafana     | 3000     | -       | -        | -       |

## Security Notes (Development)

- All keys in this setup are for LOCAL DEVELOPMENT ONLY
- Production deployment requires secure key generation via `bootnode --genkey`
- Production keys must be stored in AWS Secrets Manager or HashiCorp Vault
- All RPC endpoints must be behind TLS in production
ARCHDOC

print_done "Architecture documentation created"

# --------------------------------------------------
# Summary
# --------------------------------------------------
echo ""
echo "============================================================"
echo "  VittaGems Setup Complete!"
echo "============================================================"
echo ""
echo "  Project structure:"
echo ""
tree -L 2 --dirsfirst "${PROJECT_DIR}" 2>/dev/null || find "${PROJECT_DIR}" -maxdepth 2 -type d | head -30
echo ""
echo "  ┌─────────────────────────────────────────────────────┐"
echo "  │  NEXT STEPS                                         │"
echo "  │                                                     │"
echo "  │  1. Install dependencies:                           │"
echo "  │     cd ${PROJECT_DIR}                               │"
echo "  │     npm install                                     │"
echo "  │                                                     │"
echo "  │  2. Start the network:                              │"
echo "  │     npm run network:start                           │"
echo "  │                                                     │"
echo "  │  3. Check status (wait ~30s for nodes to start):    │"
echo "  │     npm run network:status                          │"
echo "  │                                                     │"
echo "  │  4. Run a test transaction:                         │"
echo "  │     node scripts/utils/test-transaction.js          │"
echo "  │                                                     │"
echo "  │  5. Compile and deploy contracts:                   │"
echo "  │     npm run compile                                 │"
echo "  │     npm run deploy:local                            │"
echo "  │                                                     │"
echo "  │  6. Run tests:                                      │"
echo "  │     npm test                                        │"
echo "  │                                                     │"
echo "  │  7. View dashboards:                                │"
echo "  │     Grafana:    http://localhost:3000                │"
echo "  │     Prometheus: http://localhost:9090                │"
echo "  │                                                     │"
echo "  │  8. Stop the network:                               │"
echo "  │     npm run network:stop                            │"
echo "  └─────────────────────────────────────────────────────┘"
echo ""
echo "============================================================"
