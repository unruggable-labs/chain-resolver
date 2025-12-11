// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title IChainResolver
 * @author @unruggable-labs, @defi-wonderland
 * @notice Interface for the ChainResolver contract specified in ERC-7828
 * @dev Source: https://github.com/unruggable-labs/chain-resolver/tree/main/src/interfaces/IChainResolver.sol
 */
interface IChainResolver {

    // Container for chain registration data
    struct ChainRegistrationData {
        string label; // short chain label (e.g., "optimism")
        string chainName; // human-readable formatted chain name
        address owner; // label owner
        bytes interoperableAddress; // ERC-7930 Interoperable Address
    }

    // Events
    event ChainRegistered(bytes32 indexed _labelhash, string _chainName, bytes _chainId);
    event ChainAdminSet(bytes32 indexed _labelhash, address _owner);
    event AliasRegistered(bytes32 indexed _aliasHash, bytes32 indexed _canonicalLabelhash, string _alias);
    event AliasRemoved(bytes32 indexed _aliasHash, bytes32 indexed _canonicalLabelhash, string _alias);
    event ParentNamehashChanged(bytes32 indexed _newParentNamehash);

    // ENSIP-1
    event AddrChanged(bytes32 indexed _labelhash, address _owner);
    // ENSIP-9
    event AddressChanged(bytes32 indexed node, uint256 coinType, bytes newAddress);
    // ENSIP-24
    event DataChanged(bytes32 indexed node, string indexed indexedKey, string key, bytes indexed indexedData);

    // Errors
    // There is no registered chain at that index
    error IndexOutOfRange();
    // Only the chain owner can edit associated records
    error NotChainOwner(address _caller, bytes32 _labelhash);
    // Some keys are immutable, e.g, the 'interoperable-address' data key, and the 
    error ImmutableDataKey(bytes32 _labelhash, string key);
    error ImmutableTextKey(bytes32 _labelhash, string key);

    // The `reverse.<namespace>.eth` node is special and can not be owned
    error ReverseNodeOwnershipBlock();
    // Cannot set chain admin to zero address
    error InvalidChainAdmin();
    // Registration validation errors
    error EmptyLabel();
    error EmptyChainName();
    error InvalidInteroperableAddress();

    /// @notice Functions

    /**
     * @notice Return the canonical chain label for a given ERC-7930 Interoperable Address.
     * @param _interoperableAddress The ERC-7930 Interoperable Address.
     * @return _chainLabel The chain label (e.g., "optimism").
     */
    function chainLabel(bytes calldata _interoperableAddress) external view returns (string memory _chainLabel);

    /**
     * @notice Return the human readable chain name for a given ERC-7930 Interoperable Address.
     * @param _interoperableAddress The ERC-7930 Interoperable Address.
     * @return _chainName The chain name (e.g., "Optimism").
     */
    function chainName(bytes calldata _interoperableAddress) external view returns (string memory _chainName);

    /**
     * @notice Return the ERC-7930 Interoperable Address bytes for a given labelhash.
     * @param _labelhash The ENS labelhash `keccak256(bytes(label))`.
     * @return _interoperableAddress The ERC-7930 Interoperable Address.
     */
    function interoperableAddress(bytes32 _labelhash) external view returns (bytes memory _interoperableAddress);

    /**
     * @notice Register or update a chain entry
     * @param _data The ChainRegistrationData struct
     */
    function register(ChainRegistrationData calldata _data) external;

    /**
     * @notice Batch register or update multiple chains.
     * @param _items Array of ChainRegistrationData structs.
     */
    function batchRegister(ChainRegistrationData[] calldata _items) external;

    /**
     * @notice Set or transfer the administrator of a label (chain).
     * @param _labelhash The ENS labelhash to update.
     * @param _owner The new owner address.
     */
    function setChainAdmin(bytes32 _labelhash, address _owner) external;

    /**
     * @notice Register an alias that points to a canonical labelhash.
     * @param _alias The alias string (e.g., "op").
     * @param _canonicalLabelhash The canonical labelhash to point to.
     */
    function registerAlias(string calldata _alias, bytes32 _canonicalLabelhash) external;

    /**
     * @notice Remove an alias.
     * @param _alias The alias string to remove.
     */
    function removeAlias(string calldata _alias) external;

    /**
     * @notice Get the canonical labelhash for an alias.
     * @param _labelhash The labelhash to check.
     * @return The canonical labelhash, or bytes32(0) if not an alias.
     */
    function getCanonicalLabelhash(bytes32 _labelhash) external view returns (bytes32);
}