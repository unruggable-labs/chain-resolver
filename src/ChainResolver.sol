// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

/**
 * @title ChainResolver
 * @author Unruggable
 * @notice ENS resolver for chain ID registration and resolution with ERC-7930 identifiers.
 * @dev Simplified resolver that reads from ChainRegistry using ERC-8048 storage
 * @dev Repository: https://github.com/unruggable-labs/chain-resolver
 */
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {HexUtils} from "@ensdomains/ens-contracts/contracts/utils/HexUtils.sol";
import {IExtendedResolver} from "@ensdomains/ens-contracts/contracts/resolvers/profiles/IExtendedResolver.sol";
import {NameCoder} from "@ensdomains/ens-contracts/contracts/utils/NameCoder.sol";
import {IChainResolver} from "./interfaces/IChainResolver.sol";
import {IChainRegistry} from "./interfaces/IChainRegistry.sol";

contract ChainResolver is Ownable, IERC165, IExtendedResolver, IChainResolver {
    // Custom errors
    error UseRegistryForOwnershipManagement();
    
    // Registry contract
    IChainRegistry public immutable registry;

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

    // Registry key constants
    string public constant ERC_7930_CHAIN_ID_KEY = "erc-7930-chain-id";
    string public constant CHAIN_NAME_KEY = "chain-name";
    string public constant ENS_ADDRESS_PREFIX = "ens-address:";
    string public constant ENS_CONTENTHASH_KEY = "ens-contenthash";
    string public constant ENS_TEXT_PREFIX = "ens-text:";
    string public constant ENS_DATA_PREFIX = "ens-data:";

    /**
     * @notice Constructor
     * @param _owner The address to set as the owner
     * @param _registry The ChainRegistry contract address
     */
    constructor(address _owner, address _registry) Ownable(_owner) {
        registry = IChainRegistry(_registry);
    }

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
            return _resolveAddress(labelhash, ETHEREUM_COIN_TYPE);
        } else if (selector == ADDR_COINTYPE_SELECTOR) {
            (, uint256 coinType) = abi.decode(data[4:], (bytes32, uint256));
            return _resolveAddress(labelhash, coinType);
        } else if (selector == CONTENTHASH_SELECTOR) {
            return _resolveContenthash(labelhash);
        } else if (selector == TEXT_SELECTOR) {
            (, string memory key) = abi.decode(data[4:], (bytes32, string));
            return _resolveText(labelhash, key);
        } else if (selector == DATA_SELECTOR) {
            (, string memory key) = abi.decode(data[4:], (bytes32, string));
            return _resolveData(labelhash, key);
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
        return registry.getChainNameByChainId(_chainIdBytes);
    }

    /**
     * @inheritdoc IChainResolver
     */
    function chainId(bytes32 _labelhash) external view returns (bytes memory _chainId) {
        return registry.getChainId(_labelhash);
    }

    /**
     * @inheritdoc IChainResolver
     */
    function register(string calldata _chainName, address _owner, bytes calldata _chainId) external onlyOwner {
        // Delegate to registry
        IChainRegistry.ChainRecord[] memory records = new IChainRegistry.ChainRecord[](0);
        registry.registerChain(_chainName, _owner, _chainId, _chainName, records);
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
            IChainRegistry.ChainRecord[] memory records = new IChainRegistry.ChainRecord[](0);
            registry.registerChain(_chainNames[i], _owners[i], _chainIds[i], _chainNames[i], records);
        }
    }

    /**
     * @inheritdoc IChainResolver
     */
    function setLabelOwner(bytes32 _labelhash, address _owner) external {
        // This functionality is now handled by the registry's NFT ownership
        revert UseRegistryForOwnershipManagement();
    }

    /**
     * @inheritdoc IChainResolver
     */
    function setOperator(address _operator, bool _isOperator) external {
        // Operator management is handled directly by the registry
        revert UseRegistryForOwnershipManagement();
    }

    /**
     * @inheritdoc IChainResolver
     */
    function isAuthorized(bytes32 _labelhash, address _address) external view returns (bool _authorized) {
        return registry.isAuthorized(_labelhash, _address);
    }

    // ============ ENS Resolver Functions ============

    /**
     * @notice Set the ETH address (coin type 60) for a labelhash.
     * @param _labelhash The labelhash to update.
     * @param _addr The EVM address to set.
     */
    function setAddr(bytes32 _labelhash, address _addr) external {
        _checkAuthorization(_labelhash);
        bytes memory value = abi.encodePacked(_addr);
        registry.setENSAddress(_labelhash, 60, value);
        emit AddrChanged(_labelhash, _addr);
    }

    /**
     * @notice Set a multi-coin address for a given coin type.
     * @param _labelhash The labelhash to update.
     * @param _coinType The coin type (per ENSIP-11).
     * @param _value The raw address bytes encoded for that coin type.
     */
    function setAddr(bytes32 _labelhash, uint256 _coinType, bytes calldata _value) external {
        _checkAuthorization(_labelhash);
        registry.setENSAddress(_labelhash, _coinType, _value);
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
    function setContenthash(bytes32 _labelhash, bytes calldata _hash) external {
        _checkAuthorization(_labelhash);
        registry.setENSContentHash(_labelhash, _hash);
    }

    /**
     * @notice Set a text record for a labelhash.
     * @param _labelhash The labelhash to update.
     * @param _key The text record key.
     * @param _value The text record value.
     */
    function setText(bytes32 _labelhash, string calldata _key, string calldata _value) external {
        _checkAuthorization(_labelhash);
        registry.setENSText(_labelhash, _key, _value);
    }

    /**
     * @notice Set a data record for a labelhash.
     * @param _labelhash The labelhash to update.
     * @param _key The data record key.
     * @param _data The data record value.
     */
    function setData(bytes32 _labelhash, string calldata _key, bytes calldata _data) external {
        _checkAuthorization(_labelhash);
        registry.setENSData(_labelhash, _key, _data);
        emit DataChanged(_labelhash, _key, _key, _data);
    }

    /**
     * @notice Get the address for a labelhash with a specific coin type.
     * @param _labelhash The labelhash to query.
     * @param _coinType The coin type (default: 60 for Ethereum).
     * @return The address for this label and coin type.
     */
    function getAddr(bytes32 _labelhash, uint256 _coinType) external view returns (bytes memory) {
        string memory key = _makeKey(ENS_ADDRESS_PREFIX, _bytes32ToHex(_labelhash), ",", _uint256ToString(_coinType));
        return registry.getChainRecord(_labelhash, key);
    }

    /**
     * @notice Get the content hash for a labelhash.
     * @param _labelhash The labelhash to query.
     * @return The content hash for this label.
     */
    function getContenthash(bytes32 _labelhash) external view returns (bytes memory) {
        string memory key = _makeKey(ENS_CONTENTHASH_KEY, _labelhash);
        return registry.getChainRecord(_labelhash, key);
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
        return registry.getChainOwner(_labelhash);
    }

    // ============ Internal Resolution Functions ============

    /**
     * @notice Resolve address for a coin type
     * @param _labelhash The labelhash
     * @param _coinType The coin type
     * @return The address bytes
     */
    function _resolveAddress(bytes32 _labelhash, uint256 _coinType) internal view returns (bytes memory) {
        string memory key = _makeKey(ENS_ADDRESS_PREFIX, _bytes32ToHex(_labelhash), ",", _uint256ToString(_coinType));
        bytes memory value = registry.getChainRecord(_labelhash, key);
        
        if (value.length == 0) {
            return abi.encode("");
        }
        
        if (_coinType == ETHEREUM_COIN_TYPE) {
            return abi.encode(bytesToAddress(value));
        }
        
        return abi.encode(value);
    }

    /**
     * @notice Resolve content hash
     * @param _labelhash The labelhash
     * @return The content hash bytes
     */
    function _resolveContenthash(bytes32 _labelhash) internal view returns (bytes memory) {
        string memory key = _makeKey(ENS_CONTENTHASH_KEY, _bytes32ToHex(_labelhash));
        bytes memory contentHash = registry.getChainRecord(_labelhash, key);
        return abi.encode(contentHash);
    }

    /**
     * @notice Resolve text record with overrides
     * @param _labelhash The labelhash
     * @param _key The text key
     * @return The text value
     */
    function _resolveText(bytes32 _labelhash, string memory _key) internal view returns (bytes memory) {
        string memory value = _getTextWithOverrides(_labelhash, _key);
        return abi.encode(value);
    }

    /**
     * @notice Resolve data record with overrides
     * @param _labelhash The labelhash
     * @param _key The data key
     * @return The data value
     */
    function _resolveData(bytes32 _labelhash, string memory _key) internal view returns (bytes memory) {
        bytes memory value = _getDataWithOverrides(_labelhash, _key);
        return abi.encode(value);
    }

    // ============ Override Functions ============

    /**
     * @notice Internal function to handle text record keys with overrides
     * @param _labelhash The labelhash to query
     * @param _key The text record key
     * @return The text record value (with overrides for chain-id and chain-name:)
     */
    function _getTextWithOverrides(bytes32 _labelhash, string memory _key) internal view returns (string memory) {
        // Special case for "chain-id" text record
        if (keccak256(abi.encodePacked(_key)) == keccak256(abi.encodePacked(CHAIN_ID_KEY))) {
            bytes memory chainIdBytes = registry.getChainId(_labelhash);
            return HexUtils.bytesToHex(chainIdBytes);
        }

        // Check if key starts with "chain-name:" prefix (reverse resolution)
        // Only apply reverse lookup for reverse.cid.eth context
        bytes memory keyBytes = bytes(_key);
        bytes memory keyPrefixBytes = bytes(CHAIN_NAME_PREFIX);
        if (_startsWith(keyBytes, keyPrefixBytes)) {
            // For now, we'll apply reverse lookup to any chain-name: key
            // This could be refined to only apply in reverse.cid.eth context
            // Extract the chain ID from the key (everything after "chain-name:")
            bytes memory chainIdHexBytes = new bytes(keyBytes.length - keyPrefixBytes.length);
            for (uint i = 0; i < chainIdHexBytes.length; i++) {
                chainIdHexBytes[i] = keyBytes[i + keyPrefixBytes.length];
            }
            string memory chainIdHex = string(chainIdHexBytes);
            (bytes memory chainIdBytes, bool valid) = HexUtils.hexToBytes(bytes(chainIdHex), 0, bytes(chainIdHex).length);
            if (!valid) {
                return "";
            }
            return registry.getChainNameByChainId(chainIdBytes);
        }

        // Default: return stored text record
        string memory registryKey = _makeKey(ENS_TEXT_PREFIX, _bytes32ToHex(_labelhash), ":", _key);
        bytes memory value = registry.getChainRecord(_labelhash, registryKey);
        return string(value);
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
            return registry.getChainId(_labelhash);
        }

        // Default: return stored data record
        string memory registryKey = _makeKey(ENS_DATA_PREFIX, _bytes32ToHex(_labelhash), ":", _key);
        return registry.getChainRecord(_labelhash, registryKey);
    }

    // ============ Utility Functions ============

    /**
     * @notice Check authorization for a labelhash
     * @param _labelhash The labelhash to check
     */
    function _checkAuthorization(bytes32 _labelhash) internal view {
        if (!registry.isAuthorized(_labelhash, msg.sender)) {
            revert NotAuthorized(msg.sender, _labelhash);
        }
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

    /**
     * @notice Convert uint256 to string
     * @param _value The uint256 value
     * @return The string representation
     */
    function _uint256ToString(uint256 _value) internal pure returns (string memory) {
        if (_value == 0) {
            return "0";
        }
        uint256 temp = _value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (_value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(_value % 10)));
            _value /= 10;
        }
        return string(buffer);
    }
}