// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

/**
 * @title IERC8048
 * @author @nxt3d
 * @notice Interface for ERC-8048 onchain metadata storage
 * @dev Standardized interface for storing and retrieving onchain metadata
 */
interface IERC8048 {
    
    /**
     * @notice Emitted when metadata is set for a token
     * @param tokenId The token ID
     * @param key The metadata key
     * @param value The metadata value
     */
    event MetadataSet(uint256 indexed tokenId, string key, string indexed indexedKey, bytes value);

    /**
     * @notice Get metadata value for a key
     * @param tokenId The token ID to get metadata for
     * @param key The metadata key
     * @return The metadata value as bytes
     */
    function getMetadata(uint256 tokenId, string calldata key) external view returns (bytes memory);

    /**
     * @notice Set metadata for a token
     * @param tokenId The token ID to set metadata for
     * @param key The metadata key
     * @param value The metadata value as bytes
     */
    function setMetadata(uint256 tokenId, string calldata key, bytes calldata value) external;

    /**
     * @notice Set metadata for a token (callable by any contract)
     * @param tokenId The token ID to set metadata for
     * @param key The metadata key
     * @param value The metadata value as bytes
     */
    function setMetadataByContract(uint256 tokenId, string calldata key, bytes calldata value) external;
}
