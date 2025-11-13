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
     * @notice Modifier to ensure only the chain owner can call the function
     * @param _labelhash The labelhash to check authorization for
     */
    modifier onlyChainOwner(bytes32 _labelhash) {
        address _owner = chainData[_labelhash].owner;
        if (_owner != _msgSender()) {
            revert NotChainOwner(_msgSender(), _labelhash);
        }
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
    string public constant INTEROPERABLE_ADDRESS_KEY = "interoperable-address";
    string public constant CHAIN_NAME_PREFIX = "chain-name:";
    bytes32 public constant REVERSE_LABELHASH = keccak256("reverse");

    // Chain data storage
    mapping(bytes32 labelhash => ChainData data) internal chainData;
    mapping(bytes interoperableAddress => string label) internal labelByInteroperableAddress;

    // Discoverability
    // Total number of registered chains
    uint256 public chainCount;
    // Known labelhashes
    bytes32[] private labelhashList;

    // ENS record storage
    mapping(bytes32 labelhash => mapping(uint256 coinType => bytes value)) private addressRecords;
    mapping(bytes32 labelhash => bytes contenthash) private contenthashRecords;
    mapping(bytes32 labelhash => mapping(string key => string value)) private textRecords;
    mapping(bytes32 labelhash => mapping(string key => bytes data)) private dataRecords;

    /**
     * @notice Constructor
     * @param _owner The address to set as the owner
     */
    constructor(address _owner) Ownable(_owner) {}

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IExtendedResolver).interfaceId
            || interfaceId == type(IChainResolver).interfaceId;
    }

    //////
    /// RESOLUTION
    //////

    /**
     * @notice Resolve data for a DNS-encoded name using ENSIP-10 interface.
     * @param name The DNS-encoded name.
     * @param data The ABI-encoded ENS method calldata.
     * @return The resolved data based on the method selector.
     */
    function resolve(bytes calldata name, bytes calldata data) external view override returns (bytes memory) {
        
        // Extract the first labelhash from the DNS-encoded name
        (bytes32 labelhash,,,) = NameCoder.readLabel(name, 0, true);

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

    function setChainAdmin(bytes32 _labelhash, address _owner) external onlyChainOwner(_labelhash) {

        if (_labelhash == REVERSE_LABELHASH) {
            revert ReverseNodeOwnershipBlock();
        }

        chainData[_labelhash].owner = _owner;
        emit ChainAdminSet(_labelhash, _owner);
    }

    /**
     * @notice EXTERNAL Set the address for a given coinType.
     * @param _labelhash The labelhash to update.
     * @param _coinType The coin type (per ENSIP-11).
     * @param _value The raw address bytes encoded for that coin type.
     */
    function setAddr(bytes32 _labelhash, uint256 _coinType, bytes calldata _value)
        external
        onlyChainOwner(_labelhash)
    {
        addressRecords[_labelhash][_coinType] = _value;
        emit AddressChanged(_labelhash, _coinType, _value);
        if (_coinType == ETHEREUM_COIN_TYPE) {
            emit AddrChanged(_labelhash, bytesToAddress(_value));
        }    }

    /**
     * @notice Set a text record for a labelhash.
     * @dev EXTERNAL - blocks immutable keys
     * @param _labelhash The labelhash to update.
     * @param _key The text record key.
     * @param _value The text record value.
     * @dev Note: "chain-id" text record will be stored but not used - resolve() overrides it with internal registry value.
     */
    function setText(bytes32 _labelhash, string calldata _key, string calldata _value)
        external
        onlyChainOwner(_labelhash)
    {

        if (keccak256(bytes(_key)) == keccak256(bytes(INTEROPERABLE_ADDRESS_KEY))) {
            revert ImmutableTextKey(_labelhash, _key);
        }

        _setText(_labelhash, _key, _value);
    }

    /**
     * @notice INTERNAL Set a text record for a labelhash.
     * @param _labelhash The labelhash to update.
     * @param _key The text record key.
     * @param _value The text record value.
     * @dev Note: "chain-id" text record will be stored but not used - resolve() overrides it with internal registry value.
     */
    function _setText(bytes32 _labelhash, string memory _key, string memory _value)
        internal
    {
        textRecords[_labelhash][_key] = _value;
        //emit TextChanged(_labelhash, _key, keccak256(_key), keccak256(_value));
    }

    /**
     * @notice Set the contenthash for a labelhash.
     * @param _labelhash The labelhash to update.
     * @param _contenthash The contenthash to set.
     */
    function setContenthash(bytes32 _labelhash, bytes calldata _contenthash) 
        external 
        onlyChainOwner(_labelhash) 
    {
        contenthashRecords[_labelhash] = _contenthash;
    }

    /**
     * @notice Set a data record for a labelhash.
     * @dev EXTERNAL - blocks immutable keys
     * @param _labelhash The labelhash to update.
     * @param _key The data record key.
     * @param _data The data record value.
     */
    function setData(bytes32 _labelhash, string calldata _key, bytes calldata _data)
        external
        onlyChainOwner(_labelhash)
    {
        if (keccak256(bytes(_key)) == keccak256(bytes(INTEROPERABLE_ADDRESS_KEY))) {
            revert ImmutableDataKey(_labelhash, _key);
        }

        _setData(_labelhash, _key, _data);
    }

    /**
     * @notice INTERNAL Set a data record for a labelhash.
     * @param _labelhash The labelhash to update.
     * @param _key The data record key.
     * @param _data The data record value.
     */
    function _setData(bytes32 _labelhash, string memory _key, bytes memory _data)
        internal
    {
        dataRecords[_labelhash][_key] = _data;
        emit DataChanged(_labelhash, _key, keccak256(bytes(_key)), keccak256(_data));
    }

    //////
    /// GETTERS
    //////

    function chainLabel(bytes calldata _interoperableAddress) external view returns (string memory) {
        return _getText(REVERSE_LABELHASH, concat(CHAIN_NAME_PREFIX, _interoperableAddress));
    }

    function chainName(bytes calldata _interoperableAddress) external view returns (string memory) {
        return chainData[keccak256(bytes(labelByInteroperableAddress[_interoperableAddress]))].chainName;
    }

    function interoperableAddress(bytes32 _labelhash) external view returns (bytes memory) {
        return _getData(_labelhash, INTEROPERABLE_ADDRESS_KEY);
    }

    /**
     * @notice Get the address for a labelhash with a specific coin type.
     * @param _labelhash The labelhash to query.
     * @param _coinType The coin type (default: 60 for Ethereum).
     * @return The address for this label and coin type.
     */
    function getAddr(bytes32 _labelhash, uint256 _coinType) external view returns (bytes memory) {
        return _getAddr(_labelhash, _coinType);
    }

    /**
     * @notice Get a text record for a labelhash.
     * @param _labelhash The labelhash to query.
     * @param _key The text record key.
     * @return The text record value (with special handling for chain-id and chain-name:).
     */
    function getText(bytes32 _labelhash, string calldata _key) external view returns (string memory) {
        return _getText(_labelhash, _key);
    }

    /**
     * @notice Get the content hash for a labelhash.
     * @param _labelhash The labelhash to query.
     * @return The content hash for this label.
     */
    function getContenthash(bytes32 _labelhash) external view returns (bytes memory) {
        return _getContenthash(_labelhash);
    }

    /**
     * @notice Get a data record for a labelhash.
     * @param _labelhash The labelhash to query.
     * @param _key The data record key.
     * @return The data record value (with special handling for chain-id).
     */
    function getData(bytes32 _labelhash, string calldata _key) external view returns (bytes memory) {
        return _getData(_labelhash, _key);
    }

    /**
     * @notice Get the admin for a chain
     * @param _labelhash The labelhash to query.
     * @return The owner address.
     */
    function getChainAdmin(bytes32 _labelhash) external view returns (address) {
        return chainData[_labelhash].owner;
    }

    //////
    /// REGISTRATION
    //////

    function register(ChainData calldata data) external onlyOwner {
        _register(data.label, data.chainName, data.owner, data.interoperableAddress);
    }

    function batchRegister(ChainData[] calldata items) external onlyOwner {
        uint256 _length = items.length;
        for (uint256 i = 0; i < _length; i++) {
            _register(items[i].label, items[i].chainName, items[i].owner, items[i].interoperableAddress);
        }
    }

    /**
     * @notice Internal helper function to register an individual chain
     * @param _label The short chain label (e.g., "optimism")
     * @param _chainName The chain name (e.g., "Optimism")
     * @param _owner The owner address
     * @param _interoperableAddress The Interoperable Address (ERC-7930)
     */
    function _register(string calldata _label, string calldata _chainName, address _owner, bytes calldata _interoperableAddress)
        internal
    {
        bytes32 _labelhash = keccak256(bytes(_label));

        bool isUpdate = chainData[_labelhash].owner != address(0);

        chainData[_labelhash].chainName = _chainName;
        chainData[_labelhash].owner = _owner;

        _setData(_labelhash, INTEROPERABLE_ADDRESS_KEY, _interoperableAddress);
        _setText(REVERSE_LABELHASH, concat(CHAIN_NAME_PREFIX, _interoperableAddress), _label);

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
    function getChainAtIndex(uint256 _index)
        external
        view
        returns (string memory _label, string memory _chainName, bytes memory _interoperableAddress)
    {
        if (_index >= labelhashList.length) revert IndexOutOfRange();
        bytes32 labelhash = labelhashList[_index];
        _chainName = chainData[labelhash].chainName;
        _interoperableAddress = _getData(labelhash, INTEROPERABLE_ADDRESS_KEY);
        _label = _getText(REVERSE_LABELHASH, concat(CHAIN_NAME_PREFIX, _interoperableAddress));
    }

    //////
    /// INTERNAL Getters
    //////

    /**
     * @notice INTERNAL function for getting address records for a specific coin type.
     * @param _labelhash The labelhash to query.
     * @param _coinType The coin type (default: 60 for Ethereum).
     * @return The address for this label and coin type.
     */
    function _getAddr(bytes32 _labelhash, uint256 _coinType) internal view returns (bytes memory) {
        return addressRecords[_labelhash][_coinType];
    }

    /**
     * @notice INTERNAL function for getting text records
     * @param _labelhash The labelhash to query
     * @param _key The text record key
     * @return The text record value
     */
    function _getText(bytes32 _labelhash, string memory _key)
        internal
        view
        returns (string memory)
    {
        return textRecords[_labelhash][_key];
    }

    /**
     * @notice INTERNAL function for getting a contenthash
     * @param _labelhash The labelhash to query
     * @return The contenthash value
     */
    function _getContenthash(bytes32 _labelhash)
        internal
        view
        returns (bytes memory)
    {
        return contenthashRecords[_labelhash];
    }

    /**
     * @notice INTERNAL function to handle data record keys with overrides
     * @param _labelhash The labelhash to query
     * @param _key The data record key
     * @return The data record value (with override for chain-id)
     */
    function _getData(bytes32 _labelhash, string memory _key) internal view returns (bytes memory) {
        return dataRecords[_labelhash][_key];
    }

    //////
    /// HELPERS
    //////

    /**
     * @notice Concatenates a string with bytes into a single string.
     * @param _str The string prefix.
     * @param _data The bytes to append.
     * @return The concatenated string.
     */
    function concat(string memory _str, bytes memory _data) internal pure returns (string memory) {
        return string(abi.encodePacked(_str, _data));
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
}
