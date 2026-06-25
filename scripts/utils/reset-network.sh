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
