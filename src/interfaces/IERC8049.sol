// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

/**
 * @title IERC8049
 * @author @nxt3d
 * @notice Interface for ERC-8049 Contract-Level Onchain Metadata
 * @dev Standardized interface for storing and retrieving contract-level metadata
 */
interface IERC8049 {
    
    /**
     * @notice Emitted when contract metadata is updated
     * @param key The metadata key
     * @param indexedKey The indexed metadata key
     * @param value The metadata value
     */
    event ContractMetadataUpdated(string key, string indexed indexedKey, bytes value);

    /**
     * @notice Get contract metadata value for a key
     * @param key The metadata key
     * @return value The metadata value as bytes
     */
    function getContractMetadata(string calldata key) external view returns (bytes memory value);
}