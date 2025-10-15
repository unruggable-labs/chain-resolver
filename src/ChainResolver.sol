// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title ChainResolver
 * @author Unruggable
 * @notice ENS resolver for chain ID registration and resolution with ERC-7930 identifiers.
 * @dev Based on Wonderland's L2Resolver.
 * @dev Repository: https://github.com/unruggable-labs/chain-resolver
 */
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {HexUtils} from "@ensdomains/ens-contracts/contracts/utils/HexUtils.sol";
import {IExtendedResolver} from "@ensdomains/ens-contracts/contracts/resolvers/profiles/IExtendedResolver.sol";
import {NameCoder} from "@ensdomains/ens-contracts/contracts/utils/NameCoder.sol";
import {IChainResolver} from "./interfaces/IChainResolver.sol";

contract ChainResolver is Ownable, IERC165, IExtendedResolver, IChainResolver {
    /**
     * @notice Modifier to ensure only the label owner or authorized operator can call the function
     * @param _labelhash The labelhash to check authorization for
     */
    modifier onlyAuthorized(bytes32 _labelhash) {
        _authenticateCaller(msg.sender, _labelhash);
        _;
    }

    // ENS method selectors
    bytes4 public constant ADDR_SELECTOR = bytes4(keccak256("addr(bytes32)"));
    bytes4 public constant ADDR_COINTYPE_SELECTOR = bytes4(keccak256("addr(bytes32,uint256)"));
    bytes4 public constant CONTENTHASH_SELECTOR = bytes4(keccak256("contenthash(bytes32)"));
    bytes4 public constant TEXT_SELECTOR = bytes4(keccak256("text(bytes32,string)"));
    bytes4 public constant DATA_SELECTOR = bytes4(keccak256("data(bytes32,string)"));

    // Coin type constants
    uint256 public constant ETHEREUM_COIN_TYPE = 60;

    // Text record key constants
    string public constant CHAIN_ID_KEY = "chain-id";
    string public constant CHAIN_NAME_PREFIX = "chain-name:";

    // Chain data storage
    mapping(bytes32 _labelhash => bytes _chainId) internal chainIds;
    mapping(bytes _chainId => string _chainName) internal chainNames;
    mapping(bytes32 _labelhash => address _owner) internal labelOwners;
    mapping(address _owner => mapping(address _operator => bool _isOperator)) internal operators;

    // ENS record storage
    mapping(bytes32 labelhash => mapping(uint256 coinType => bytes value)) private addressRecords;
    mapping(bytes32 labelhash => bytes contentHash) private contenthashRecords;
    mapping(bytes32 labelhash => mapping(string key => string value)) private textRecords;
    mapping(bytes32 labelhash => mapping(string key => bytes data)) private dataRecords;

    /**
     * @notice Constructor
     * @param _owner The address to set as the owner
     */
    constructor(address _owner) Ownable(_owner) {}

    /**
     * @notice Resolve data for a DNS-encoded name using ENSIP-10 interface.
     * @param name The DNS-encoded name.
     * @param data The ABI-encoded ENS method calldata.
     * @return The resolved data based on the method selector.
     */
    function resolve(bytes calldata name, bytes calldata data) external view override returns (bytes memory) {
        // Extract the first label from the DNS-encoded name
        (bytes32 labelhash,,,) = NameCoder.readLabel(name, 0, true);

        // Get the method selector (first 4 bytes)
        bytes4 selector = bytes4(data);

        if (selector == ADDR_SELECTOR) {
            bytes memory v = addressRecords[labelhash][ETHEREUM_COIN_TYPE];
            if (v.length == 0) {
                return abi.encode(payable(0));
            }
            return abi.encode(bytesToAddress(v));
        } else if (selector == ADDR_COINTYPE_SELECTOR) {
            (, uint256 coinType) = abi.decode(data[4:], (bytes32, uint256));
            bytes memory a = addressRecords[labelhash][coinType];
            return abi.encode(a);
        } else if (selector == CONTENTHASH_SELECTOR) {
            // contenthash(bytes32) - return content hash
            bytes memory contentHash = contenthashRecords[labelhash];
            return abi.encode(contentHash);
        } else if (selector == TEXT_SELECTOR) {
            // text(bytes32,string) - decode key and return text value
            (, string memory key) = abi.decode(data[4:], (bytes32, string));
            string memory value = _getTextWithOverrides(labelhash, key);
            return abi.encode(value);
        } else if (selector == DATA_SELECTOR) {
            // data(bytes32,string) - decode key and return data value
            (, string memory keyStr) = abi.decode(data[4:], (bytes32, string));
            bytes memory dataValue = _getDataWithOverrides(labelhash, keyStr);
            return abi.encode(dataValue);
        }

        // Return empty bytes if no selector matches
        return abi.encode("");
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IExtendedResolver).interfaceId
            || interfaceId == type(IChainResolver).interfaceId;
    }

    // ============ Chain Registry Functions ============

    /**
     * @inheritdoc IChainResolver
     */
    function chainName(bytes calldata _chainIdBytes) external view returns (string memory _chainName) {
        _chainName = chainNames[_chainIdBytes];
    }

    /**
     * @inheritdoc IChainResolver
     */
    function chainId(bytes32 _labelhash) external view returns (bytes memory _chainId) {
        _chainId = chainIds[_labelhash];
    }

    /**
     * @inheritdoc IChainResolver
     */
    function register(string calldata _chainName, address _owner, bytes calldata _chainId) external onlyOwner {
        _register(_chainName, _owner, _chainId);
    }

    /**
     * @notice Batch register multiple chains (owner only)
     * @param _chainNames Array of chain names
     * @param _owners Array of owners for each chain
     * @param _chainIds Array of chain IDs
     */
    function batchRegister(string[] calldata _chainNames, address[] calldata _owners, bytes[] calldata _chainIds)
        external
        onlyOwner
    {
        uint256 _length = _chainNames.length;
        if (_length != _owners.length || _length != _chainIds.length) {
            revert InvalidDataLength();
        }

        for (uint256 i = 0; i < _length; i++) {
            _register(_chainNames[i], _owners[i], _chainIds[i]);
        }
    }

    /**
     * @inheritdoc IChainResolver
     */
    function setLabelOwner(bytes32 _labelhash, address _owner) external onlyAuthorized(_labelhash) {
        labelOwners[_labelhash] = _owner;
        emit LabelOwnerSet(_labelhash, _owner);
    }

    /**
     * @inheritdoc IChainResolver
     */
    function setOperator(address _operator, bool _isOperator) external {
        operators[msg.sender][_operator] = _isOperator;
        emit OperatorSet(msg.sender, _operator, _isOperator);
    }

    /**
     * @inheritdoc IChainResolver
     */
    function isAuthorized(bytes32 _labelhash, address _address) external view returns (bool _authorized) {
        address _owner = labelOwners[_labelhash];
        return _owner == _address || operators[_owner][_address];
    }

    // ============ ENS Resolver Functions ============

    /**
     * @notice Set the ETH address (coin type 60) for a labelhash.
     * @param _labelhash The labelhash to update.
     * @param _addr The EVM address to set.
     */
    function setAddr(bytes32 _labelhash, address _addr) external onlyAuthorized(_labelhash) {
        addressRecords[_labelhash][ETHEREUM_COIN_TYPE] = abi.encodePacked(_addr);
        emit AddrChanged(_labelhash, _addr);
    }

    /**
     * @notice Set a multi-coin address for a given coin type.
     * @param _labelhash The labelhash to update.
     * @param _coinType The coin type (per ENSIP-11).
     * @param _value The raw address bytes encoded for that coin type.
     */
    function setAddr(bytes32 _labelhash, uint256 _coinType, bytes calldata _value)
        external
        onlyAuthorized(_labelhash)
    {
        addressRecords[_labelhash][_coinType] = _value;
        emit AddressChanged(_labelhash, _coinType, _value);
        if (_coinType == ETHEREUM_COIN_TYPE) {
            emit AddrChanged(_labelhash, bytesToAddress(_value));
        }
    }

    /**
     * @notice Set the content hash for a labelhash.
     * @param _labelhash The labelhash to update.
     * @param _hash The content hash to set.
     */
    function setContenthash(bytes32 _labelhash, bytes calldata _hash) external onlyAuthorized(_labelhash) {
        contenthashRecords[_labelhash] = _hash;
    }

    /**
     * @notice Set a text record for a labelhash.
     * @param _labelhash The labelhash to update.
     * @param _key The text record key.
     * @param _value The text record value.
     * @dev Note: "chain-id" text record will be stored but not used - resolve() overrides it with internal registry value.
     */
    function setText(bytes32 _labelhash, string calldata _key, string calldata _value)
        external
        onlyAuthorized(_labelhash)
    {
        textRecords[_labelhash][_key] = _value;
    }

    /**
     * @notice Set a data record for a labelhash.
     * @param _labelhash The labelhash to update.
     * @param _key The data record key.
     * @param _data The data record value.
     */
    function setData(bytes32 _labelhash, string calldata _key, bytes calldata _data)
        external
        onlyAuthorized(_labelhash)
    {
        dataRecords[_labelhash][_key] = _data;
        emit DataChanged(_labelhash, _key, _key, _data);
    }

    /**
     * @notice Get the address for a labelhash with a specific coin type.
     * @param _labelhash The labelhash to query.
     * @param _coinType The coin type (default: 60 for Ethereum).
     * @return The address for this label and coin type.
     */
    function getAddr(bytes32 _labelhash, uint256 _coinType) external view returns (bytes memory) {
        return addressRecords[_labelhash][_coinType];
    }

    /**
     * @notice Get the content hash for a labelhash.
     * @param _labelhash The labelhash to query.
     * @return The content hash for this label.
     */
    function getContenthash(bytes32 _labelhash) external view returns (bytes memory) {
        return contenthashRecords[_labelhash];
    }

    /**
     * @notice Get a text record for a labelhash.
     * @param _labelhash The labelhash to query.
     * @param _key The text record key.
     * @return The text record value (with special handling for chain-id and chain-name:).
     */
    function getText(bytes32 _labelhash, string calldata _key) external view returns (string memory) {
        return _getTextWithOverrides(_labelhash, _key);
    }

    /**
     * @notice Get a data record for a labelhash.
     * @param _labelhash The labelhash to query.
     * @param _key The data record key.
     * @return The data record value (with special handling for chain-id).
     */
    function getData(bytes32 _labelhash, string calldata _key) external view returns (bytes memory) {
        return _getDataWithOverrides(_labelhash, _key);
    }

    /**
     * @notice Get the owner of a labelhash.
     * @param _labelhash The labelhash to query.
     * @return The owner address.
     */
    function getOwner(bytes32 _labelhash) external view returns (address) {
        return labelOwners[_labelhash];
    }

    // ============ Utility Functions ============

    /**
     * @notice Internal helper function to register a single chain
     * @param _chainName The chain name
     * @param _owner The owner address
     * @param _chainId The chain ID
     */
    function _register(string calldata _chainName, address _owner, bytes calldata _chainId) internal {
        bytes32 _labelhash = keccak256(bytes(_chainName));

        labelOwners[_labelhash] = _owner;
        chainIds[_labelhash] = _chainId;
        chainNames[_chainId] = _chainName;

        emit LabelOwnerSet(_labelhash, _owner);
        emit RecordSet(_labelhash, _chainId, _chainName);
    }

    /**
     * @notice Check if bytes starts with a prefix
     * @param data The bytes to check
     * @param prefix The prefix to look for
     * @return True if data starts with prefix
     */
    function _startsWith(bytes memory data, bytes memory prefix) internal pure returns (bool) {
        if (data.length < prefix.length) return false;
        for (uint256 i = 0; i < prefix.length; i++) {
            if (data[i] != prefix[i]) return false;
        }
        return true;
    }

    /**
     * @notice Extract substring from string
     * @param str The string to extract from
     * @param start The start index
     * @param end The end index
     * @return The extracted substring
     */
    function _substring(string memory str, uint256 start, uint256 end) internal pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        bytes memory result = new bytes(end - start);
        for (uint256 i = start; i < end; i++) {
            result[i - start] = strBytes[i];
        }
        return string(result);
    }

    /**
     * @notice Internal function to handle text record keys with overrides
     * @param _labelhash The labelhash to query
     * @param _key The text record key
     * @return The text record value (with overrides for chain-id and chain-name:)
     */
    function _getTextWithOverrides(bytes32 _labelhash, string memory _key) internal view returns (string memory) {
        // Special case for "chain-id" text record
        // When client requests text record with key "chain-id", return the chain's ERC-7930 identifier as hex string
        // Note: Resolving ERC-7930 chain IDs via data record (raw bytes) is preferred, but text record is included for compatibility with ENSIP-5
        if (keccak256(abi.encodePacked(_key)) == keccak256(abi.encodePacked(CHAIN_ID_KEY))) {
            // Get chain ID bytes from internal registry and encode as hex string
            bytes memory chainIdBytes = chainIds[_labelhash];
            return HexUtils.bytesToHex(chainIdBytes);
        }

        // Check if key starts with "chain-name:" prefix (reverse resolution)
        // This enables reverse lookup: given a ERC-7930 chain ID, find the chain name
        // Format: "chain-name:0x<ERC-7930-hex-string>" where <ERC-7930-hex-string> is the chain ID in hex
        bytes memory keyBytes = bytes(_key);
        bytes memory keyPrefixBytes = bytes(CHAIN_NAME_PREFIX);
        if (_startsWith(keyBytes, keyPrefixBytes)) {
            // Extract the chain ID hex string from after the "chain-name:" prefix
            // Example: "chain-name:0x000000010001010a00" -> "0x000000010001010a00"
            string memory chainIdPart = _substring(_key, keyPrefixBytes.length, keyBytes.length);
            // Convert hex string to bytes for lookup in chainNames mapping
            (bytes memory chainIdBytes,) = HexUtils.hexToBytes(bytes(chainIdPart), 0, bytes(chainIdPart).length);
            // Return the chain name associated with this chain ID
            return chainNames[chainIdBytes];
        }

        // Default: return stored text record
        // For all other keys, return the value stored in the textRecords mapping
        return textRecords[_labelhash][_key];
    }

    /**
     * @notice Internal function to handle data record keys with overrides
     * @param _labelhash The labelhash to query
     * @param _key The data record key
     * @return The data record value (with override for chain-id)
     */
    function _getDataWithOverrides(bytes32 _labelhash, string memory _key) internal view returns (bytes memory) {
        // Special case for "chain-id" data record: return raw ERC-7930 bytes
        if (keccak256(abi.encodePacked(_key)) == keccak256(abi.encodePacked(CHAIN_ID_KEY))) {
            return chainIds[_labelhash];
        }

        // Default: return stored data record
        return dataRecords[_labelhash][_key];
    }

    /**
     * @notice Decodes a packed 20-byte value into an EVM address.
     * @param b The 20-byte sequence.
     * @return a The decoded payable address.
     * @dev Reverts if `b.length != 20`.
     */
    function bytesToAddress(bytes memory b) internal pure returns (address payable a) {
        require(b.length == 20);
        assembly {
            a := div(mload(add(b, 32)), exp(256, 12))
        }
    }

    /**
     * @notice Authenticates the caller for a given labelhash.
     * @param _caller The address to check.
     * @param _labelhash The labelhash to check.
     */
    function _authenticateCaller(address _caller, bytes32 _labelhash) internal view {
        address _owner = labelOwners[_labelhash];
        if (_owner != _caller && !operators[_owner][_caller]) {
            revert NotAuthorized(_caller, _labelhash);
        }
    }
}
