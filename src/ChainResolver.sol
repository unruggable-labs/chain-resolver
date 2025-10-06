// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title ChainResolver
 * @author Unruggable Labs
 * @notice Unified contract for ENS record resolution, reverse resolution, and chain data management.
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
     * @param _labelHash The labelhash to check authorization for
     */
    modifier onlyAuthorized(bytes32 _labelHash) {
        _authenticateCaller(msg.sender, _labelHash);
        _;
    }

    // ENS method selectors
    bytes4 public constant ADDR_SELECTOR = bytes4(keccak256("addr(bytes32)"));
    bytes4 public constant ADDR_COINTYPE_SELECTOR = bytes4(keccak256("addr(bytes32,uint256)"));
    bytes4 public constant CONTENTHASH_SELECTOR = bytes4(keccak256("contenthash(bytes32)"));
    bytes4 public constant TEXT_SELECTOR = bytes4(keccak256("text(bytes32,string)"));
    bytes4 public constant DATA_SELECTOR = bytes4(keccak256("data(bytes32,bytes)"));

    // Coin type constants
    uint256 public constant ETHEREUM_COIN_TYPE = 60;

    // Text record key constants
    string public constant CHAIN_ID_KEY = "chain-id";
    string public constant CHAIN_NAME_PREFIX = "chain-name:";

    // Chain data storage
    mapping(bytes32 _labelHash => bytes _chainId) internal chainIds;
    mapping(bytes _chainId => string _chainName) internal chainNames;
    mapping(bytes32 _labelHash => address _owner) internal labelOwners;
    mapping(address _owner => mapping(address _operator => bool _isOperator)) internal operators;

    // ENS record storage
    mapping(bytes32 labelHash => mapping(uint256 coinType => address addr)) private addressRecords;
    mapping(bytes32 labelHash => bytes contentHash) private contenthashRecords;
    mapping(bytes32 labelHash => mapping(string key => string value)) private textRecords;
    mapping(bytes32 labelHash => mapping(bytes key => bytes data)) private dataRecords;

    /**
     * @notice Constructor
     * @param _owner The address to set as the owner
     */
    constructor(address _owner) Ownable(_owner) {}

    /**
     * @notice Resolve data for a DNS-encoded name using ENSIP-10 interface.
     * @param name The DNS-encoded name.
     * @param data The ABI-encoded ENS method call data.
     * @return The resolved data based on the method selector.
     */
    function resolve(bytes calldata name, bytes calldata data) external view override returns (bytes memory) {
        // Extract the first label from the DNS-encoded name
        (bytes32 labelHash,,,) = NameCoder.readLabel(name, 0, true);

        // Get the method selector (first 4 bytes)
        bytes4 selector = bytes4(data);

        if (selector == ADDR_SELECTOR) {
            // addr(bytes32) - return address for Ethereum (coinType 60)
            address addr = addressRecords[labelHash][ETHEREUM_COIN_TYPE];
            return abi.encode(addr);
        } else if (selector == ADDR_COINTYPE_SELECTOR) {
            // addr(bytes32,uint256) - decode coinType and return address
            (, uint256 coinType) = abi.decode(data[4:], (bytes32, uint256));
            address addr = addressRecords[labelHash][coinType];
            return abi.encode(addr);
        } else if (selector == CONTENTHASH_SELECTOR) {
            // contenthash(bytes32) - return content hash
            bytes memory contentHash = contenthashRecords[labelHash];
            return abi.encode(contentHash);
        } else if (selector == TEXT_SELECTOR) {
            // text(bytes32,string) - decode key and return text value
            (, string memory key) = abi.decode(data[4:], (bytes32, string));

            // Special case for "chain-id" text record
            if (keccak256(abi.encodePacked(key)) == keccak256(abi.encodePacked(CHAIN_ID_KEY))) {
                // Get chain ID bytes from internal registry and encode as hex string
                bytes memory chainIdBytes = chainIds[labelHash];
                string memory hexString = HexUtils.bytesToHex(chainIdBytes);
                return abi.encode(hexString);
            }

            // Check if key starts with "chain-name:" prefix (reverse resolution)
            bytes memory keyBytes = bytes(key);
            bytes memory prefixBytes = bytes(CHAIN_NAME_PREFIX);
            if (_startsWith(keyBytes, prefixBytes)) {
                // Extract chainId from key (remove "chain-name:" prefix)
                string memory chainIdHex = _substring(key, prefixBytes.length, keyBytes.length);
                bytes memory chainIdBytes = bytes(chainIdHex);
                string memory resolvedChainName = chainNames[chainIdBytes];
                return abi.encode(resolvedChainName);
            }

            // Default: return text value from mapping
            string memory value = textRecords[labelHash][key];
            return abi.encode(value);
        } else if (selector == DATA_SELECTOR) {
            // data(bytes32,bytes) - decode key and return data value
            (, bytes memory key) = abi.decode(data[4:], (bytes32, bytes));

            // Check if key starts with "chain-name:" prefix (reverse resolution)
            bytes memory prefixBytes = bytes(CHAIN_NAME_PREFIX);
            if (_startsWith(key, prefixBytes)) {
                // Extract chainId from key (remove "chain-name:" prefix)
                bytes memory chainIdBytes = new bytes(key.length - prefixBytes.length);
                for (uint256 i = 0; i < chainIdBytes.length; i++) {
                    chainIdBytes[i] = key[prefixBytes.length + i];
                }
                string memory resolvedChainName = chainNames[chainIdBytes];
                return abi.encode(resolvedChainName);
            }

            // Default: return data value from mapping
            bytes memory dataValue = dataRecords[labelHash][key];
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
    function chainId(bytes32 _labelHash) external view returns (bytes memory _chainId) {
        _chainId = chainIds[_labelHash];
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
    function setLabelOwner(bytes32 _labelHash, address _owner) external onlyAuthorized(_labelHash) {
        labelOwners[_labelHash] = _owner;
        emit LabelOwnerSet(_labelHash, _owner);
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
    function isAuthorized(bytes32 _labelHash, address _address) external view returns (bool _authorized) {
        address _owner = labelOwners[_labelHash];
        return _owner == _address || operators[_owner][_address];
    }

    // ============ ENS Resolver Functions ============

    /**
     * @notice Set the address for a labelhash with a specific coin type.
     * @param _labelHash The labelhash to update.
     * @param _coinType The coin type (default: 60 for Ethereum).
     * @param _addr The address to set.
     */
    function setAddr(bytes32 _labelHash, uint256 _coinType, address _addr) external onlyAuthorized(_labelHash) {
        addressRecords[_labelHash][_coinType] = _addr;
    }

    /**
     * @notice Set the content hash for a labelhash.
     * @param _labelHash The labelhash to update.
     * @param _hash The content hash to set.
     */
    function setContenthash(bytes32 _labelHash, bytes calldata _hash) external onlyAuthorized(_labelHash) {
        contenthashRecords[_labelHash] = _hash;
    }

    /**
     * @notice Set a text record for a labelhash.
     * @param _labelHash The labelhash to update.
     * @param _key The text record key.
     * @param _value The text record value.
     * @dev Note: "chain-id" text record will be stored but not used - resolve() overrides it with internal registry value.
     */
    function setText(bytes32 _labelHash, string calldata _key, string calldata _value)
        external
        onlyAuthorized(_labelHash)
    {
        textRecords[_labelHash][_key] = _value;
    }

    /**
     * @notice Set a data record for a labelhash.
     * @param _labelHash The labelhash to update.
     * @param _key The data record key.
     * @param _data The data record value.
     */
    function setData(bytes32 _labelHash, bytes calldata _key, bytes calldata _data)
        external
        onlyAuthorized(_labelHash)
    {
        dataRecords[_labelHash][_key] = _data;
    }

    /**
     * @notice Get the address for a labelhash with a specific coin type.
     * @param _labelHash The labelhash to query.
     * @param _coinType The coin type (default: 60 for Ethereum).
     * @return The address for this label and coin type.
     */
    function getAddr(bytes32 _labelHash, uint256 _coinType) external view returns (address) {
        return addressRecords[_labelHash][_coinType];
    }

    /**
     * @notice Get the content hash for a labelhash.
     * @param _labelHash The labelhash to query.
     * @return The content hash for this label.
     */
    function getContenthash(bytes32 _labelHash) external view returns (bytes memory) {
        return contenthashRecords[_labelHash];
    }

    /**
     * @notice Get a text record for a labelhash.
     * @param _labelHash The labelhash to query.
     * @param _key The text record key.
     * @return The text record value.
     */
    function getText(bytes32 _labelHash, string calldata _key) external view returns (string memory) {
        return textRecords[_labelHash][_key];
    }

    /**
     * @notice Get a data record for a labelhash.
     * @param _labelHash The labelhash to query.
     * @param _key The data record key.
     * @return The data record value.
     */
    function getData(bytes32 _labelHash, bytes calldata _key) external view returns (bytes memory) {
        return dataRecords[_labelHash][_key];
    }

    /**
     * @notice Get the owner of a labelhash.
     * @param _labelHash The labelhash to query.
     * @return The owner address.
     */
    function getOwner(bytes32 _labelHash) external view returns (address) {
        return labelOwners[_labelHash];
    }

    // ============ Utility Functions ============

    /**
     * @notice Internal helper function to register a single chain
     * @param _chainName The chain name
     * @param _owner The owner address
     * @param _chainId The chain ID
     */
    function _register(string calldata _chainName, address _owner, bytes calldata _chainId) internal {
        bytes32 _labelHash = keccak256(bytes(_chainName));

        labelOwners[_labelHash] = _owner;
        chainIds[_labelHash] = _chainId;
        chainNames[_chainId] = _chainName;

        emit LabelOwnerSet(_labelHash, _owner);
        emit RecordSet(_labelHash, _chainId, _chainName);
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
     * @notice Authenticates the caller for a given labelhash.
     * @param _caller The address to check.
     * @param _labelHash The labelhash to check.
     */
    function _authenticateCaller(address _caller, bytes32 _labelHash) internal view {
        address _owner = labelOwners[_labelHash];
        if (_owner != _caller && !operators[_owner][_caller]) {
            revert NotAuthorized(_caller, _labelHash);
        }
    }
}
