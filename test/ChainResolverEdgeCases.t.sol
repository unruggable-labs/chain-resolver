// SPDX-License-Identifier: MIT

// Misc tests

pragma solidity ^0.8.25;

import "./ChainResolverTestBase.sol";

contract ChainResolverEdgeCasesTest is ChainResolverTestBase {
    address public operator = address(0x4);
    address public zeroAddress = address(0x0);

    function setUp() public {
        vm.startPrank(admin);
        resolver = deployResolver(admin);
        vm.stopPrank();
    }

    function test_001____register____________________EmptyChainName() public {
        vm.startPrank(admin);

        // Try to register with empty chain name
        string memory emptyName = "";
        bytes32 emptyLabelHash = keccak256(bytes(emptyName));

        // This should work - empty string is valid
        registerChain(emptyName, emptyName, user1, TEST_INTEROPERABLE_ADDRESS);

        // Verify registration
        assertEq(
            resolver.getChainAdmin(emptyLabelHash),
            user1,
            "Empty chain name should be registrable"
        );
        assertEq(
            resolver.interoperableAddress(emptyLabelHash),
            TEST_INTEROPERABLE_ADDRESS,
            "Chain ID should be set for empty name"
        );

        vm.stopPrank();

        console.log("Successfully registered empty chain name");
    }

    function test_002____register____________________VeryLongChainName()
        public
    {
        vm.startPrank(admin);

        // Try to register with very long chain name
        string
            memory longName = "this_is_a_very_long_chain_name_that_is_much_longer_than_normal_chain_names_used_in_blockchain_ecosystems_and_should_test_the_limits_of_the_registration_system";
        bytes32 longLabelHash = keccak256(bytes(longName));

        // This should work - long names are valid
        registerChain(longName, longName, user1, TEST_INTEROPERABLE_ADDRESS);

        // Verify registration
        assertEq(
            resolver.getChainAdmin(longLabelHash),
            user1,
            "Long chain name should be registrable"
        );
        assertEq(
            resolver.interoperableAddress(longLabelHash),
            TEST_INTEROPERABLE_ADDRESS,
            "Chain ID should be set for long name"
        );
        assertEq(
            resolver.chainName(TEST_INTEROPERABLE_ADDRESS),
            longName,
            "Long chain name correctly reverse resolves"
        );

        vm.stopPrank();

        console.log("Successfully registered very long chain name");
    }

    function test_003____register____________________EmptyChainId() public {
        vm.startPrank(admin);

        // Try to register with empty chain ID
        bytes memory emptyChainId = "";

        registerChain(TEST_LABEL, TEST_CHAIN_NAME, user1, emptyChainId);

        // Verify registration
        assertEq(
            resolver.getChainAdmin(TEST_LABELHASH),
            user1,
            "Owner should be set"
        );
        assertEq(
            resolver.interoperableAddress(TEST_LABELHASH),
            emptyChainId,
            "Empty chain ID should be stored"
        );
        assertEq(
            resolver.chainName(emptyChainId),
            TEST_CHAIN_NAME,
            "Chain name should be stored"
        );

        vm.stopPrank();

        console.log("Successfully registered with empty chain ID");
    }

    function test_004____register____________________VeryLongChainId() public {
        vm.startPrank(admin);

        // Try to register with very long chain ID
        bytes memory longChainId = new bytes(1000);
        for (uint256 i = 0; i < longChainId.length; i++) {
            longChainId[i] = bytes1(uint8(i % 256));
        }

        registerChain(TEST_LABEL, TEST_CHAIN_NAME, user1, longChainId);

        // Verify registration
        assertEq(
            resolver.getChainAdmin(TEST_LABELHASH),
            user1,
            "Owner should be set"
        );
        assertEq(
            resolver.interoperableAddress(TEST_LABELHASH),
            longChainId,
            "Long chain ID should be stored"
        );
        assertEq(
            resolver.chainName(longChainId),
            TEST_CHAIN_NAME,
            "Chain name should be stored"
        );

        vm.stopPrank();

        console.log("Successfully registered with very long chain ID");
    }

    function test_005____resolve_____________________UnknownSelector() public {
        vm.startPrank(admin);
        registerTestChain();
        vm.stopPrank();

        // Test resolve with unknown selector
        bytes memory name = dnsEncodeLabel(TEST_LABEL);
        bytes memory unknownData = abi.encodeWithSelector(
            bytes4(0x12345678),
            TEST_LABELHASH
        );
        bytes memory result = resolver.resolve(name, unknownData);

        // Should return empty string for unknown selector
        assertEq(result, abi.encode(""));

        console.log("Successfully handled unknown selector");
    }

    function test_006____supportsInterface___________InterfaceSupport()
        public
        view
    {
        // Interface support across common and arbitrary IDs (edge cases)

        // Test with various interface IDs
        bytes4[] memory testInterfaces = new bytes4[](10);
        testInterfaces[0] = type(IERC165).interfaceId;
        testInterfaces[1] = type(IExtendedResolver).interfaceId;
        testInterfaces[2] = type(IChainResolver).interfaceId;
        testInterfaces[3] = 0x00000000; // Zero interface
        testInterfaces[4] = 0xffffffff; // Max interface
        testInterfaces[5] = 0x12345678; // Random interface
        testInterfaces[6] = 0xabcdef01; // Another random interface
        testInterfaces[7] = 0x00000001; // Single bit set
        testInterfaces[8] = 0x80000000; // High bit set
        testInterfaces[9] = 0x55555555; // Alternating bits

        bool[] memory expectedResults = new bool[](10);
        expectedResults[0] = true; // IERC165
        expectedResults[1] = true; // IExtendedResolver
        expectedResults[2] = true; // IChainResolver
        expectedResults[3] = false; // Zero interface
        expectedResults[4] = false; // Max interface
        expectedResults[5] = false; // Random interface
        expectedResults[6] = false; // Another random interface
        expectedResults[7] = false; // Single bit set
        expectedResults[8] = false; // High bit set
        expectedResults[9] = false; // Alternating bits

        for (uint256 i = 0; i < testInterfaces.length; i++) {
            bool result = resolver.supportsInterface(testInterfaces[i]);
            assertEq(
                result,
                expectedResults[i],
                string(
                    abi.encodePacked(
                        "Interface ",
                        vm.toString(i),
                        " should return expected result"
                    )
                )
            );
        }

        console.log("Successfully handled interface support");
    }

    function test_007____bytesToAddress_______________RevertsOnInvalidLength()
        public
    {
        vm.startPrank(admin);
        registerTestChain();
        vm.stopPrank();

        vm.startPrank(user1);

        // Test setAddr with invalid length (not 20 bytes)
        bytes memory invalidBytes = hex"1234"; // 2 bytes instead of 20

        // This should revert because bytesToAddress is internal and requires 20 bytes
        // We can't directly test this function since it's internal, but we can test
        // the setAddr function that uses it with invalid data

        vm.expectRevert();
        resolver.setAddr(TEST_LABELHASH, 60, invalidBytes); // Use the coinType version

        vm.stopPrank();

        console.log("Successfully reverted on invalid address length");
    }

    function test_008____setAddr_____________________NonEthereumCoinType()
        public
    {
        vm.startPrank(admin);
        registerTestChain();
        vm.stopPrank();

        vm.startPrank(user1);

        // Test setAddr with non-Ethereum coin type
        address testAddr = address(0x1234567890123456789012345678901234567890);
        uint256 nonEthereumCoinType = 1; // Bitcoin coin type

        // This should set the address for the requested non-Ethereum coin type (generic storage),
        // but NOT affect the ETH (60) record.
        resolver.setAddr(
            TEST_LABELHASH,
            nonEthereumCoinType,
            abi.encodePacked(testAddr)
        );

        // ETH address remains unset
        bytes memory retrievedAddr = resolver.getAddr(TEST_LABELHASH, 60); // Ethereum coin type
        assertEq(
            retrievedAddr.length,
            0,
            "Non-Ethereum addresses should not be retrievable via getAddr"
        );

        // The generic coin type record should be retrievable as raw bytes
        bytes memory nonEth = resolver.getAddr(TEST_LABELHASH, nonEthereumCoinType);
        assertEq(
            nonEth,
            abi.encodePacked(testAddr),
            "Non-Ethereum coin type should be stored and retrievable"
        );

        vm.stopPrank();

        console.log("Successfully handled non-Ethereum coin type");
    }

    function test_009____startsWith__________________NoOverrideForDataKeysShorterThanPrefix()
        public
    {
        vm.startPrank(admin);
        registerTestChain();
        vm.stopPrank();

        vm.startPrank(user1);

        // Test _startsWith with data shorter than prefix
        // This tests the internal _startsWith function through setText with chain-name: prefix
        string memory shortKey = "test-key"; // Regular key that doesn't trigger special handling

        // This should not revert but should not match the prefix
        resolver.setText(TEST_LABELHASH, shortKey, "test-value");

        // Verify the text was set (not handled by special logic)
        string memory retrievedValue = resolver.getText(TEST_LABELHASH, shortKey);
        assertEq(
            retrievedValue,
            "test-value",
            "Short key should be stored as regular text"
        );

        vm.stopPrank();

        console.log("Successfully handled data shorter than prefix");
    }

    function test_010____startsWith__________________NoOverrideForPrefixMismatch()
        public
    {
        vm.startPrank(admin);
        registerTestChain();
        vm.stopPrank();

        vm.startPrank(user1);

        // Test _startsWith with same-length-or-longer key that mismatches the prefix
        // Prefix is "chain-name:"; here we use "chain-nom:abcdef" which is >= length but differs
        string memory nonMatchingKey = "chain-nom:abcdef";

        // This should not revert but should not match the prefix
        resolver.setText(TEST_LABELHASH, nonMatchingKey, "test-value");

        // Verify the text was set (no override due to prefix mismatch)
        string memory retrievedValue = resolver.getText(
            TEST_LABELHASH,
            nonMatchingKey
        );
        assertEq(
            retrievedValue,
            "test-value",
            "Non-matching key should be stored as regular text"
        );

        vm.stopPrank();

        console.log("Successfully handled data that doesn't match prefix");
    }

    function test_011____bytesToAddress_______________ValidAddressConversion()
        public
    {
        vm.startPrank(admin);
        registerTestChain();
        vm.stopPrank();

        vm.startPrank(user1);

        // Test bytesToAddress with valid data through setAddr
        address testAddr = address(0x1234567890123456789012345678901234567890);
        resolver.setAddr(TEST_LABELHASH, 60, abi.encodePacked(testAddr));

        // Now resolve it to trigger bytesToAddress with valid data
        bytes memory name = dnsEncodeLabel(TEST_LABEL);
        bytes memory addrData = abi.encodeWithSelector(
            resolver.ADDR_SELECTOR(),
            TEST_LABELHASH
        );
        bytes memory result = resolver.resolve(name, addrData);
        address resolvedAddr = abi.decode(result, (address));

        // Should return the same address
        assertEq(resolvedAddr, testAddr);

        vm.stopPrank();

        console.log("Successfully converted valid address bytes");
    }
}
