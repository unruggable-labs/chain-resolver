// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "../src/ChainResolver.sol";
import {NameCoder} from "@ensdomains/ens-contracts/contracts/utils/NameCoder.sol";
import {HexUtils} from "@ensdomains/ens-contracts/contracts/utils/HexUtils.sol";

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

    // Precomputed DNS-encoded names
    // cid.eth => 0x03 'cid' 0x03 'eth' 0x00
    bytes internal constant DNS_CID_ETH = hex"036369640365746800";

    // Encoded key for reverse text query: "chain-name:" + <7930 hex w/out 0x>
    string internal constant KEY_CHAIN_NAME = "chain-name:000000010001010a00";

    function setUp() public {
        vm.startPrank(admin);
        resolver = new ChainResolver(admin);
        vm.stopPrank();
    }

    // Identify the file being tested
    function test1000________________________________________________________________________________() public {}
    function test1100_____________________________ENS_REVERSE____________________________________() public {}
    function test1200________________________________________________________________________________() public {}

    function test_001____resolve_____________________ReverseResolvesChainNameText() public {
        vm.startPrank(admin);

        // Register a chain
        resolver.register(CHAIN_NAME, user1, CHAIN_ID);

        vm.stopPrank();

        // Test reverse resolution via resolve() under namespace root with node-bound reverse context
        // name = cid.eth; node = namehash("reverse.cid.eth")
        bytes memory name = DNS_CID_ETH;
        bytes32 node = NameCoder.namehash(NameCoder.encode("reverse.cid.eth"), 0);

        // Manually set a conflicting value for the special key to prove overrides apply
        // Even if a user sets textRecords["chain-name:<hex>"] = "hacked",
        // _getTextWithOverrides ignores it and returns from internal mapping.
        vm.startPrank(user1);
        string memory chainIdHex = HexUtils.bytesToHex(CHAIN_ID);
        string memory chainNameKey = string(abi.encodePacked("chain-name:", chainIdHex));
        resolver.setText(LABEL_HASH, chainNameKey, "hacked");
        vm.stopPrank();

        bytes memory textData = abi.encodeWithSelector(resolver.TEXT_SELECTOR(), node, chainNameKey);
        bytes memory result = resolver.resolve(name, textData);
        string memory resolvedChainName = abi.decode(result, (string));

        assertEq(resolvedChainName, CHAIN_NAME, "Override should return canonical chain name, ignoring stored text");

        console.log("Successfully resolved reverse chain name via resolve function");
        console.log("Chain ID -> Chain Name:", resolvedChainName);
    }

    function test_002____chainName___________________ReverseResolvesChainNameFromChainId() public {
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

    function test_003____chainName___________________ReturnsEmptyForUnknownChainId() public {
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

    function test_004____resolve_____________________ReverseCidEthReturnsRegisteredChainName() public {
        vm.startPrank(admin);
        resolver.register(CHAIN_NAME, user1, CHAIN_ID);
        vm.stopPrank();

        // Build calldata for text(bytes32,string) using node-bound reverse context
        bytes4 TEXT_SELECTOR = bytes4(keccak256("text(bytes32,string)"));
        bytes memory data = abi.encodeWithSelector(
            TEXT_SELECTOR, NameCoder.namehash(NameCoder.encode("reverse.cid.eth"), 0), KEY_CHAIN_NAME
        );

        // Query under cid.eth with node-bound reverse
        bytes memory out = resolver.resolve(DNS_CID_ETH, data);
        string memory result = abi.decode(out, (string));

        assertEq(result, CHAIN_NAME, "reverse.cid.eth should return chain name");
    }

    function test_005____resolve_____________________NonReverseContextReturnsStoredTextRecord() public {
        vm.startPrank(admin);
        resolver.register(CHAIN_NAME, user1, CHAIN_ID);
        vm.stopPrank();

        // Store a text record for this label and the reverse key
        string memory fallbackVal = "fallback-value";
        vm.startPrank(user1);
        resolver.setText(LABEL_HASH, KEY_CHAIN_NAME, fallbackVal);
        vm.stopPrank();

        // Build calldata for text(bytes32,string)
        bytes4 TEXT_SELECTOR = bytes4(keccak256("text(bytes32,string)"));
        bytes memory data = abi.encodeWithSelector(TEXT_SELECTOR, bytes32(0), KEY_CHAIN_NAME);

        // Query under optimism.cid.eth (not reverse.cid.eth) - still non-reverse context
        bytes memory dnsOptimismCidEth = hex"086f7074696d69736d036369640365746800";
        bytes memory out = resolver.resolve(dnsOptimismCidEth, data);
        string memory result = abi.decode(out, (string));

        assertEq(result, fallbackVal, "non-reverse context should return stored text record value");
    }
}
