// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/ChainResolver.sol";
import "../src/interfaces/IChainResolver.sol";
import {NameCoder} from "@ensdomains/ens-contracts/contracts/utils/NameCoder.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

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

    /**
     * @notice Deploy ChainResolver behind an ERC1967 proxy
     * @param _owner The owner address
     * @return The ChainResolver instance (pointing to proxy)
     */
    function deployResolver(address _owner) internal returns (ChainResolver) {
        bytes32 parentNamehash = NameCoder.namehash(NameCoder.encode("cid.eth"), 0);
        return deployResolverWithNamehash(_owner, parentNamehash);
    }

    /**
     * @notice Deploy ChainResolver behind an ERC1967 proxy with custom parent namehash
     * @param _owner The owner address
     * @param _parentNamehash The parent namespace namehash
     * @return The ChainResolver instance (pointing to proxy)
     */
    function deployResolverWithNamehash(address _owner, bytes32 _parentNamehash) internal returns (ChainResolver) {
        // Deploy implementation
        implementation = new ChainResolver();
        
        // Encode initialization call
        bytes memory initData = abi.encodeWithSelector(
            ChainResolver.initialize.selector,
            _owner,
            _parentNamehash
        );
        
        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        
        // Return proxy cast as ChainResolver
        return ChainResolver(address(proxy));
    }
}

