// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {IERC8049} from "./interfaces/IERC8049.sol";

/**
 * @title ERC8049ContractMetadata
 * @notice Extension for ERC-8049 Contract-Level Onchain Metadata
 * @dev Implements Diamond Storage pattern for predictable storage locations
 */
abstract contract ERC8049ContractMetadata is IERC8049 {
    struct ContractMetadataStorage {
        mapping(string key => bytes value) metadata;
    }

    // keccak256("erc8049.contract.metadata.storage")
    bytes32 private constant CONTRACT_METADATA_STORAGE_LOCATION =
        0x7c6988a1b2cb39fbaff1c9413b7b80ed9241f1bdbe6602ef83baf9d6673fd50a;

    function _getContractMetadataStorage() private pure returns (ContractMetadataStorage storage $) {
        bytes32 location = CONTRACT_METADATA_STORAGE_LOCATION;
        assembly {
            $.slot := location
        }
    }

    /**
     * @notice Get contract metadata value for a key
     * @param key The metadata key
     * @return value The metadata value as bytes
     */
    function getContractMetadata(string calldata key) external view override returns (bytes memory value) {
        ContractMetadataStorage storage $ = _getContractMetadataStorage();
        return $.metadata[key];
    }

    /**
     * @notice Set contract metadata value for a key
     * @param key The metadata key
     * @param value The metadata value as bytes
     * @dev This function should be overridden to add access control
     */
    function _setContractMetadata(string memory key, bytes memory value) internal {
        ContractMetadataStorage storage $ = _getContractMetadataStorage();
        $.metadata[key] = value;
        emit ContractMetadataUpdated(key, key, value);
    }
}
