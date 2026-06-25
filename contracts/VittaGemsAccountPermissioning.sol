// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title VittaGemsAccountPermissioning
 * @notice On-chain account permissioning for the VittaGems network.
 *
 *         GoQuorum calls `transactionAllowed()` before accepting any transaction.
 *         If this function returns false, the transaction is dropped immediately.
 *
 *         This implements the VittaGems requirement:
 *         "Approved counterparties only — no open enrollment" (Spec page 5)
 *
 *         Account types map to the VittaGems role hierarchy:
 *         - ADMIN:            Can manage the allowlist
 *         - TREASURY:         Mint, reserve management
 *         - COMPLIANCE:       Hold, freeze, release
 *         - SETTLEMENT_AGENT: Transfer, burn, reconcile
 *         - PARTNER:          Receive transfers, query balance
 *         - CONTRACT:         Deployed smart contracts (need send permissions)
 *         - READONLY:         Can query but not transact
 */
contract VittaGemsAccountPermissioning is AccessControl {

    bytes32 public constant ACCOUNT_ADMIN = keccak256("ACCOUNT_ADMIN");

    // ── Account Types ──────────────────────────────────
    enum AccountType {
        NONE,               // Not registered — all transactions blocked
        ADMIN,
        TREASURY,
        COMPLIANCE,
        SETTLEMENT_AGENT,
        PARTNER,
        CONTRACT,
        READONLY
    }

    // ── Data Structures ────────────────────────────────
    struct AccountInfo {
        address account;
        AccountType accountType;
        string  name;           // "VittaGems Treasury", "Acme US Provider"
        string  orgId;          // Organization identifier
        bool    isActive;
        uint256 addedAt;
        uint256 removedAt;
    }

    // ── State ──────────────────────────────────────────
    mapping(address => AccountInfo) public accounts;
    mapping(address => bool) public allowedAccounts;

    address[] public accountList;

    uint256 public totalAccounts;
    uint256 public activeAccounts;

    // Transaction value limits per account type
    mapping(AccountType => uint256) public transactionLimits;

    // Daily transaction count tracking
    mapping(address => mapping(uint256 => uint256)) public dailyTxCount;
    mapping(AccountType => uint256) public dailyTxLimits;

    // ── Events ─────────────────────────────────────────
    event AccountAdded(
        address indexed account,
        AccountType accountType,
        string name,
        string orgId,
        address indexed addedBy,
        uint256 timestamp
    );

    event AccountRemoved(
        address indexed account,
        string name,
        address indexed removedBy,
        uint256 timestamp
    );

    event AccountTypeChanged(
        address indexed account,
        AccountType oldType,
        AccountType newType,
        address indexed changedBy,
        uint256 timestamp
    );

    event TransactionBlocked(
        address indexed sender,
        address indexed target,
        uint256 value,
        string reason,
        uint256 timestamp
    );

    // ── Constructor ────────────────────────────────────
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ACCOUNT_ADMIN, msg.sender);

        // Register deployer as ADMIN
        _addAccount(msg.sender, AccountType.ADMIN, "Network Deployer", "VittaGems");

        // Set default transaction limits (in wei)
        // These map to VittaGems spec: "per-transaction and daily cap checks"
        transactionLimits[AccountType.ADMIN]            = type(uint256).max;
        transactionLimits[AccountType.TREASURY]          = type(uint256).max;
        transactionLimits[AccountType.COMPLIANCE]        = type(uint256).max;
        transactionLimits[AccountType.SETTLEMENT_AGENT]  = type(uint256).max;
        transactionLimits[AccountType.PARTNER]           = 0; // Partners don't send, only receive
        transactionLimits[AccountType.CONTRACT]           = type(uint256).max;
        transactionLimits[AccountType.READONLY]           = 0;

        // Daily tx count limits
        dailyTxLimits[AccountType.ADMIN]            = 10000;
        dailyTxLimits[AccountType.TREASURY]          = 5000;
        dailyTxLimits[AccountType.COMPLIANCE]        = 5000;
        dailyTxLimits[AccountType.SETTLEMENT_AGENT]  = 10000;
        dailyTxLimits[AccountType.PARTNER]           = 100;
        dailyTxLimits[AccountType.CONTRACT]           = type(uint256).max;
        dailyTxLimits[AccountType.READONLY]           = 0;
    }

    // ── GoQuorum Permissioning Interface ───────────────
    /**
     * @notice Called by GoQuorum before accepting any transaction.
     * @param sender    Transaction sender address
     * @param target    Transaction target address (0x0 for contract creation)
     * @param value     Transaction value in wei
     * @param gasPrice  Gas price (always 0 in VittaGems)
     * @param gasLimit  Gas limit
     * @param payload   Transaction data payload
     * @return          true if transaction is allowed
     */
    function transactionAllowed(
        address sender,
        address target,
        uint256 value,
        uint256 gasPrice,
        uint256 gasLimit,
        bytes calldata payload
    ) external returns (bool) {

        // Check 1: Is sender registered and active?
        if (!allowedAccounts[sender]) {
            emit TransactionBlocked(sender, target, value, "Account not registered", block.timestamp);
            return false;
        }

        AccountInfo storage senderInfo = accounts[sender];

        // Check 2: Is sender's account type allowed to send transactions?
        if (senderInfo.accountType == AccountType.READONLY) {
            emit TransactionBlocked(sender, target, value, "Read-only account", block.timestamp);
            return false;
        }

        // Check 3: Value limit check
        if (value > transactionLimits[senderInfo.accountType]) {
            emit TransactionBlocked(sender, target, value, "Exceeds value limit", block.timestamp);
            return false;
        }

        // Check 4: Daily transaction count
        uint256 today = block.timestamp / 1 days;
        if (dailyTxCount[sender][today] >= dailyTxLimits[senderInfo.accountType]) {
            emit TransactionBlocked(sender, target, value, "Daily tx limit reached", block.timestamp);
            return false;
        }

        // Increment daily count
        dailyTxCount[sender][today]++;

        return true;
    }

    // ── Admin Functions ────────────────────────────────

    /**
     * @notice Register a new account on the network.
     */
    function addAccount(
        address _account,
        AccountType _type,
        string calldata _name,
        string calldata _orgId
    ) external onlyRole(ACCOUNT_ADMIN) {
        require(!allowedAccounts[_account], "Account already registered");
        require(_type != AccountType.NONE, "Cannot register as NONE type");

        _addAccount(_account, _type, _name, _orgId);

        emit AccountAdded(_account, _type, _name, _orgId, msg.sender, block.timestamp);
    }

    /**
     * @notice Remove an account from the allowlist.
     */
    function removeAccount(address _account) external onlyRole(ACCOUNT_ADMIN) {
        require(allowedAccounts[_account], "Account not found");
        require(_account != msg.sender, "Cannot remove self");

        allowedAccounts[_account] = false;
        accounts[_account].isActive = false;
        accounts[_account].removedAt = block.timestamp;
        activeAccounts--;

        emit AccountRemoved(_account, accounts[_account].name, msg.sender, block.timestamp);
    }

    /**
     * @notice Change an account's type (role change).
     */
    function changeAccountType(
        address _account,
        AccountType _newType
    ) external onlyRole(ACCOUNT_ADMIN) {
        require(allowedAccounts[_account], "Account not found");
        require(_newType != AccountType.NONE, "Use removeAccount instead");

        AccountType oldType = accounts[_account].accountType;
        accounts[_account].accountType = _newType;

        emit AccountTypeChanged(_account, oldType, _newType, msg.sender, block.timestamp);
    }

    /**
     * @notice Reactivate a removed account.
     */
    function reactivateAccount(address _account) external onlyRole(ACCOUNT_ADMIN) {
        require(accounts[_account].addedAt > 0, "Account never existed");
        require(!allowedAccounts[_account], "Account already active");

        allowedAccounts[_account] = true;
        accounts[_account].isActive = true;
        accounts[_account].removedAt = 0;
        activeAccounts++;

        emit AccountAdded(
            _account,
            accounts[_account].accountType,
            accounts[_account].name,
            accounts[_account].orgId,
            msg.sender,
            block.timestamp
        );
    }

    /**
     * @notice Set per-transaction value limit for an account type.
     */
    function setTransactionLimit(AccountType _type, uint256 _limit) external onlyRole(ACCOUNT_ADMIN) {
        transactionLimits[_type] = _limit;
    }

    /**
     * @notice Set daily transaction count limit for an account type.
     */
    function setDailyTxLimit(AccountType _type, uint256 _limit) external onlyRole(ACCOUNT_ADMIN) {
        dailyTxLimits[_type] = _limit;
    }

    // ── View Functions ─────────────────────────────────

    function isAccountAllowed(address _account) external view returns (bool) {
        return allowedAccounts[_account];
    }

    function getAccountInfo(address _account) external view returns (AccountInfo memory) {
        return accounts[_account];
    }

    function getAccountCount() external view returns (uint256 total, uint256 active) {
        return (totalAccounts, activeAccounts);
    }

    function getAccountList() external view returns (address[] memory) {
        return accountList;
    }

    function getActiveAccounts() external view returns (AccountInfo[] memory) {
        AccountInfo[] memory result = new AccountInfo[](activeAccounts);
        uint256 idx = 0;
        for (uint256 i = 0; i < accountList.length; i++) {
            if (allowedAccounts[accountList[i]]) {
                result[idx] = accounts[accountList[i]];
                idx++;
            }
        }
        return result;
    }

    function getDailyTxCount(address _account) external view returns (uint256) {
        uint256 today = block.timestamp / 1 days;
        return dailyTxCount[_account][today];
    }

    // ── Internal ───────────────────────────────────────

    function _addAccount(
        address _account,
        AccountType _type,
        string memory _name,
        string memory _orgId
    ) internal {
        accounts[_account] = AccountInfo({
            account:     _account,
            accountType: _type,
            name:        _name,
            orgId:       _orgId,
            isActive:    true,
            addedAt:     block.timestamp,
            removedAt:   0
        });

        allowedAccounts[_account] = true;
        accountList.push(_account);
        totalAccounts++;
        activeAccounts++;
    }
}
