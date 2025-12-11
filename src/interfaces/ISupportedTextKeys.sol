// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title ISupportedTextKeys
 * @notice Interface for the supported text keys for a given node (ENSIP-5).
 * @dev Interface selector: `0x92873114`
 */
interface ISupportedTextKeys {
    /// @notice For a specific `node`, get an array of supported text keys.
    /// @param node The node (namehash).
    /// @return The keys for which we have associated text records.
    function supportedTextKeys(bytes32 node) external view returns (string[] memory);
}

