// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "../src/ChainResolver.sol";

contract ChainResolverENSReverseTest is Test {
    ChainResolver public resolver;

    address public admin = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    address public operator = address(0x4);

    // Test data - using 7930 chain ID format
    string public constant CHAIN_NAME = "optimism";
    // 7930 format: Version(4) + ChainType(2) + ChainRefLen(1) + ChainRef(1) + AddrLen(1) + Addr(0)
    // Version: 0x00000001, ChainType: 0x0001 (Ethereum), ChainRefLen: 0x01, ChainRef: 0x0a (10), AddrLen: 0x00, Addr: (empty)
    bytes public constant CHAIN_ID = hex"000000010001010a00";
    bytes32 public constant LABEL_HASH = keccak256(bytes(CHAIN_NAME));

    function setUp() public {
        vm.startPrank(admin);
        resolver = new ChainResolver(admin);
        vm.stopPrank();
    }

    // Identify the file being tested
    function test1000________________________________________________________________________________() public {}
    function test1100_____________________________ENS_REVERSE____________________________________() public {}
    function test1200________________________________________________________________________________() public {}

    function test_001____resolve_____________________ResolvesReverseChainName() public {
        vm.startPrank(admin);

        // Register a chain
        resolver.register(CHAIN_NAME, user1, CHAIN_ID);

        vm.stopPrank();

        // Test reverse resolution via resolve function with proper DNS encoding
        bytes memory name = abi.encodePacked(bytes1(uint8(bytes(CHAIN_NAME).length)), bytes(CHAIN_NAME), bytes1(0x00));

        // Test text record with chain-name: prefix (set it manually first)
        vm.startPrank(user1);
        string memory chainNameKey = string(abi.encodePacked("chain-name:", CHAIN_ID));
        resolver.setText(LABEL_HASH, chainNameKey, CHAIN_NAME);
        vm.stopPrank();

        bytes memory textData = abi.encodeWithSelector(resolver.TEXT_SELECTOR(), LABEL_HASH, chainNameKey);
        bytes memory result = resolver.resolve(name, textData);
        string memory resolvedChainName = abi.decode(result, (string));

        assertEq(resolvedChainName, CHAIN_NAME, "Should resolve chain name from chain ID via resolve function");

        console.log("Successfully resolved reverse chain name via resolve function");
        console.log("Chain ID -> Chain Name:", resolvedChainName);
    }

    function test_002____resolve_____________________ResolvesReverseChainNameData() public {
        vm.startPrank(admin);

        // Register a chain
        resolver.register(CHAIN_NAME, user1, CHAIN_ID);

        vm.stopPrank();

        // Test reverse resolution via data record with proper DNS encoding
        bytes memory name = abi.encodePacked(bytes1(uint8(bytes(CHAIN_NAME).length)), bytes(CHAIN_NAME), bytes1(0x00));

        // Test data record with chain-name: prefix (this should use the special handling in resolve function)
        bytes memory chainNameKey = abi.encodePacked("chain-name:", CHAIN_ID);
        bytes memory dataData = abi.encodeWithSelector(resolver.DATA_SELECTOR(), LABEL_HASH, chainNameKey);
        bytes memory result = resolver.resolve(name, dataData);
        string memory resolvedChainName = abi.decode(result, (string));

        assertEq(
            resolvedChainName, CHAIN_NAME, "Should resolve chain name from chain ID via data record resolve function"
        );

        console.log("Successfully resolved reverse chain name via data record resolve function");
    }

    function test_003____chainName___________________ResolvesChainNameFromChainId() public {
        vm.startPrank(admin);

        // Register a chain
        resolver.register(CHAIN_NAME, user1, CHAIN_ID);

        vm.stopPrank();

        // Test direct reverse resolution - chain ID to chain name
        string memory resolvedChainName = resolver.chainName(CHAIN_ID);

        assertEq(resolvedChainName, CHAIN_NAME, "Should resolve chain name from chain ID");

        console.log("Successfully resolved reverse chain name via direct function");
        console.log("Chain ID -> Chain Name:", resolvedChainName);
    }

    function test_004____reverseLookup_______________MultipleChainsReverseResolution() public {
        vm.startPrank(admin);

        // Register multiple chains
        string memory chainName2 = "arbitrum";
        bytes memory chainId2 = hex"000000010001016600"; // 7930 format for chain 102

        resolver.register(CHAIN_NAME, user1, CHAIN_ID);
        resolver.register(chainName2, user2, chainId2);

        vm.stopPrank();

        // Test reverse resolution for both chains
        string memory resolvedName1 = resolver.chainName(CHAIN_ID);
        string memory resolvedName2 = resolver.chainName(chainId2);

        assertEq(resolvedName1, CHAIN_NAME, "Should resolve first chain name");
        assertEq(resolvedName2, chainName2, "Should resolve second chain name");

        console.log("Successfully resolved multiple chains via reverse lookup");
        console.log("Chain 1:", resolvedName1);
        console.log("Chain 2:", resolvedName2);
    }

    function test_005____chainName___________________ReturnsEmptyForUnknownChainId() public {
        vm.startPrank(admin);

        // Register a chain
        resolver.register(CHAIN_NAME, user1, CHAIN_ID);

        vm.stopPrank();

        // Test reverse resolution for unknown chain ID
        bytes memory unknownChainId = hex"000000010001019900"; // 7930 format for chain 153 (unknown)
        string memory resolvedName = resolver.chainName(unknownChainId);

        assertEq(resolvedName, "", "Should return empty string for unknown chain ID");

        console.log("Successfully returned empty string for unknown chain ID");
    }
}
