// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title VittaGemsNodePermissioning
 * @notice On-chain node permissioning for the VittaGems network.
 *
 *         GoQuorum calls `connectionAllowed()` at the P2P layer every time
 *         a node attempts to connect. If this function returns false, the
 *         connection is rejected at the protocol level — not just a config file.
 *
 *         This contract implements the GoQuorum Permissioning v2 interface:
 *         https://consensys.github.io/quorum/en/latest/Concepts/Permissioning/
 *
 * @dev    To activate, deploy this contract and pass its address in each node's
 *         startup config: --permissioned --permissions-nodes-contract <address>
 *         Or configure in the genesis file under "permissionConfig".
 */
contract VittaGemsNodePermissioning is AccessControl {

    bytes32 public constant NODE_ADMIN = keccak256("NODE_ADMIN");

    // ── Data Structures ────────────────────────────────
    struct NodeInfo {
        string  enodeId;     // 128-char hex public key
        string  ip;          // IP or hostname
        uint16  port;        // P2P port
        string  name;        // Human-readable name ("validator1", "rpc1")
        string  orgId;       // Organization ("VittaGems", "PartnerA")
        bool    isActive;
        uint256 addedAt;
        uint256 removedAt;
    }

    // ── State ──────────────────────────────────────────
    // enodeId (lowercase) → NodeInfo
    mapping(string => NodeInfo) public nodes;

    // List of all enode IDs (for enumeration)
    string[] public nodeList;

    // Quick lookup: enodeId → allowed
    mapping(string => bool) public allowedNodes;

    uint256 public totalNodes;
    uint256 public activeNodes;

    // ── Events ─────────────────────────────────────────
    event NodeAdded(
        string indexed enodeId,
        string ip,
        uint16 port,
        string name,
        string orgId,
        address indexed addedBy,
        uint256 timestamp
    );

    event NodeRemoved(
        string indexed enodeId,
        string name,
        address indexed removedBy,
        uint256 timestamp
    );

    event NodeUpdated(
        string indexed enodeId,
        string ip,
        uint16 port,
        address indexed updatedBy,
        uint256 timestamp
    );

    // ── Constructor ────────────────────────────────────
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(NODE_ADMIN, msg.sender);
    }

    // ── GoQuorum Permissioning Interface ───────────────
    /**
     * @notice Called by GoQuorum at the P2P layer for every incoming connection.
     * @param enodeId   The connecting node's public key (128 hex chars)
     * @param ip        The connecting node's IP address
     * @param port      The connecting node's P2P port
     * @return          true if connection is allowed, false to reject
     */
    function connectionAllowed(
        string calldata enodeId,
        string calldata ip,
        uint16 port
    ) external view returns (bool) {
        return allowedNodes[_toLower(enodeId)];
    }

    // ── Admin Functions ────────────────────────────────

    /**
     * @notice Add a node to the allowlist.
     */
    function addNode(
        string calldata _enodeId,
        string calldata _ip,
        uint16 _port,
        string calldata _name,
        string calldata _orgId
    ) external onlyRole(NODE_ADMIN) {
        string memory lowerEnodeId = _toLower(_enodeId);

        require(!allowedNodes[lowerEnodeId], "Node already exists");
        require(bytes(_enodeId).length == 128, "Invalid enode ID length");

        nodes[lowerEnodeId] = NodeInfo({
            enodeId:   lowerEnodeId,
            ip:        _ip,
            port:      _port,
            name:      _name,
            orgId:     _orgId,
            isActive:  true,
            addedAt:   block.timestamp,
            removedAt: 0
        });

        allowedNodes[lowerEnodeId] = true;
        nodeList.push(lowerEnodeId);
        totalNodes++;
        activeNodes++;

        emit NodeAdded(lowerEnodeId, _ip, _port, _name, _orgId, msg.sender, block.timestamp);
    }

    /**
     * @notice Remove a node from the allowlist.
     *         The node will be disconnected at the next P2P check.
     */
    function removeNode(string calldata _enodeId) external onlyRole(NODE_ADMIN) {
        string memory lowerEnodeId = _toLower(_enodeId);

        require(allowedNodes[lowerEnodeId], "Node not found");

        allowedNodes[lowerEnodeId] = false;
        nodes[lowerEnodeId].isActive = false;
        nodes[lowerEnodeId].removedAt = block.timestamp;
        activeNodes--;

        emit NodeRemoved(lowerEnodeId, nodes[lowerEnodeId].name, msg.sender, block.timestamp);
    }

    /**
     * @notice Update a node's connection details (IP/port change).
     */
    function updateNode(
        string calldata _enodeId,
        string calldata _newIp,
        uint16 _newPort
    ) external onlyRole(NODE_ADMIN) {
        string memory lowerEnodeId = _toLower(_enodeId);

        require(allowedNodes[lowerEnodeId], "Node not found or not active");

        nodes[lowerEnodeId].ip = _newIp;
        nodes[lowerEnodeId].port = _newPort;

        emit NodeUpdated(lowerEnodeId, _newIp, _newPort, msg.sender, block.timestamp);
    }

    /**
     * @notice Re-activate a previously removed node.
     */
    function reactivateNode(string calldata _enodeId) external onlyRole(NODE_ADMIN) {
        string memory lowerEnodeId = _toLower(_enodeId);

        require(bytes(nodes[lowerEnodeId].enodeId).length > 0, "Node never existed");
        require(!allowedNodes[lowerEnodeId], "Node already active");

        allowedNodes[lowerEnodeId] = true;
        nodes[lowerEnodeId].isActive = true;
        nodes[lowerEnodeId].removedAt = 0;
        activeNodes++;

        emit NodeAdded(
            lowerEnodeId,
            nodes[lowerEnodeId].ip,
            nodes[lowerEnodeId].port,
            nodes[lowerEnodeId].name,
            nodes[lowerEnodeId].orgId,
            msg.sender,
            block.timestamp
        );
    }

    // ── View Functions ─────────────────────────────────

    function isNodeAllowed(string calldata _enodeId) external view returns (bool) {
        return allowedNodes[_toLower(_enodeId)];
    }

    function getNodeInfo(string calldata _enodeId) external view returns (NodeInfo memory) {
        return nodes[_toLower(_enodeId)];
    }

    function getNodeCount() external view returns (uint256 total, uint256 active) {
        return (totalNodes, activeNodes);
    }

    function getNodeList() external view returns (string[] memory) {
        return nodeList;
    }

    /**
     * @notice Get all currently active nodes.
     */
    function getActiveNodes() external view returns (NodeInfo[] memory) {
        NodeInfo[] memory result = new NodeInfo[](activeNodes);
        uint256 idx = 0;
        for (uint256 i = 0; i < nodeList.length; i++) {
            if (allowedNodes[nodeList[i]]) {
                result[idx] = nodes[nodeList[i]];
                idx++;
            }
        }
        return result;
    }

    // ── Internal ───────────────────────────────────────

    /**
     * @dev Convert string to lowercase for consistent key matching.
     *      Enode IDs can come in mixed case from different sources.
     */
    function _toLower(string memory _str) internal pure returns (string memory) {
        bytes memory bStr = bytes(_str);
        bytes memory bLower = new bytes(bStr.length);
        for (uint256 i = 0; i < bStr.length; i++) {
            if (bStr[i] >= 0x41 && bStr[i] <= 0x5A) {
                bLower[i] = bytes1(uint8(bStr[i]) + 32);
            } else {
                bLower[i] = bStr[i];
            }
        }
        return string(bLower);
    }
}
