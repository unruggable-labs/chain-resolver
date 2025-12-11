// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title ISupportedDataKeys
 * @notice Interface for the supported data keys for a given node (ENSIP-24).
 * @dev Interface selector: `0x29fb1892`
 */
interface ISupportedDataKeys {
    /// @notice For a specific `node`, get an array of supported data keys.
    /// @param node The node (namehash).
    /// @return The keys for which we have associated data.
    function supportedDataKeys(bytes32 node) external view returns (string[] memory);
}