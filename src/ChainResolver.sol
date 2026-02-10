// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title ChainResolver
 * @author Thomas Clowes (clowes.eth) - <thomas@unruggable.com>
 * @notice Implementation of ERC-7828: Interoperable Addresses using ENS.
 * @dev Upgradeable via UUPS. Owner can upgrade directly.
 * @dev Repository: https://github.com/unruggable-labs/chain-resolver
 */
import {
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {
    Initializable
} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {
    UUPSUpgradeable
} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {
    IExtendedResolver
} from "@ensdomains/ens-contracts/contracts/resolvers/profiles/IExtendedResolver.sol";
import {
    NameCoder
} from "@ensdomains/ens-contracts/contracts/utils/NameCoder.sol";
import {IChainResolver} from "./interfaces/IChainResolver.sol";
import {ISupportedDataKeys} from "./interfaces/ISupportedDataKeys.sol";
import {ISupportedTextKeys} from "./interfaces/ISupportedTextKeys.sol";

// https://github.com/ensdomains/ens-contracts/blob/289913d7e3923228675add09498d66920216fe9b/contracts/resolvers/profiles/ITextResolver.sol
event TextChanged(
    bytes32 indexed node,
    string indexed indexedKey,
    string key,
    string value
);

contract ChainResolver is
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    IERC165,
    IExtendedResolver,
    IChainResolver,
    ISupportedDataKeys,
    ISupportedTextKeys
{
    /**
     * @notice Modifier to ensure only the chain owner can call the function
     * @param _labelhash The labelhash to check authorization for
     * @dev For the root 2LD, allows contract owner instead of chain owner
     */
    modifier onlyChainOwner(bytes32 _labelhash) {
        if (_labelhash == BASE_NAME_LABELHASH) {
            // Base name records can only be set by contract owner
            if (_msgSender() != owner()) {
                revert NotChainOwner(_msgSender(), _labelhash);
            }
        } else {
            bytes32 canonical = _resolveLabelhash(_labelhash);
            address _owner = chainOwners[canonical];
            if (_owner != _msgSender()) {
                revert NotChainOwner(_msgSender(), _labelhash);
            }
        }
        _;
    }

    // ENS method selectors
    bytes4 private constant ADDR_SELECTOR = bytes4(keccak256("addr(bytes32)"));
    bytes4 private constant ADDR_COINTYPE_SELECTOR =
        bytes4(keccak256("addr(bytes32,uint256)"));
    bytes4 private constant CONTENTHASH_SELECTOR =
        bytes4(keccak256("contenthash(bytes32)"));
    bytes4 private constant TEXT_SELECTOR =
        bytes4(keccak256("text(bytes32,string)"));
    bytes4 private constant DATA_SELECTOR =
        bytes4(keccak256("data(bytes32,string)"));

    // Cointype constants
    uint256 private constant ETHEREUM_COIN_TYPE = 60;

    // Data record key constants
    string private constant INTEROPERABLE_ADDRESS_DATA_KEY =
        "interoperable-address";
    bytes32 private constant INTEROPERABLE_ADDRESS_DATA_KEY_HASH =
        keccak256("interoperable-address");

    // Text record key constants
    string private constant CHAIN_LABEL_PREFIX = "chain-label:";
    bytes32 private constant REVERSE_LABELHASH = keccak256("reverse");
    
    // Sentinel value for base 2LD name - not an actual labelhash
    // The base 2LD has no third level label, so we use bytes32(0) as a placeholder
    bytes32 private constant BASE_NAME_LABELHASH = bytes32(0);

    // Parent namespace namehash. Used for computing full namehashes in events
    bytes32 public parentNamehash;

    // Chain data storage
    mapping(bytes32 labelhash => address owner) private chainOwners;
    mapping(bytes32 labelhash => string name) private chainNames;
    mapping(bytes interoperableAddress => string label)
        internal labelByInteroperableAddress;

    // Alias mapping. Alias labelhash => canonical labelhash
    mapping(bytes32 => bytes32) private aliasOf;

    // Label lookup by labelhash (for getCanonicalLabel efficiency)
    mapping(bytes32 labelhash => string label) private labelByLabelhash;

    // Discoverability
    // Total number of registered chains
    uint256 public chainCount;
    // Known labelhashes
    bytes32[] private labelhashList;

    // ENS record storage
    mapping(bytes32 labelhash => mapping(uint256 coinType => bytes value))
        private addressRecords;
    mapping(bytes32 labelhash => bytes contenthash) private contenthashRecords;
    mapping(bytes32 labelhash => mapping(string key => string value))
        private textRecords;
    mapping(bytes32 labelhash => mapping(string key => bytes data))
        private dataRecords;

    // Data key tracking for ISupportedDataKeys
    mapping(bytes32 labelhash => string[] keys) private dataKeys;
    mapping(bytes32 labelhash => mapping(bytes32 keyHash => bool exists))
        private dataKeyExists;

    // Text key tracking for ISupportedTextKeys
    mapping(bytes32 labelhash => string[] keys) private textKeys;
    mapping(bytes32 labelhash => mapping(bytes32 keyHash => bool exists))
        private textKeyExists;

    // Node to labelhash mapping. Used for events emission supportedTextKeys/supportedDataKeys
    mapping(bytes32 node => bytes32 labelhash) private nodeToLabelhash;

    // Default contenthash used when no specific contenthash is set
    bytes public defaultContenthash;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the contract
     * @param _owner The address to set as the owner
     * @param _parentNamehash The namehash of the parent namespace (e.g., namehash("on.eth"))
     */
    function initialize(
        address _owner,
        bytes32 _parentNamehash
    ) external initializer {
        __Ownable_init(_owner);
        parentNamehash = _parentNamehash;
        emit ParentNamehashChanged(_parentNamehash);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) external pure override returns (bool) {
        return
            interfaceId == type(IERC165).interfaceId ||
            interfaceId == type(IExtendedResolver).interfaceId ||
            interfaceId == type(IChainResolver).interfaceId ||
            interfaceId == type(ISupportedDataKeys).interfaceId ||
            interfaceId == type(ISupportedTextKeys).interfaceId;
    }

    /**
     * @notice For a specific `node`, get an array of supported data keys.
     * @dev Implements ISupportedDataKeys (ENSIP-24). Uses nodeToLabelhash mapping to resolve
     *      the labelhash from the node, then returns the data keys stored for that labelhash.
     * @param node The node (namehash) to query.
     * @return The keys for which we have associated data records.
     */
    function supportedDataKeys(bytes32 node) external view override returns (string[] memory) {
        return dataKeys[nodeToLabelhash[node]];
    }

    /**
     * @notice For a specific `node`, get an array of supported text keys.
     * @dev Implements ISupportedTextKeys. Uses nodeToLabelhash mapping to resolve
     *      the labelhash from the node, then returns the text keys stored for that labelhash.
     * @param node The node (namehash) to query.
     * @return The keys for which we have associated text records.
     */
    function supportedTextKeys(bytes32 node) external view override returns (string[] memory) {
        return textKeys[nodeToLabelhash[node]];
    }

    /**
     * @notice UUPS authorization - only owner can upgrade.
     */
    function _authorizeUpgrade(address) internal override onlyOwner {}

    //////
    /// RESOLUTION
    //////

    /**
     * @notice Resolve data for a DNS-encoded name using ENSIP-10.
     * @param name The DNS-encoded name.
     * @param data The ABI-encoded ENS method calldata.
     * @return The resolved data based on the method selector.
     */
    function resolve(
        bytes calldata name,
        bytes calldata data
    ) external view override returns (bytes memory) {
        // Compute namehash from DNS-encoded name to check if it's the base name
        bytes32 namehash = NameCoder.namehash(name, 0);
        bytes32 labelhash;
        
        // If this is the parent namehash, use BASE_NAME_LABELHASH for base name records
        if (namehash == parentNamehash) {
            labelhash = BASE_NAME_LABELHASH;
        } else {
            // Extract the first labelhash from the DNS-encoded name
            (labelhash, , , ) = NameCoder.readLabel(name, 0, true);
        }

        // Get the method selector (first 4 bytes)
        bytes4 selector = bytes4(data);

        if (selector == ADDR_SELECTOR) {
            // addr(bytes32)
            bytes memory v = _getAddr(labelhash, ETHEREUM_COIN_TYPE);
            if (v.length == 0) {
                return abi.encode(address(0));
            }
            return abi.encode(bytesToAddress(v));
        } else if (selector == ADDR_COINTYPE_SELECTOR) {
            // addr(bytes32,uint256)
            (, uint256 coinType) = abi.decode(data[4:], (bytes32, uint256));
            bytes memory a = _getAddr(labelhash, coinType);
            return abi.encode(a);
        } else if (selector == CONTENTHASH_SELECTOR) {
            // contenthash(bytes32)
            bytes memory contenthash = _getContenthash(labelhash);
            return abi.encode(contenthash);
        } else if (selector == TEXT_SELECTOR) {
            // text(bytes32,string)
            (, string memory key) = abi.decode(data[4:], (bytes32, string));
            string memory value = _getText(labelhash, key);
            return abi.encode(value);
        } else if (selector == DATA_SELECTOR) {
            // data(bytes32,string)
            (, string memory keyStr) = abi.decode(data[4:], (bytes32, string));
            bytes memory dataValue = _getData(labelhash, keyStr);
            return abi.encode(dataValue);
        }

        // Return empty bytes if no selector matches
        return abi.encode("");
    }

    //////
    /// SETTERS
    //////

    function setChainAdmin(
        bytes32 _labelhash,
        address _owner
    ) external onlyChainOwner(_labelhash) {
        if (_owner == address(0)) {
            revert InvalidChainAdmin();
        }

        bytes32 canonical = _resolveLabelhash(_labelhash);

        if (canonical == REVERSE_LABELHASH) {
            revert ReverseNodeOwnershipBlock();
        }

        chainOwners[canonical] = _owner;
        emit ChainAdminSet(canonical, _owner);
    }

    /**
     * @notice Set the address for a given coinType.
     * @param _labelhash The labelhash to update.
     * @param _coinType The coin type (per ENSIP-11).
     * @param _value The raw address bytes encoded for that coin type.
     */
    function setAddr(
        bytes32 _labelhash,
        uint256 _coinType,
        bytes calldata _value
    ) external onlyChainOwner(_labelhash) {
        bytes32 canonical = _resolveLabelhash(_labelhash);
        addressRecords[canonical][_coinType] = _value;
        bytes32 node = _computeNamehash(canonical);
        emit AddressChanged(node, _coinType, _value);
        if (_coinType == ETHEREUM_COIN_TYPE) {
            emit AddrChanged(node, bytesToAddress(_value));
        }
    }

    /**
     * @notice Set a text record for a labelhash.
     * @dev Blocks immutable keys.
     * @param _labelhash The labelhash to update.
     * @param _key The text record key.
     * @param _value The text record value.
     */
    function setText(
        bytes32 _labelhash,
        string calldata _key,
        string calldata _value
    ) external onlyChainOwner(_labelhash) {
        _setText(_resolveLabelhash(_labelhash), _key, _value);
    }

    /**
     * @notice Batch set multiple text records for a labelhash.
     * @param _labelhash The labelhash to update.
     * @param _keys Array of text record keys.
     * @param _values Array of text record values.
     */
    function batchSetText(
        bytes32 _labelhash,
        string[] calldata _keys,
        string[] calldata _values
    ) external onlyChainOwner(_labelhash) {
        if (_keys.length != _values.length) {
            revert ArrayLengthMismatch();
        }
        bytes32 canonical = _resolveLabelhash(_labelhash);
        uint256 len = _keys.length;
        for (uint256 i = 0; i < len; i++) {
            _setText(canonical, _keys[i], _values[i]);
        }
    }

    /**
     * @notice Set a text record for a labelhash.
     * @param _labelhash The labelhash to update.
     * @param _key The text record key.
     * @param _value The text record value.
     */
    function _setText(
        bytes32 _labelhash,
        string memory _key,
        string memory _value
    ) internal {
        textRecords[_labelhash][_key] = _value;

        // Track the key for supportedTextKeys
        bytes32 keyHash = keccak256(bytes(_key));
        if (!textKeyExists[_labelhash][keyHash]) {
            textKeyExists[_labelhash][keyHash] = true;
            textKeys[_labelhash].push(_key);
        }

        // Compute node and update reverse mapping for supportedTextKeys interface
        bytes32 node = _computeNamehash(_labelhash);
        nodeToLabelhash[node] = _labelhash;

        emit TextChanged(node, _key, _key, _value);
    }

    /**
     * @notice Set the default contenthash used when no specific contenthash is set.
     * @param _contenthash The default contenthash to set.
     */
    function setDefaultContenthash(bytes calldata _contenthash) external onlyOwner {
        defaultContenthash = _contenthash;
        bytes32 baseNode = _computeNamehash(BASE_NAME_LABELHASH);
        emit ContenthashChanged(baseNode, _contenthash);
    }

    /**
     * @notice Set the contenthash for a labelhash.
     * @param _labelhash The labelhash to update. Use bytes32(0) for base name.
     * @param _contenthash The contenthash to set.
     */
    function setContenthash(
        bytes32 _labelhash,
        bytes calldata _contenthash
    ) external onlyChainOwner(_labelhash) {
        bytes32 canonical = _resolveLabelhash(_labelhash);
        contenthashRecords[canonical] = _contenthash;
        
        // Update node mapping for supportedTextKeys/supportedDataKeys
        bytes32 node = _computeNamehash(canonical);
        nodeToLabelhash[node] = canonical;
        
        emit ContenthashChanged(node, _contenthash);
    }

    /**
     * @notice Set a data record for a labelhash.
     * @dev Blocks immutable keys.
     * @param _labelhash The labelhash to update.
     * @param _key The data record key.
     * @param _data The data record value.
     */
    function setData(
        bytes32 _labelhash,
        string calldata _key,
        bytes calldata _data
    ) external onlyChainOwner(_labelhash) {
        if (keccak256(bytes(_key)) == INTEROPERABLE_ADDRESS_DATA_KEY_HASH) {
            revert ImmutableDataKey(_labelhash, _key);
        }

        _setData(_resolveLabelhash(_labelhash), _key, _data);
    }

    /**
     * @notice Batch set multiple data records for a labelhash.
     * @param _labelhash The labelhash to update.
     * @param _keys Array of data record keys.
     * @param _data Array of data record values.
     */
    function batchSetData(
        bytes32 _labelhash,
        string[] calldata _keys,
        bytes[] calldata _data
    ) external onlyChainOwner(_labelhash) {
        if (_keys.length != _data.length) {
            revert ArrayLengthMismatch();
        }
        bytes32 canonical = _resolveLabelhash(_labelhash);
        uint256 len = _keys.length;
        for (uint256 i = 0; i < len; i++) {
            if (keccak256(bytes(_keys[i])) == INTEROPERABLE_ADDRESS_DATA_KEY_HASH) {
                revert ImmutableDataKey(_labelhash, _keys[i]);
            }
            _setData(canonical, _keys[i], _data[i]);
        }
    }

    /**
     * @notice Set a data record for a labelhash.
     * @param _labelhash The labelhash to update.
     * @param _key The data record key.
     * @param _data The data record value.
     */
    function _setData(
        bytes32 _labelhash,
        string memory _key,
        bytes memory _data
    ) internal {
        dataRecords[_labelhash][_key] = _data;

        // Track the key for supportedDataKeys
        bytes32 keyHash = keccak256(bytes(_key));
        if (!dataKeyExists[_labelhash][keyHash]) {
            dataKeyExists[_labelhash][keyHash] = true;
            dataKeys[_labelhash].push(_key);
        }

        // Compute node and update reverse mapping for supportedDataKeys interface
        bytes32 node = _computeNamehash(_labelhash);
        nodeToLabelhash[node] = _labelhash;

        emit DataChanged(node, _key, _key, _data);
    }

    //////
    /// GETTERS
    //////

    /**
     * @notice Return the canonical chain label for a given ERC-7930 Interoperable Address.
     * @dev Implements reverse resolution (ERC-7828). Looks up the chain label stored in the
     *      reverse node's text record using the key format "chain-label:<interoperable-address>".
     *      Returns empty string if no label is registered for the given interoperable address.
     * @param _interoperableAddress The ERC-7930 Interoperable Address bytes.
     * @return The chain label (e.g., "optimism") or empty string if not found.
     */
    function chainLabel(
        bytes calldata _interoperableAddress
    ) external view returns (string memory) {
        return
            _getText(
                REVERSE_LABELHASH,
                concat(CHAIN_LABEL_PREFIX, _interoperableAddress)
            );
    }

    /**
     * @notice Get the chain name for a label string.
     * @param _label The chain label (e.g., "optimism").
     * @return The chain name.
     */
    function chainName(
        string calldata _label
    ) external view returns (string memory) {
        bytes32 _labelhash = keccak256(bytes(_label));
        return chainNames[_resolveLabelhash(_labelhash)];
    }

    /**
     * @notice Get the interoperable address for a label string.
     * @param _label The chain label (e.g., "optimism").
     * @return The interoperable address bytes.
     */
    function interoperableAddress(
        string calldata _label
    ) external view returns (bytes memory) {
        bytes32 _labelhash = keccak256(bytes(_label));
        return
            _getData(
                _resolveLabelhash(_labelhash),
                INTEROPERABLE_ADDRESS_DATA_KEY
            );
    }

        /**
     * @notice Get the address for a label with a specific coin type.
     * @param _label The label string to query.
     * @param _coinType The coin type (default: 60 for Ethereum).
     * @return The address for this label and coin type.
     */
    function getAddr(
        string calldata _label,
        uint256 _coinType
    ) external view returns (bytes memory) {
        bytes32 _labelhash = keccak256(bytes(_label));
        return _getAddr(_labelhash, _coinType);
    }

    /**
     * @notice Get a text record for a label.
     * @param _label The label string to query.
     * @param _key The text record key.
     * @return The text record value (with special handling for chain-id and chain-name:).
     */
    function getText(
        string calldata _label,
        string calldata _key
    ) external view returns (string memory) {
        bytes32 _labelhash = keccak256(bytes(_label));
        return _getText(_labelhash, _key);
    }

    /**
     * @notice Get the content hash for a label.
     * @param _label The label string to query.
     * @return The content hash for this label.
     */
    function getContenthash(
        string calldata _label
    ) external view returns (bytes memory) {
        bytes32 _labelhash = keccak256(bytes(_label));
        return _getContenthash(_labelhash);
    }

    /**
     * @notice Get a data record for a label.
     * @param _label The label string to query.
     * @param _key The data record key.
     * @return The data record value (with special handling for chain-id).
     */
    function getData(
        string calldata _label,
        string calldata _key
    ) external view returns (bytes memory) {
        bytes32 _labelhash = keccak256(bytes(_label));
        return _getData(_labelhash, _key);
    }

    /**
     * @notice Get the admin for a chain.
     * @param _label The label string to query.
     * @return The owner address.
     */
    function getChainAdmin(string calldata _label) external view returns (address) {
        bytes32 _labelhash = keccak256(bytes(_label));
        return chainOwners[_resolveLabelhash(_labelhash)];
    }

    /**
     * @notice Get the canonical label information for an alias.
     * @param _label The label string to check.
     * @return info The canonical label info (label and labelhash), or empty if not an alias.
     */
    function getCanonicalLabel(
        string calldata _label
    ) external view returns (IChainResolver.CanonicalLabelInfo memory info) {
        bytes32 _labelhash = keccak256(bytes(_label));
        bytes32 canonicalLabelhash = aliasOf[_labelhash];
        if (canonicalLabelhash == bytes32(0)) {
            return info;
        }
        info.label = labelByLabelhash[canonicalLabelhash];
        info.labelhash = canonicalLabelhash;
    }

    //////
    /// INTERNAL Getters
    //////
    
    /**
     * @notice Get address records for a specific coin type.
     * @param _labelhash The labelhash to query.
     * @param _coinType The coin type (default: 60 for Ethereum).
     * @return The address for this label and coin type.
     */
    function _getAddr(
        bytes32 _labelhash,
        uint256 _coinType
    ) internal view returns (bytes memory) {
        return addressRecords[_resolveLabelhash(_labelhash)][_coinType];
    }

    /**
     * @notice Get text records.
     * @param _labelhash The labelhash to query.
     * @param _key The text record key.
     * @return The text record value.
     */
    function _getText(
        bytes32 _labelhash,
        string memory _key
    ) internal view returns (string memory) {
        return textRecords[_resolveLabelhash(_labelhash)][_key];
    }

    /**
     * @notice Get a contenthash.
     * @param _labelhash The labelhash to query.
     * @return The contenthash value. Returns defaultContenthash if no specific contenthash is set.
     */
    function _getContenthash(
        bytes32 _labelhash
    ) internal view returns (bytes memory) {
        bytes memory specific = contenthashRecords[_resolveLabelhash(_labelhash)];
        if (specific.length > 0) {
            return specific;
        }
        return defaultContenthash;
    }

    /**
     * @notice Get a data record.
     * @param _labelhash The labelhash to query.
     * @param _key The data record key.
     * @return The data record value (with override for chain-id).
     */
    function _getData(
        bytes32 _labelhash,
        string memory _key
    ) internal view returns (bytes memory) {
        return dataRecords[_resolveLabelhash(_labelhash)][_key];
    }

    //////
    /// REGISTRATION
    //////

    function register(ChainRegistrationData calldata data) external onlyOwner {
        _register(
            data.label,
            data.chainName,
            data.owner,
            data.interoperableAddress
        );
    }

    function batchRegister(
        ChainRegistrationData[] calldata data
    ) external onlyOwner {
        uint256 _length = data.length;
        for (uint256 i = 0; i < _length; i++) {
            _register(
                data[i].label,
                data[i].chainName,
                data[i].owner,
                data[i].interoperableAddress
            );
        }
    }

    /**
     * @notice Register an individual chain.
     * @param _label The short chain label (e.g., "optimism").
     * @param _chainName The chain name (e.g., "Optimism").
     * @param _owner The owner address.
     * @param _interoperableAddress The Interoperable Address (ERC-7930).
     */
    function _register(
        string calldata _label,
        string calldata _chainName,
        address _owner,
        bytes calldata _interoperableAddress
    ) internal {
        // Validate inputs
        if (bytes(_label).length == 0) {
            revert EmptyLabel();
        }
        if (bytes(_chainName).length == 0) {
            revert EmptyChainName();
        }
        if (_interoperableAddress.length < 7) {
            revert InvalidInteroperableAddress();
        }
        if (_owner == address(0)) {
            revert InvalidChainAdmin();
        }

        bytes32 _labelhash = keccak256(bytes(_label));

        bool isNew = bytes(chainNames[_labelhash]).length == 0;


        chainNames[_labelhash] = _chainName;
        chainOwners[_labelhash] = _owner;
        labelByLabelhash[_labelhash] = _label;

        _setData(
            _labelhash,
            INTEROPERABLE_ADDRESS_DATA_KEY,
            _interoperableAddress
        );
        _setText(
            REVERSE_LABELHASH,
            concat(CHAIN_LABEL_PREFIX, _interoperableAddress),
            _label
        );

        // Map the Interoperable Address back to the chain label (for reverse resolution)
        labelByInteroperableAddress[_interoperableAddress] = _label;

        if (isNew) {
            labelhashList.push(_labelhash);
            unchecked {
                chainCount += 1;
            }
        } else {
            // Clear old Interoperable Address mappings if re-registering
            bytes memory oldAddress = dataRecords[_labelhash][INTEROPERABLE_ADDRESS_DATA_KEY];
            if (oldAddress.length > 0 && keccak256(oldAddress) != keccak256(_interoperableAddress)) {
                delete labelByInteroperableAddress[oldAddress];
                delete textRecords[REVERSE_LABELHASH][concat(CHAIN_LABEL_PREFIX, oldAddress)];
            }
        }

        emit ChainAdminSet(_labelhash, _owner);
        emit ChainRegistered(_labelhash, _chainName, _interoperableAddress);
    }

    /**
     * @notice Register an alias that points to a canonical labelhash.
     * @param _alias The alias string (e.g., "op").
     * @param _canonicalLabelhash The canonical labelhash to point to (e.g., keccak256("optimism")).
     */
    function registerAlias(
        string calldata _alias,
        bytes32 _canonicalLabelhash
    ) external onlyOwner {
        _registerAlias(_alias, _canonicalLabelhash);
    }

    /**
     * @notice Batch register aliases that point to canonical labelhashes.
     * @param _aliases Array of alias strings.
     * @param _canonicalLabelhashes Array of canonical labelhashes to point to.
     */
    function batchRegisterAlias(
        string[] calldata _aliases,
        bytes32[] calldata _canonicalLabelhashes
    ) external onlyOwner {
        if (_aliases.length != _canonicalLabelhashes.length) {
            revert ArrayLengthMismatch();
        }
        uint256 _length = _aliases.length;
        for (uint256 i = 0; i < _length; i++) {
            _registerAlias(_aliases[i], _canonicalLabelhashes[i]);
        }
    }

    /**
     * @notice Register an alias.
     * @param _alias The alias string (e.g., "op").
     * @param _canonicalLabelhash The canonical labelhash to point to.
     */
    function _registerAlias(
        string calldata _alias,
        bytes32 _canonicalLabelhash
    ) internal {
        bytes32 aliasHash = keccak256(bytes(_alias));

        // Prevent alias chains (op → optimism → something-else)
        if (aliasOf[_canonicalLabelhash] != bytes32(0)) {
            revert CannotAliasToAlias();
        }

        // Ensure canonical is actually registered
        if (chainOwners[_canonicalLabelhash] == address(0)) {
            revert CanonicalNotRegistered();
        }

        aliasOf[aliasHash] = _canonicalLabelhash;
        labelByLabelhash[aliasHash] = _alias;

        // Map alias node → canonical labelhash for supportedDataKeys
        nodeToLabelhash[_computeNamehash(aliasHash)] = _canonicalLabelhash;

        emit AliasRegistered(aliasHash, _canonicalLabelhash, _alias);
    }

    /**
     * @notice Remove an alias.
     * @param _alias The alias string to remove.
     */
    function removeAlias(string calldata _alias) external onlyOwner {
        bytes32 aliasHash = keccak256(bytes(_alias));
        bytes32 canonical = aliasOf[aliasHash];
        if (canonical == bytes32(0)) {
            revert AliasDoesNotExist();
        }

        delete aliasOf[aliasHash];
        delete labelByLabelhash[aliasHash];
        delete nodeToLabelhash[_computeNamehash(aliasHash)];
        emit AliasRemoved(aliasHash, canonical, _alias);
    }

    //////
    /// DISCOVERABILITY
    //////

    /**
     * @notice Return the chain label and chain name at a given index.
     * @param _index The index in the chain list
     * @return _label The short chain label (e.g., "optimism")
     * @return _chainName The chain name (e.g., "Optimism")
     * @return _interoperableAddress The Interoperable Addres (ERC-7930)
     */
    function getChainAtIndex(
        uint256 _index
    )
        external
        view
        returns (
            string memory _label,
            string memory _chainName,
            bytes memory _interoperableAddress
        )
    {
        if (_index >= labelhashList.length) revert IndexOutOfRange();
        bytes32 labelhash = labelhashList[_index];
        _chainName = chainNames[labelhash];
        _interoperableAddress = _getData(
            labelhash,
            INTEROPERABLE_ADDRESS_DATA_KEY
        );
        _label = _getText(
            REVERSE_LABELHASH,
            concat(CHAIN_LABEL_PREFIX, _interoperableAddress)
        );
    }

    //////
    /// HELPERS
    //////

    /**
     * @notice Resolves an alias to its canonical labelhash, or returns the input if not an alias.
     * @param _labelhash The labelhash to resolve.
     * @return The canonical labelhash.
     */
    function _resolveLabelhash(
        bytes32 _labelhash
    ) internal view returns (bytes32) {
        bytes32 canonical = aliasOf[_labelhash];
        return canonical == bytes32(0) ? _labelhash : canonical;
    }

    /**
     * @notice Computes the full ENS namehash from a labelhash using the parent namespace.
     * @param _labelhash The labelhash of the label.
     * @return The full namehash (e.g., namehash("optimism.on.eth") from labelhash("optimism")).
     * @dev For BASE_NAME_LABELHASH (bytes32(0)), returns parentNamehash directly.
     */
    function _computeNamehash(
        bytes32 _labelhash
    ) internal view returns (bytes32) {
        if (_labelhash == BASE_NAME_LABELHASH) {
            return parentNamehash;
        }
        return keccak256(abi.encodePacked(parentNamehash, _labelhash));
    }
    
    /**
     * @notice Concatenates a string with bytes (as hex string) into a single string.
     * @param _str The string prefix.
     * @param _data The bytes to append as hex.
     * @return The concatenated string.
     */
    function concat(
        string memory _str,
        bytes memory _data
    ) internal pure returns (string memory) {
        return string(abi.encodePacked(_str, bytesToHexString(_data)));
    }

    /**
     * @notice Converts bytes to a hex string (without 0x prefix).
     * @param _data The bytes to convert.
     * @return The hex string representation.
     */
    function bytesToHexString(
        bytes memory _data
    ) internal pure returns (string memory) {
        bytes memory hexChars = "0123456789abcdef";
        bytes memory result = new bytes(_data.length * 2);
        for (uint256 i = 0; i < _data.length; i++) {
            result[i * 2] = hexChars[uint8(_data[i] >> 4)];
            result[i * 2 + 1] = hexChars[uint8(_data[i] & 0x0f)];
        }
        return string(result);
    }

    /**
     * @notice Decodes a packed 20-byte value into an EVM address.
     * @param b The 20-byte sequence.
     * @return a The decoded payable address.
     * @dev Reverts if `b.length != 20`.
     */
    function bytesToAddress(
        bytes memory b
    ) internal pure returns (address payable a) {
        if (b.length != 20) {
            revert InvalidAddressLength();
        }
        assembly {
            a := div(mload(add(b, 32)), exp(256, 12))
        }
    }
}
