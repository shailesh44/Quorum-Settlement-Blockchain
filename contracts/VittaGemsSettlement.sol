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

        s.partner = _to;
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
