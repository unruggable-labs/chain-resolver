// SPDX-License-Identifier: MIT

// Tests for ERC-7828 reverse resolution
// The resolution of a chain label from an Interoperable Address.

pragma solidity ^0.8.25;

import "./ChainResolverTestBase.sol";
import {HexUtils} from "@ensdomains/ens-contracts/contracts/utils/HexUtils.sol";

contract ChainResolverENSReverseTest is ChainResolverTestBase {
    address public operator = address(0x4);

    // Precomputed DNS-encoded names for PARENT_DOMAIN
    bytes internal DNS_REVERSE_PARENT_DOMAIN;

    // Encoded key for reverse text query: "chain-label:" + <7930 hex (no 0x prefix)>
    string internal constant KEY_CHAIN_LABEL = "chain-label:00010001010a00";

    function setUp() public {
        vm.startPrank(admin);
        resolver = deployResolver(admin);
        vm.stopPrank();

        // Compute DNS-encoded reverse name
        DNS_REVERSE_PARENT_DOMAIN = NameCoder.encode(
            string(abi.encodePacked("reverse.", PARENT_DOMAIN))
        );
    }

    function test_001____resolve_____________________ReverseResolvesChainNameText()
        public
    {
        vm.startPrank(admin);
        registerTestChain();
        vm.stopPrank();

        // Test reverse resolution via resolve() per ENSIP-10 using full name
        // name = reverse.PARENT_DOMAIN; node = namehash(name)
        bytes memory name = DNS_REVERSE_PARENT_DOMAIN;
        bytes32 node = NameCoder.namehash(name, 0);

        bytes4 textSelector = bytes4(keccak256("text(bytes32,string)"));
        bytes memory textData = abi.encodeWithSelector(
            textSelector,
            node,
            KEY_CHAIN_LABEL
        );
        bytes memory result = resolver.resolve(name, textData);
        string memory resolvedChainName = abi.decode(result, (string));

        // Reverse should return the label for the given 7930 ID
        assertEq(
            resolvedChainName,
            TEST_LABEL,
            "Reverse should return label, not name"
        );

        console.log(
            "Successfully resolved reverse chain name via resolve function"
        );
        console.log("Interoperable Address -> Label:", resolvedChainName);
    }

    function test_002____chainName_______________ReverseResolvesChainNameFromInteroperableAddress()
        public
    {
        vm.startPrank(admin);
        registerTestChain();
        vm.stopPrank();

        // Test reverse resolution using chainLabel + chainName
        string memory resolvedLabel = resolver.chainLabel(TEST_INTEROPERABLE_ADDRESS);
        string memory resolvedChainName = resolver.chainName(resolvedLabel);
        assertEq(
            resolvedChainName,
            TEST_CHAIN_NAME,
            "Should resolve chain name via chainLabel + chainName"
        );

        console.log(
            "Successfully resolved reverse chain name via chainLabel + chainName"
        );
        console.log("Interoperable Address -> Label -> Name:", resolvedChainName);
    }

    function test_003____chainName___________________ReturnsEmptyForUnknownInteroperableAddress()
        public
    {
        vm.startPrank(admin);
        registerTestChain();
        vm.stopPrank();

        // Test reverse resolution for unknown Interoperable Address
        bytes memory unknownInteroperableAddress = hex"00010001019900";
        string memory resolvedLabel = resolver.chainLabel(unknownInteroperableAddress);
        string memory resolvedName = bytes(resolvedLabel).length > 0 ? resolver.chainName(resolvedLabel) : "";

        assertEq(
            resolvedName,
            "",
            "Should return empty string for unknown Interoperable Address"
        );

        console.log("Successfully returned empty string for unknown Interoperable Address");
    }

    function test_004____resolve_____________________ReverseCidEthReturnsRegisteredChainName()
        public
    {
        vm.startPrank(admin);
        registerTestChain();
        vm.stopPrank();

        // Build calldata for text(bytes32,string) using node-bound reverse context
        bytes4 textSelector = bytes4(keccak256("text(bytes32,string)"));
        bytes memory name = DNS_REVERSE_PARENT_DOMAIN;
        bytes memory data = abi.encodeWithSelector(
            textSelector,
            NameCoder.namehash(name, 0),
            KEY_CHAIN_LABEL
        );

        // Query under reverse.PARENT_DOMAIN with node-bound reverse
        bytes memory out = resolver.resolve(name, data);
        string memory result = abi.decode(out, (string));

        // Reverse should return the label for the chain ID
        assertEq(
            result,
            TEST_LABEL,
            "reverse.PARENT_DOMAIN should return label"
        );
    }

    function test_005____resolve_____________________NonReverseContextReturnsStoredTextRecord()
        public
    {
        vm.startPrank(admin);
        registerTestChain();
        vm.stopPrank();

        // Store a text record for this label and the reverse key
        string memory fallbackVal = "fallback-value";
        vm.startPrank(user1);
        resolver.setText(TEST_LABELHASH, KEY_CHAIN_LABEL, fallbackVal);
        vm.stopPrank();

        // Build calldata for text(bytes32,string)
        bytes4 TEXT_SELECTOR = bytes4(keccak256("text(bytes32,string)"));
        bytes memory data = abi.encodeWithSelector(
            TEXT_SELECTOR,
            bytes32(0),
            KEY_CHAIN_LABEL
        );

        // Query under optimism.PARENT_DOMAIN (not reverse.PARENT_DOMAIN) - still non-reverse context
        bytes memory dnsName = dnsEncodeLabel(TEST_LABEL);
        bytes memory out = resolver.resolve(dnsName, data);
        string memory result = abi.decode(out, (string));

        assertEq(
            result,
            fallbackVal,
            "non-reverse context should return stored text record value"
        );
    }
}
