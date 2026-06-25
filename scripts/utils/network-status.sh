#!/bin/bash
GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
echo "============================================================"
echo "  Network Status"
echo "============================================================"
BLOCK=$(curl -s -m 3 -X POST "http://localhost:8545" --header "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' 2>/dev/null | jq -r '.result // empty' 2>/dev/null)
PEERS=$(curl -s -m 3 -X POST "http://localhost:8545" --header "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' 2>/dev/null | jq -r '.result // empty' 2>/dev/null)
if [ -n "$BLOCK" ]; then echo -e "  ${GREEN}●${NC} validator1: Block #$((16#${BLOCK#0x})) | Peers: $((16#${PEERS#0x}))"; else echo -e "  ${RED}●${NC} validator1: OFFLINE"; fi
BLOCK=$(curl -s -m 3 -X POST "http://localhost:8547" --header "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' 2>/dev/null | jq -r '.result // empty' 2>/dev/null)
PEERS=$(curl -s -m 3 -X POST "http://localhost:8547" --header "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' 2>/dev/null | jq -r '.result // empty' 2>/dev/null)
if [ -n "$BLOCK" ]; then echo -e "  ${GREEN}●${NC} validator2: Block #$((16#${BLOCK#0x})) | Peers: $((16#${PEERS#0x}))"; else echo -e "  ${RED}●${NC} validator2: OFFLINE"; fi
BLOCK=$(curl -s -m 3 -X POST "http://localhost:8549" --header "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' 2>/dev/null | jq -r '.result // empty' 2>/dev/null)
PEERS=$(curl -s -m 3 -X POST "http://localhost:8549" --header "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' 2>/dev/null | jq -r '.result // empty' 2>/dev/null)
if [ -n "$BLOCK" ]; then echo -e "  ${GREEN}●${NC} validator3: Block #$((16#${BLOCK#0x})) | Peers: $((16#${PEERS#0x}))"; else echo -e "  ${RED}●${NC} validator3: OFFLINE"; fi
BLOCK=$(curl -s -m 3 -X POST "http://localhost:8551" --header "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' 2>/dev/null | jq -r '.result // empty' 2>/dev/null)
PEERS=$(curl -s -m 3 -X POST "http://localhost:8551" --header "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' 2>/dev/null | jq -r '.result // empty' 2>/dev/null)
if [ -n "$BLOCK" ]; then echo -e "  ${GREEN}●${NC} rpc1: Block #$((16#${BLOCK#0x})) | Peers: $((16#${PEERS#0x}))"; else echo -e "  ${RED}●${NC} rpc1: OFFLINE"; fi
BLOCK=$(curl -s -m 3 -X POST "http://localhost:8553" --header "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' 2>/dev/null | jq -r '.result // empty' 2>/dev/null)
PEERS=$(curl -s -m 3 -X POST "http://localhost:8553" --header "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' 2>/dev/null | jq -r '.result // empty' 2>/dev/null)
if [ -n "$BLOCK" ]; then echo -e "  ${GREEN}●${NC} rpc2: Block #$((16#${BLOCK#0x})) | Peers: $((16#${PEERS#0x}))"; else echo -e "  ${RED}●${NC} rpc2: OFFLINE"; fi
echo ""
echo "  IBFT Validators:"
VALS=$(curl -s -X POST http://localhost:8545 --header "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"istanbul_getValidators","params":["latest"],"id":1}' 2>/dev/null | jq -r '.result[]?' 2>/dev/null)
if [ -n "$VALS" ]; then echo "$VALS" | while read -r addr; do echo -e "    ${GREEN}✓${NC} $addr"; done; else echo "    Could not fetch validators"; fi
echo "============================================================"
