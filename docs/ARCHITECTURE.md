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
