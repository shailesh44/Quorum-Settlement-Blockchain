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
