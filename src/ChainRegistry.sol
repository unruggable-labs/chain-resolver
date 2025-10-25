// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {ERC8049ContractMetadata} from "./ERC8049ContractMetadata.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {HexUtils} from "@ensdomains/ens-contracts/contracts/utils/HexUtils.sol";
import {IChainRegistry} from "./interfaces/IChainRegistry.sol";
import {IERC8049} from "./interfaces/IERC8049.sol";

/**
 * @title ChainRegistry
 * @author Unruggable
 * @notice Registry for chain records using ERC-8048 onchain metadata storage
 * @dev Uses standardized keys to store all chain records as bytes
 * @dev Repository: https://github.com/unruggable-labs/chain-resolver
 */
contract ChainRegistry is ERC8049ContractMetadata, Ownable, IERC165, IChainRegistry {
    // Custom errors
    error NotAuthorized(address caller, bytes32 labelhash);
    
    // Standardized key constants for ERC-8049 contract metadata storage
    // Format: <prefix><hex-encoded-labelhash>
    string public constant ERC_7930_CHAIN_ID_KEY = "erc-7930-chain-id:";
    string public constant CHAIN_NAME_KEY = "chain-name:";
    string public constant ENS_ADDRESS_PREFIX = "ens-address:";
    string public constant ENS_CONTENTHASH_KEY = "ens-contenthash:";
    string public constant ENS_TEXT_PREFIX = "ens-text:";
    string public constant ENS_DATA_PREFIX = "ens-data:";

    // reverse resolution key constants
    // to reverse resolve use chain-name:<7930-hex>
    string public constant CHAIN_NAME_PREFIX = "chain-name:";

    // Chain ownership and authorization - now using ERC-8049 storage
    // No need for mappings since we store everything in contract metadata

    /**
     * @notice Create a standardized key with 1 parameter
     * @param _prefix The key prefix
     * @return The constructed key
     */
    function _makeKey(string memory _prefix) internal pure returns (string memory) {
        return _prefix;
    }

    /**
     * @notice Create a standardized key with 2 parameters
     * @param _prefix The key prefix
     * @param _suffix The suffix to append
     * @return The constructed key
     */
    function _makeKey(string memory _prefix, string memory _suffix) internal pure returns (string memory) {
        return string(abi.encodePacked(_prefix, _suffix));
    }

    /**
     * @notice Create a standardized key with 3 parameters
     * @param _prefix The key prefix
     * @param _middle The middle part to append
     * @param _suffix The suffix to append
     * @return The constructed key
     */
    function _makeKey(string memory _prefix, string memory _middle, string memory _suffix) internal pure returns (string memory) {
        return string(abi.encodePacked(_prefix, _middle, _suffix));
    }

    /**
     * @notice Create a standardized key with 4 parameters
     * @param _prefix The key prefix
     * @param _middle1 The first middle part to append
     * @param _middle2 The second middle part to append
     * @param _suffix The suffix to append
     * @return The constructed key
     */
    function _makeKey(string memory _prefix, string memory _middle1, string memory _middle2, string memory _suffix) internal pure returns (string memory) {
        return string(abi.encodePacked(_prefix, _middle1, _middle2, _suffix));
    }


    /**
     * @notice Constructor
     * @param _owner The address to set as the owner
     */
    constructor(address _owner) Ownable(_owner) {}

    /**
     * @notice Register a new chain with all its records
     * @param _chainName The chain name (becomes the label)
     * @param _owner The owner address
     * @param _chainId The ERC-7930 chain ID bytes
     * @param _chainName The human-readable chain name
     * @param _records Array of record data to store
     */
    function registerChain(
        string memory _chainName,
        address _owner,
        bytes memory _chainId,
        string memory _chainDisplayName,
        ChainRecord[] memory _records
    ) public {
        bytes32 _labelhash = keccak256(bytes(_chainName));
        
        // Set ownership using ERC-8049 storage
        string memory ownerKey = _makeKey("chain-owner:", _bytes32ToHex(_labelhash));
        _setContractMetadata(ownerKey, abi.encodePacked(_owner));
        
        // Set reverse lookup using ERC-8049 storage
        string memory reverseKey = _makeKey("chain-name:", HexUtils.bytesToHex(_chainId));
        _setContractMetadata(reverseKey, bytes(_chainDisplayName));
        
        // Store core chain data using contract metadata with labelhash in key
        string memory chainIdKey = _makeKey(ERC_7930_CHAIN_ID_KEY, _labelhash);
        string memory chainNameKey = _makeKey(CHAIN_NAME_KEY, _labelhash);
        _setContractMetadata(chainIdKey, _chainId);
        _setContractMetadata(chainNameKey, bytes(_chainDisplayName));
        
        // Store all provided records
        for (uint256 i = 0; i < _records.length; i++) {
            ChainRecord memory record = _records[i];
            string memory recordKey = string(abi.encodePacked(record.key, ":", _bytes32ToHex(_labelhash)));
            _setContractMetadata(recordKey, record.value);
        }
        
        emit ChainRegistered(_labelhash, _owner, _chainId, _chainDisplayName);
    }

    /**
     * @notice Batch register multiple chains
     * @param _chains Array of chain registration data
     */
    function batchRegisterChains(ChainRegistration[] calldata _chains) external onlyOwner {
        for (uint256 i = 0; i < _chains.length; i++) {
            ChainRegistration memory chain = _chains[i];
            registerChain(
                chain.chainName,
                chain.owner,
                chain.chainId,
                chain.chainDisplayName,
                chain.records
            );
        }
    }

    /**
     * @notice Set a record for a chain (authorized users only)
     * @param _labelhash The chain labelhash
     * @param _key The record key
     * @param _value The record value
     */
    function setChainRecord(bytes32 _labelhash, string calldata _key, bytes calldata _value) 
        external 
    {
        _checkAuthorization(_labelhash);
        
        string memory recordKey = string(abi.encodePacked(_key, ":", _bytes32ToHex(_labelhash)));
        _setContractMetadata(recordKey, _value);
        emit ChainRecordSet(_labelhash, _key, _value);
    }

    /**
     * @notice Set ERC-7930 chain ID for a labelhash
     * @param _labelhash The labelhash
     * @param _chainId The ERC-7930 chain ID bytes
     */
    function setERC7930ChainId(bytes32 _labelhash, bytes calldata _chainId) external {
        _checkAuthorization(_labelhash, msg.sender);
        string memory key = _makeKey(ERC_7930_CHAIN_ID_KEY, _bytes32ToHex(_labelhash));
        _setContractMetadata(key, _chainId);
        emit ChainRecordSet(_labelhash, ERC_7930_CHAIN_ID_KEY, _chainId);
    }

    /**
     * @notice Set chain name for a labelhash
     * @param _labelhash The labelhash
     * @param _chainName The chain name
     */
    function setChainName(bytes32 _labelhash, string calldata _chainName) external {
        _checkAuthorization(_labelhash, msg.sender);
        string memory key = _makeKey(CHAIN_NAME_KEY, _bytes32ToHex(_labelhash));
        _setContractMetadata(key, bytes(_chainName));
        emit ChainRecordSet(_labelhash, CHAIN_NAME_KEY, bytes(_chainName));
    }

    /**
     * @notice Set ENS address for a labelhash and coin type
     * @param _labelhash The labelhash
     * @param _coinType The coin type
     * @param _address The address bytes
     */
    function setENSAddress(bytes32 _labelhash, uint256 _coinType, bytes calldata _address) external {
        _checkAuthorization(_labelhash, msg.sender);
        string memory key = _makeKey(ENS_ADDRESS_PREFIX, _bytes32ToHex(_labelhash), ",", _uint256ToString(_coinType));
        _setContractMetadata(key, _address);
        emit ChainRecordSet(_labelhash, key, _address);
    }

    /**
     * @notice Set ENS content hash for a labelhash
     * @param _labelhash The labelhash
     * @param _contentHash The content hash
     */
    function setENSContentHash(bytes32 _labelhash, bytes calldata _contentHash) external {
        _checkAuthorization(_labelhash, msg.sender);
        string memory key = _makeKey(ENS_CONTENTHASH_KEY, _bytes32ToHex(_labelhash));
        _setContractMetadata(key, _contentHash);
        emit ChainRecordSet(_labelhash, ENS_CONTENTHASH_KEY, _contentHash);
    }

    /**
     * @notice Set ENS text record for a labelhash
     * @param _labelhash The labelhash
     * @param _textKey The text record key
     * @param _textValue The text record value
     */
    function setENSText(bytes32 _labelhash, string calldata _textKey, string calldata _textValue) external {
        _checkAuthorization(_labelhash, msg.sender);
        string memory key = _makeKey(ENS_TEXT_PREFIX, _bytes32ToHex(_labelhash), ":", _textKey);
        _setContractMetadata(key, bytes(_textValue));
        emit ChainRecordSet(_labelhash, key, bytes(_textValue));
    }

    /**
     * @notice Set ENS data record for a labelhash
     * @param _labelhash The labelhash
     * @param _dataKey The data record key
     * @param _dataValue The data record value
     */
    function setENSData(bytes32 _labelhash, string calldata _dataKey, bytes calldata _dataValue) external {
        _checkAuthorization(_labelhash, msg.sender);
        string memory key = _makeKey(ENS_DATA_PREFIX, _bytes32ToHex(_labelhash), ":", _dataKey);
        _setContractMetadata(key, _dataValue);
        emit ChainRecordSet(_labelhash, key, _dataValue);
    }



    /**
     * @notice Get the ERC-7930 chain ID for a chain
     * @param _labelhash The chain labelhash
     * @return The ERC-7930 chain ID bytes
     */
    function getChainId(bytes32 _labelhash) external view returns (bytes memory) {
        string memory chainIdKey = _makeKey(ERC_7930_CHAIN_ID_KEY, _bytes32ToHex(_labelhash));
        return this.getContractMetadata(chainIdKey);
    }

    /**
     * @notice Get the chain name for an ERC-7930 address
     * @param _erc7930Address The ERC-7930 address hex encoded string
     * @return The chain name
     */
    function getChainName(bytes calldata _erc7930Address) external view returns (string memory) {
        string memory chainNameKey = _makeKey("chain-name:", HexUtils.bytesToHex(_erc7930Address));
        bytes memory nameBytes = this.getContractMetadata(chainNameKey);
        return string(nameBytes);
    }

    /**
     * @notice Get the owner of a chain
     * @param _labelhash The chain labelhash
     * @return The owner address
     */
    function getChainOwner(bytes32 _labelhash) external view returns (address) {
        string memory ownerKey = _makeKey("chain-owner:", _bytes32ToHex(_labelhash));
        bytes memory ownerBytes = this.getContractMetadata(ownerKey);
        if (ownerBytes.length == 0) {
            return address(0);
        }
        return address(bytes20(ownerBytes));
    }

    /**
     * @notice Get the chain name for a chain ID
     * @param _chainId The chain ID
     * @return The chain name
     */
    function getChainNameByChainId(bytes calldata _chainId) external view returns (string memory) {
        return this.getChainName(_chainId);
    }

    /**
     * @notice Set operator for chain management
     * @param _operator The operator address
     * @param _isOperator Whether the address is an operator
     */
    function setOperator(address _operator, bool _isOperator) external {
        string memory operatorKey = _makeKey("chain-operator:", _addressToHex(msg.sender), ",", _addressToHex(_operator));
        _setContractMetadata(operatorKey, abi.encodePacked(_isOperator));
        emit OperatorSet(msg.sender, _operator, _isOperator);
    }

    /**
     * @notice Set operator for a specific caller (called by resolver)
     * @param _operator The operator address
     * @param _isOperator Whether the address is an operator
     * @param _caller The original caller
     */
    function setOperatorForCaller(address _operator, bool _isOperator, address _caller) external {
        string memory operatorKey = _makeKey("chain-operator:", _addressToHex(_caller), ",", _addressToHex(_operator));
        _setContractMetadata(operatorKey, abi.encodePacked(_isOperator));
        emit OperatorSet(_caller, _operator, _isOperator);
    }

    /**
     * @notice Check if an address is authorized for a chain
     * @param _labelhash The chain labelhash
     * @param _address The address to check
     * @return True if authorized
     */
    function isAuthorized(bytes32 _labelhash, address _address) external view returns (bool) {
        address owner = this.getChainOwner(_labelhash);
        if (owner == _address) {
            return true;
        }
        
        // Check if _address is an operator of the owner
        string memory operatorKey = _makeKey("chain-operator:", _addressToHex(owner), ",", _addressToHex(_address));
        bytes memory operatorBytes = this.getContractMetadata(operatorKey);
        if (operatorBytes.length == 0) {
            return false;
        }
        return bytes1(operatorBytes) == bytes1(abi.encodePacked(true));
    }

    /**
     * @notice Supports interface check
     * @param interfaceId The interface ID to check
     * @return True if the interface is supported
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IChainRegistry).interfaceId || 
               interfaceId == type(IERC165).interfaceId ||
               interfaceId == type(IERC8049).interfaceId;
    }

    /**
     * @notice Check authorization for a labelhash
     * @param _labelhash The labelhash to check
     */
    function _checkAuthorization(bytes32 _labelhash) internal view {
        if (!this.isAuthorized(_labelhash, msg.sender)) {
            revert NotAuthorized(msg.sender, _labelhash);
        }
    }

    function _checkAuthorization(bytes32 _labelhash, address _caller) internal view {
        if (!this.isAuthorized(_labelhash, _caller)) {
            revert NotAuthorized(_caller, _labelhash);
        }
    }

    /**
     * @notice Convert bytes32 to hex string
     * @param _value The bytes32 value
     * @return The hex string representation
     */
    function _bytes32ToHex(bytes32 _value) internal pure returns (string memory) {
        return _toHexString(uint256(_value), 32);
    }

    /**
     * @notice Convert address to hex string
     * @param _addr The address to convert
     * @return The hex string representation
     */
    function _addressToHex(address _addr) internal pure returns (string memory) {
        return _toHexString(uint256(uint160(_addr)), 20);
    }

    /**
     * @notice Convert uint256 to hex string
     * @param _value The uint256 value
     * @param _length The length in bytes
     * @return The hex string representation
     */
    function _toHexString(uint256 _value, uint256 _length) internal pure returns (string memory) {
        bytes memory buffer = new bytes(2 * _length);
        for (uint256 i = 2 * _length; i > 0; --i) {
            buffer[i - 1] = _toHexChar(uint8(_value & 0xf));
            _value >>= 4;
        }
        return string(buffer);
    }

    /**
     * @notice Convert uint8 to hex character
     * @param _value The uint8 value
     * @return The hex character
     */
    function _toHexChar(uint8 _value) internal pure returns (bytes1) {
        if (_value < 10) {
            return bytes1(uint8(bytes1('0')) + _value);
        } else {
            return bytes1(uint8(bytes1('a')) + _value - 10);
        }
    }

}
