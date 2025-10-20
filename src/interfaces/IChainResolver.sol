// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title IChainResolver
 * @author @unruggable-labs, @defi-wonderland
 * @notice Interface for the ChainResolver that manages chain data using labelhashes
 * @dev Source: https://github.com/unruggable-labs/chain-resolver/tree/main/src/interfaces/IChainResolver.sol
 */
interface IChainResolver {
    /// @notice Per-labelhash chain data
    struct ChainData {
        bytes chainId; // ERC-7930 identifier bytes
        string label; // canonical lowercase label
        string name; // human-readable chain name
        address owner; // label owner
    }
    /// @notice Events
    event RecordSet(bytes32 indexed _labelhash, bytes _chainId, string _chainName);
    event LabelOwnerSet(bytes32 indexed _labelhash, address _owner);
    event OperatorSet(address indexed _owner, address indexed _operator, bool _isOperator);
    event AddrChanged(bytes32 indexed _labelhash, address _owner);
    event AddressChanged(bytes32 indexed node, uint256 coinType, bytes newAddress);
    event DataChanged(bytes32 node, string indexed indexedKey, string key, bytes data);

    /// @notice Errors
    error InvalidDataLength();
    error NotAuthorized(address _caller, bytes32 _labelhash);

    /// @notice Functions
    /**
     * @notice Return the canonical chain label for a given ERC-7930 chain identifier.
     * @dev Maps `chainIdBytes (ERC-7930)` → `label` set at registration.
     * @param _chainIdBytes The ERC-7930 chain identifier bytes.
     * @return _chainName The chain label (e.g., "optimism").
     */
    function chainName(bytes calldata _chainIdBytes) external view returns (string memory _chainName);

    /**
     * @notice Return the ERC-7930 chain identifier bytes for a given labelhash.
     * @param _labelhash The ENS labelhash `keccak256(bytes(label))`.
     * @return _chainId The ERC-7930 chain identifier bytes.
     */
    function chainId(bytes32 _labelhash) external view returns (bytes memory _chainId);

    /**
     * @notice Register or update a chain entry with explicit label and chain name (owner-only).
     * @dev
     * - Emits `LabelOwnerSet` and `RecordSet` on insert/update.
     * - Re-registering an existing label updates owner, chainId, and chainName.
     * - Enumeration: `chainCount` increments only on first insert.
     * @param _label The short chain label (e.g., "optimism").
     * @param _chainName The chain name (e.g., "Optimism").
     * @param _owner The label owner address.
     * @param _chainId The ERC-7930 chain identifier bytes.
     */
    function register(string calldata _label, string calldata _chainName, address _owner, bytes calldata _chainId)
        external;

    /**
     * @notice Batch register or update multiple chains (owner-only).
     * @dev Reverts `InvalidDataLength` if array lengths are not equal. See `register(...)` for semantics.
     * @param _labels Array of short chain labels.
     * @param _chainNames Array of chain names.
     * @param _owners Array of owners for each label.
     * @param _chainIds Array of ERC-7930 chain identifiers.
     */
    function batchRegister(
        string[] calldata _labels,
        string[] calldata _chainNames,
        address[] calldata _owners,
        bytes[] calldata _chainIds
    ) external;

    /**
     * @notice Set or transfer the owner of a label. Callable by current owner or an approved operator.
     * @param _labelhash The ENS labelhash to update.
     * @param _owner The new owner address.
     */
    function setLabelOwner(bytes32 _labelhash, address _owner) external;

    /**
     * @notice Grant or revoke operator approval scoped to `msg.sender`.
     * @param _operator The operator address.
     * @param _isOperator True to grant approval; false to revoke.
     */
    function setOperator(address _operator, bool _isOperator) external;

    /**
     * @notice Check whether an address is authorized to manage a label.
     * @param _labelhash The labelhash to check.
     * @param _address The address to test.
     * @return _authorized True if `_address` is the owner or an approved operator for the owner.
     */
    function isAuthorized(bytes32 _labelhash, address _address) external view returns (bool _authorized);
}
