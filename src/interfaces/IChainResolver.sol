// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title IChainResolver
 * @author @unruggable-labs, @defi-wonderland
 * @notice Interface for the ChainResolver that manages chain data using labelhashes
 * @dev Source: https://github.com/unruggable-labs/chain-resolver/tree/main/src/interfaces/IChainResolver.sol
 */
interface IChainResolver {
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
    function chainName(bytes calldata _chainIdBytes) external view returns (string memory _chainName);
    function chainId(bytes32 _labelhash) external view returns (bytes memory _chainId);
    function register(string calldata _chainName, address _owner, bytes calldata _chainId) external;
    function batchRegister(string[] calldata _chainNames, address[] calldata _owners, bytes[] calldata _chainIds)
        external;
    function setLabelOwner(bytes32 _labelhash, address _owner) external;
    function setOperator(address _operator, bool _isOperator) external;
    function isAuthorized(bytes32 _labelhash, address _address) external view returns (bool _authorized);
}
