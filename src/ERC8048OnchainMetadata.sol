// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC8048} from "./interfaces/IERC8048.sol";

/**
 * @title ERC8048OnchainMetadata
 * @author @nxt3d
 * @dev Extension for ERC721 that adds ERC-8048 onchain metadata storage functionality
 * @dev Uses Diamond Storage pattern for predictable storage locations (ERC-8048 compliant)
 */
abstract contract ERC8048OnchainMetadata is ERC721, IERC8048 {
    /// @custom:storage-location erc8048.onchain.metadata.storage
    struct OnchainMetadataStorage {
        mapping(uint256 tokenId => mapping(string key => bytes value)) metadata;
    }

    // keccak256("erc8048.onchain.metadata.storage")
    bytes32 private constant ONCHAIN_METADATA_STORAGE_LOCATION =
        0x1d573f2bd60f6bb1db4803946b72dd4484532d479f45b50538c89a2000f39b92;

    function _getOnchainMetadataStorage() private pure returns (OnchainMetadataStorage storage $) {
        bytes32 location = ONCHAIN_METADATA_STORAGE_LOCATION;
        assembly {
            $.slot := location
        }
    }

    /**
     * @notice Get metadata value for a key
     * @param tokenId The token ID to get metadata for
     * @param key The metadata key
     * @return The metadata value as bytes
     */
    function getMetadata(uint256 tokenId, string calldata key) external view override returns (bytes memory) {
        _requireOwned(tokenId);
        OnchainMetadataStorage storage $ = _getOnchainMetadataStorage();
        return $.metadata[tokenId][key];
    }

    /**
     * @notice Set metadata for a token (only owner or approved)
     * @param tokenId The token ID to set metadata for
     * @param key The metadata key
     * @param value The metadata value as bytes
     */
    function setMetadata(uint256 tokenId, string calldata key, bytes calldata value) external {
        _requireOwned(tokenId);
        _checkCanManageToken(tokenId);
        
        OnchainMetadataStorage storage $ = _getOnchainMetadataStorage();
        $.metadata[tokenId][key] = value;
        emit MetadataSet(tokenId, key, key, value);
    }

    /**
     * @notice Set metadata for a token (callable by any contract)
     * @dev Authorization should be handled by the calling contract
     * @param tokenId The token ID to set metadata for
     * @param key The metadata key
     * @param value The metadata value as bytes
     */
    function setMetadataByContract(uint256 tokenId, string calldata key, bytes calldata value) external {
        _requireOwned(tokenId);
        
        OnchainMetadataStorage storage $ = _getOnchainMetadataStorage();
        $.metadata[tokenId][key] = value;
        emit MetadataSet(tokenId, key, key, value);
    }

    /**
     * @notice Check if caller can manage the token
     * @param tokenId The token ID to check
     */
    function _checkCanManageToken(uint256 tokenId) internal view {
        address owner = _ownerOf(tokenId);
        require(
            msg.sender == owner || 
            msg.sender == getApproved(tokenId) || 
            isApprovedForAll(owner, msg.sender),
            "Not authorized to manage token"
        );
    }

    /**
     * @notice Supports interface check
     * @param interfaceId The interface ID to check
     * @return True if the interface is supported
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721) returns (bool) {
        return interfaceId == type(IERC8048).interfaceId || 
               super.supportsInterface(interfaceId);
    }
}
