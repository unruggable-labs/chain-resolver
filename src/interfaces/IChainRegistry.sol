// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

/**
 * @title IChainRegistry
 * @author Unruggable
 * @notice Interface for Chain Registry using ERC-8048 onchain metadata
 */
interface IChainRegistry {
    
    /**
     * @notice Chain record structure
     * @param key The record key
     * @param value The record value as bytes
     */
    struct ChainRecord {
        string key;
        bytes value;
    }

    /**
     * @notice Chain registration structure
     * @param chainName The chain name
     * @param owner The owner address
     * @param chainId The ERC-7930 chain ID
     * @param chainName The human-readable chain name
     * @param records Array of records to store
     */
    struct ChainRegistration {
        string chainName;
        address owner;
        bytes chainId;
        string chainDisplayName;
        ChainRecord[] records;
    }

    /**
     * @notice Emitted when a chain is registered
     * @param labelhash The chain labelhash
     * @param owner The chain owner
     * @param chainId The ERC-7930 chain ID
     * @param chainName The chain name
     */
    event ChainRegistered(
        bytes32 indexed labelhash,
        address indexed owner,
        bytes chainId,
        string chainName
    );

    /**
     * @notice Emitted when a chain record is set
     * @param labelhash The chain labelhash
     * @param key The record key
     * @param value The record value
     */
    event ChainRecordSet(
        bytes32 indexed labelhash,
        string key,
        bytes value
    );

    /**
     * @notice Emitted when multiple chain records are set
     * @param labelhash The chain labelhash
     * @param recordCount The number of records set
     */
    event ChainRecordsSet(
        bytes32 indexed labelhash,
        uint256 recordCount
    );

    /**
     * @notice Emitted when an operator is set
     * @param owner The owner address
     * @param operator The operator address
     * @param isOperator Whether the address is an operator
     */
    event OperatorSet(
        address indexed owner,
        address indexed operator,
        bool isOperator
    );

    /**
     * @notice Register a new chain with all its records
     * @param _chainName The chain name
     * @param _owner The owner address
     * @param _chainId The ERC-7930 chain ID
     * @param _chainDisplayName The human-readable chain name
     * @param _records Array of record data to store
     */
    function registerChain(
        string memory _chainName,
        address _owner,
        bytes memory _chainId,
        string memory _chainDisplayName,
        ChainRecord[] memory _records
    ) external;

    /**
     * @notice Batch register multiple chains
     * @param _chains Array of chain registration data
     */
    function batchRegisterChains(ChainRegistration[] calldata _chains) external;

    /**
     * @notice Set a record for a chain
     * @param _labelhash The chain labelhash
     * @param _key The record key
     * @param _value The record value
     */
    function setChainRecord(bytes32 _labelhash, string calldata _key, bytes calldata _value) external;

    /**
     * @notice Set a record for a chain (called by resolver)
     * @param _labelhash The chain labelhash
     * @param _key The record key
     * @param _value The record value
     * @param _caller The original caller (for authorization)
     */
    function setChainRecord(bytes32 _labelhash, string calldata _key, bytes calldata _value, address _caller) external;

    /**
     * @notice Set multiple records for a chain
     * @param _labelhash The chain labelhash
     * @param _records Array of records to set
     */
    function setChainRecords(bytes32 _labelhash, ChainRecord[] calldata _records) external;

    /**
     * @notice Get a record for a chain
     * @param _labelhash The chain labelhash
     * @param _key The record key
     * @return The record value
     */
    function getChainRecord(bytes32 _labelhash, string calldata _key) external view returns (bytes memory);

    /**
     * @notice Get the ERC-7930 chain ID for a chain
     * @param _labelhash The chain labelhash
     * @return The ERC-7930 chain ID bytes
     */
    function getChainId(bytes32 _labelhash) external view returns (bytes memory);

    /**
     * @notice Get the chain name for a chain
     * @param _labelhash The chain labelhash
     * @return The chain name
     */
    function getChainName(bytes32 _labelhash) external view returns (string memory);

    /**
     * @notice Get the owner of a chain
     * @param _labelhash The chain labelhash
     * @return The owner address
     */
    function getChainOwner(bytes32 _labelhash) external view returns (address);

    /**
     * @notice Get the chain name for a chain ID
     * @param _chainId The chain ID
     * @return The chain name
     */
    function getChainNameByChainId(bytes calldata _chainId) external view returns (string memory);

    /**
     * @notice Set operator for chain management
     * @param _operator The operator address
     * @param _isOperator Whether the address is an operator
     */
    function setOperator(address _operator, bool _isOperator) external;

    /**
     * @notice Set operator for a specific caller (called by resolver)
     * @param _operator The operator address
     * @param _isOperator Whether the address is an operator
     * @param _caller The original caller
     */
    function setOperatorForCaller(address _operator, bool _isOperator, address _caller) external;

    /**
     * @notice Check if an address is authorized for a chain
     * @param _labelhash The chain labelhash
     * @param _address The address to check
     * @return True if authorized
     */
    function isAuthorized(bytes32 _labelhash, address _address) external view returns (bool);
}
