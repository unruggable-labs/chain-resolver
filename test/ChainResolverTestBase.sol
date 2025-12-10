// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/ChainResolver.sol";
import "../src/interfaces/IChainResolver.sol";
import {
    NameCoder
} from "@ensdomains/ens-contracts/contracts/utils/NameCoder.sol";
import {
    ERC1967Proxy
} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title ChainResolverTestBase
 * @notice Base test contract that handles proxy deployment for ChainResolver tests
 */
abstract contract ChainResolverTestBase is Test {
    ChainResolver public resolver;
    ChainResolver public implementation;

    address public admin = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);

    // Parent domain constant
    string public constant PARENT_DOMAIN = "cid.eth";

    // Default test chain data
    string public constant TEST_LABEL = "optimism";
    string public constant TEST_CHAIN_NAME = "Optimism";
    bytes public constant TEST_INTEROPERABLE_ADDRESS = hex"00010001010a00";
    bytes32 public constant TEST_LABELHASH = keccak256(bytes(TEST_LABEL));

    /**
     * @notice Deploy ChainResolver behind an ERC1967 proxy
     * @param _owner The owner address
     * @return The ChainResolver instance (pointing to proxy)
     */
    function deployResolver(address _owner) internal returns (ChainResolver) {
        bytes32 parentNamehash = NameCoder.namehash(
            NameCoder.encode(PARENT_DOMAIN),
            0
        );
        return deployResolverWithNamehash(_owner, parentNamehash);
    }

    /**
     * @notice Deploy ChainResolver behind an ERC1967 proxy with custom parent namehash
     * @param _owner The owner address
     * @param _parentNamehash The parent namespace namehash
     * @return The ChainResolver instance (pointing to proxy)
     */
    function deployResolverWithNamehash(
        address _owner,
        bytes32 _parentNamehash
    ) internal returns (ChainResolver) {
        // Deploy implementation
        implementation = new ChainResolver();

        // Encode initialization call
        bytes memory initData = abi.encodeWithSelector(
            ChainResolver.initialize.selector,
            _owner,
            _parentNamehash
        );

        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            initData
        );

        // Return proxy cast as ChainResolver
        return ChainResolver(address(proxy));
    }

    /**
     * @notice DNS-encode a full ENS name (e.g., "optimism.cid.eth")
     * @param _name The dotted ENS name
     * @return The DNS-encoded bytes
     */
    function dnsEncode(
        string memory _name
    ) internal pure returns (bytes memory) {
        return NameCoder.encode(_name);
    }

    /**
     * @notice DNS-encode a label under the default parent domain
     * @param _label The label (e.g., "optimism")
     * @return The DNS-encoded bytes for label.PARENT_DOMAIN
     */
    function dnsEncodeLabel(
        string memory _label
    ) internal pure returns (bytes memory) {
        return
            NameCoder.encode(
                string(abi.encodePacked(_label, ".", PARENT_DOMAIN))
            );
    }

    /**
     * @notice Register the default test chain with user1 as owner
     */
    function registerTestChain() internal {
        registerChain(
            TEST_LABEL,
            TEST_CHAIN_NAME,
            user1,
            TEST_INTEROPERABLE_ADDRESS
        );
    }

    /**
     * @notice Register the default test chain with a custom owner
     * @param _owner The owner address for the chain
     */
    function registerTestChainWithOwner(address _owner) internal {
        registerChain(
            TEST_LABEL,
            TEST_CHAIN_NAME,
            _owner,
            TEST_INTEROPERABLE_ADDRESS
        );
    }

    /**
     * @notice Register a chain with custom parameters
     * @param _label The chain label
     * @param _chainName The chain name
     * @param _owner The owner address
     * @param _interoperableAddress The interoperable address bytes
     */
    function registerChain(
        string memory _label,
        string memory _chainName,
        address _owner,
        bytes memory _interoperableAddress
    ) internal {
        resolver.register(
            IChainResolver.ChainRegistrationData({
                label: _label,
                chainName: _chainName,
                owner: _owner,
                interoperableAddress: _interoperableAddress
            })
        );
    }
}
