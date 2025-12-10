// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title ChainResolver
 * @author Unruggable
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
    IChainResolver
{
    /**
     * @notice Modifier to ensure only the chain owner can call the function
     * @param _labelhash The labelhash to check authorization for
     */
    modifier onlyChainOwner(bytes32 _labelhash) {
        bytes32 canonical = _resolveLabelhash(_labelhash);
        address _owner = chainOwners[canonical];
        if (_owner != _msgSender()) {
            revert NotChainOwner(_msgSender(), _labelhash);
        }
        _;
    }

    // ENS method selectors
    bytes4 public constant ADDR_SELECTOR = bytes4(keccak256("addr(bytes32)"));
    bytes4 public constant ADDR_COINTYPE_SELECTOR =
        bytes4(keccak256("addr(bytes32,uint256)"));
    bytes4 public constant CONTENTHASH_SELECTOR =
        bytes4(keccak256("contenthash(bytes32)"));
    bytes4 public constant TEXT_SELECTOR =
        bytes4(keccak256("text(bytes32,string)"));
    bytes4 public constant DATA_SELECTOR =
        bytes4(keccak256("data(bytes32,string)"));

    // Cointype constants
    uint256 public constant ETHEREUM_COIN_TYPE = 60;

    // Data record key constants
    string public constant INTEROPERABLE_ADDRESS_DATA_KEY =
        "interoperable-address";
    bytes32 private constant INTEROPERABLE_ADDRESS_DATA_KEY_HASH =
        keccak256("interoperable-address");

    // Text record key constants
    string public constant CHAIN_LABEL_PREFIX = "chain-label:";
    bytes32 public constant REVERSE_LABELHASH = keccak256("reverse");

    // Parent namespace namehash (e.g., namehash("cid.eth")) for computing full namehashes in events
    bytes32 public parentNamehash;

    // Chain data storage
    mapping(bytes32 labelhash => address owner) private chainOwners;
    mapping(bytes32 labelhash => string name) private chainNames;
    mapping(bytes interoperableAddress => string label)
        internal labelByInteroperableAddress;

    // Alias mapping. Alias labelhash → canonical labelhash
    mapping(bytes32 => bytes32) private aliasOf;

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

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the contract (replaces constructor for upgradeable contracts)
     * @param _owner The address to set as the owner
     * @param _parentNamehash The namehash of the parent namespace (e.g., namehash("cid.eth"))
     */
    function initialize(
        address _owner,
        bytes32 _parentNamehash
    ) external initializer {
        __Ownable_init(_owner);
        parentNamehash = _parentNamehash;
    }

    function supportsInterface(
        bytes4 interfaceId
    ) external pure override returns (bool) {
        return
            interfaceId == type(IERC165).interfaceId ||
            interfaceId == type(IExtendedResolver).interfaceId ||
            interfaceId == type(IChainResolver).interfaceId;
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
        // Extract the first labelhash from the DNS-encoded name
        (bytes32 labelhash, , , ) = NameCoder.readLabel(name, 0, true);

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
        bytes32 canonical = _resolveLabelhash(_labelhash);

        if (canonical == REVERSE_LABELHASH) {
            revert ReverseNodeOwnershipBlock();
        }

        chainOwners[canonical] = _owner;
        emit ChainAdminSet(canonical, _owner);
    }

    /**
     * @notice EXTERNAL Set the address for a given coinType.
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
     * @dev EXTERNAL - blocks immutable keys
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
     * @notice INTERNAL Set a text record for a labelhash.
     * @param _labelhash The labelhash to update.
     * @param _key The text record key.
     * @param _value The text record value.
     * @dev Note: "chain-id" text record will be stored but not used - resolve() overrides it with internal registry value.
     */
    function _setText(
        bytes32 _labelhash,
        string memory _key,
        string memory _value
    ) internal {
        textRecords[_labelhash][_key] = _value;
        emit TextChanged(_computeNamehash(_labelhash), _key, _key, _value);
    }

    /**
     * @notice Set the contenthash for a labelhash.
     * @param _labelhash The labelhash to update.
     * @param _contenthash The contenthash to set.
     */
    function setContenthash(
        bytes32 _labelhash,
        bytes calldata _contenthash
    ) external onlyChainOwner(_labelhash) {
        contenthashRecords[_resolveLabelhash(_labelhash)] = _contenthash;
    }

    /**
     * @notice Set a data record for a labelhash.
     * @dev EXTERNAL - blocks immutable keys
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
     * @notice INTERNAL Set a data record for a labelhash.
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
        emit DataChanged(
            _computeNamehash(_labelhash),
            _key,
            keccak256(bytes(_key)),
            keccak256(_data)
        );
    }

    //////
    /// GETTERS
    //////

    function chainLabel(
        bytes calldata _interoperableAddress
    ) external view returns (string memory) {
        return
            _getText(
                REVERSE_LABELHASH,
                concat(CHAIN_LABEL_PREFIX, _interoperableAddress)
            );
    }

    function chainName(
        bytes calldata _interoperableAddress
    ) external view returns (string memory) {
        string memory _label = _getText(
            REVERSE_LABELHASH,
            concat(CHAIN_LABEL_PREFIX, _interoperableAddress)
        );
        bytes32 _labelhash = keccak256(bytes(_label));
        return chainNames[_resolveLabelhash(_labelhash)];
    }

    function interoperableAddress(
        bytes32 _labelhash
    ) external view returns (bytes memory) {
        return
            _getData(
                _resolveLabelhash(_labelhash),
                INTEROPERABLE_ADDRESS_DATA_KEY
            );
    }

    /**
     * @notice Get the address for a labelhash with a specific coin type.
     * @param _labelhash The labelhash to query.
     * @param _coinType The coin type (default: 60 for Ethereum).
     * @return The address for this label and coin type.
     */
    function getAddr(
        bytes32 _labelhash,
        uint256 _coinType
    ) external view returns (bytes memory) {
        return _getAddr(_labelhash, _coinType);
    }

    /**
     * @notice Get a text record for a labelhash.
     * @param _labelhash The labelhash to query.
     * @param _key The text record key.
     * @return The text record value (with special handling for chain-id and chain-name:).
     */
    function getText(
        bytes32 _labelhash,
        string calldata _key
    ) external view returns (string memory) {
        return _getText(_labelhash, _key);
    }

    /**
     * @notice Get the content hash for a labelhash.
     * @param _labelhash The labelhash to query.
     * @return The content hash for this label.
     */
    function getContenthash(
        bytes32 _labelhash
    ) external view returns (bytes memory) {
        return _getContenthash(_labelhash);
    }

    /**
     * @notice Get a data record for a labelhash.
     * @param _labelhash The labelhash to query.
     * @param _key The data record key.
     * @return The data record value (with special handling for chain-id).
     */
    function getData(
        bytes32 _labelhash,
        string calldata _key
    ) external view returns (bytes memory) {
        return _getData(_labelhash, _key);
    }

    /**
     * @notice Get the admin for a chain
     * @param _labelhash The labelhash to query.
     * @return The owner address.
     */
    function getChainAdmin(bytes32 _labelhash) external view returns (address) {
        return chainOwners[_resolveLabelhash(_labelhash)];
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
     * @notice Register an alias that points to a canonical labelhash.
     * @param _alias The alias string (e.g., "op").
     * @param _canonicalLabelhash The canonical labelhash to point to (e.g., keccak256("optimism")).
     */
    function registerAlias(
        string calldata _alias,
        bytes32 _canonicalLabelhash
    ) external onlyOwner {
        bytes32 aliasHash = keccak256(bytes(_alias));

        // Prevent alias chains (op → optimism → something-else)
        require(
            aliasOf[_canonicalLabelhash] == bytes32(0),
            "Cannot alias to an alias"
        );

        // Ensure canonical is actually registered
        require(
            chainOwners[_canonicalLabelhash] != address(0),
            "Canonical not registered"
        );

        aliasOf[aliasHash] = _canonicalLabelhash;
        emit AliasRegistered(aliasHash, _canonicalLabelhash, _alias);
    }

    /**
     * @notice Remove an alias.
     * @param _alias The alias string to remove.
     */
    function removeAlias(string calldata _alias) external onlyOwner {
        bytes32 aliasHash = keccak256(bytes(_alias));
        bytes32 canonical = aliasOf[aliasHash];
        require(canonical != bytes32(0), "Alias does not exist");

        delete aliasOf[aliasHash];
        emit AliasRemoved(aliasHash, canonical, _alias);
    }

    /**
     * @notice Get the canonical labelhash for an alias.
     * @param _labelhash The labelhash to check.
     * @return The canonical labelhash, or bytes32(0) if not an alias.
     */
    function getCanonicalLabelhash(
        bytes32 _labelhash
    ) external view returns (bytes32) {
        return aliasOf[_labelhash];
    }

    /**
     * @notice Internal helper function to register an individual chain
     * @param _label The short chain label (e.g., "optimism")
     * @param _chainName The chain name (e.g., "Optimism")
     * @param _owner The owner address
     * @param _interoperableAddress The Interoperable Address (ERC-7930)
     */
    function _register(
        string calldata _label,
        string calldata _chainName,
        address _owner,
        bytes calldata _interoperableAddress
    ) internal {
        bytes32 _labelhash = keccak256(bytes(_label));

        bool isUpdate = chainOwners[_labelhash] != address(0);

        chainNames[_labelhash] = _chainName;
        chainOwners[_labelhash] = _owner;

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

        if (!isUpdate) {
            labelhashList.push(_labelhash);
            unchecked {
                chainCount += 1;
            }
        }

        emit ChainAdminSet(_labelhash, _owner);
        emit ChainRegistered(_labelhash, _chainName, _interoperableAddress);
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
    /// INTERNAL Getters
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
     * @return The full namehash (e.g., namehash("optimism.cid.eth") from labelhash("optimism")).
     * @dev Uses the formula: namehash(label.parent) = keccak256(namehash(parent) + labelhash(label))
     */
    function _computeNamehash(
        bytes32 _labelhash
    ) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(parentNamehash, _labelhash));
    }

    /**
     * @notice INTERNAL function for getting address records for a specific coin type.
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
     * @notice INTERNAL function for getting text records
     * @param _labelhash The labelhash to query
     * @param _key The text record key
     * @return The text record value
     */
    function _getText(
        bytes32 _labelhash,
        string memory _key
    ) internal view returns (string memory) {
        return textRecords[_resolveLabelhash(_labelhash)][_key];
    }

    /**
     * @notice INTERNAL function for getting a contenthash
     * @param _labelhash The labelhash to query
     * @return The contenthash value
     */
    function _getContenthash(
        bytes32 _labelhash
    ) internal view returns (bytes memory) {
        return contenthashRecords[_resolveLabelhash(_labelhash)];
    }

    /**
     * @notice INTERNAL function to handle data record keys with overrides
     * @param _labelhash The labelhash to query
     * @param _key The data record key
     * @return The data record value (with override for chain-id)
     */
    function _getData(
        bytes32 _labelhash,
        string memory _key
    ) internal view returns (bytes memory) {
        return dataRecords[_resolveLabelhash(_labelhash)][_key];
    }

    //////
    /// HELPERS
    //////

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
        require(b.length == 20);
        assembly {
            a := div(mload(add(b, 32)), exp(256, 12))
        }
    }
}
