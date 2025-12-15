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

    function test_001____register____________________EmptyLabelReverts() public {
        vm.startPrank(admin);

        // Try to register with empty label - should revert
        vm.expectRevert(IChainResolver.EmptyLabel.selector);
        registerChain("", TEST_CHAIN_NAME, user1, TEST_INTEROPERABLE_ADDRESS);

        vm.stopPrank();

        console.log("Successfully reverted on empty label");
    }

    function test_002____register____________________EmptyChainNameReverts() public {
        vm.startPrank(admin);

        // Try to register with empty chain name - should revert
        vm.expectRevert(IChainResolver.EmptyChainName.selector);
        registerChain(TEST_LABEL, "", user1, TEST_INTEROPERABLE_ADDRESS);

        vm.stopPrank();

        console.log("Successfully reverted on empty chain name");
    }

    function test_003____register____________________VeryLongChainName()
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
            resolver.getChainAdmin(longName),
            user1,
            "Long chain name should be registrable"
        );
        assertEq(
            resolver.interoperableAddress(longName),
            TEST_INTEROPERABLE_ADDRESS,
            "Chain ID should be set for long name"
        );
        assertEq(
            resolver.chainName(longName),
            longName,
            "Long chain name correctly resolves"
        );

        vm.stopPrank();

        console.log("Successfully registered very long chain name");
    }

    function test_004____register____________________ShortInteroperableAddressReverts() public {
        vm.startPrank(admin);

        // Try to register with interoperable address < 7 bytes - should revert
        bytes memory shortAddress = hex"010203040506"; // 6 bytes

        vm.expectRevert(IChainResolver.InvalidInteroperableAddress.selector);
        registerChain(TEST_LABEL, TEST_CHAIN_NAME, user1, shortAddress);

        vm.stopPrank();

        console.log("Successfully reverted on short interoperable address");
    }

    function test_005____register____________________EmptyInteroperableAddressReverts() public {
        vm.startPrank(admin);

        // Try to register with empty interoperable address - should revert
        vm.expectRevert(IChainResolver.InvalidInteroperableAddress.selector);
        registerChain(TEST_LABEL, TEST_CHAIN_NAME, user1, "");

        vm.stopPrank();

        console.log("Successfully reverted on empty interoperable address");
    }

    function test_006____register____________________VeryLongChainId() public {
        vm.startPrank(admin);

        // Try to register with very long chain ID
        bytes memory longChainId = new bytes(1000);
        for (uint256 i = 0; i < longChainId.length; i++) {
            longChainId[i] = bytes1(uint8(i % 256));
        }

        registerChain(TEST_LABEL, TEST_CHAIN_NAME, user1, longChainId);

        // Verify registration
        assertEq(
            resolver.getChainAdmin(TEST_LABEL),
            user1,
            "Owner should be set"
        );
        assertEq(
            resolver.interoperableAddress(TEST_LABEL),
            longChainId,
            "Long chain ID should be stored"
        );
        assertEq(
            resolver.chainName(TEST_LABEL),
            TEST_CHAIN_NAME,
            "Chain name should be stored"
        );

        vm.stopPrank();

        console.log("Successfully registered with very long chain ID");
    }

    function test_007____resolve_____________________UnknownSelector() public {
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

    function test_008____supportsInterface___________InterfaceSupport()
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

    function test_009____bytesToAddress_______________RevertsOnInvalidLength()
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

    function test_010____setAddr_____________________NonEthereumCoinType()
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
        bytes memory retrievedAddr = resolver.getAddr(TEST_LABEL, 60); // Ethereum coin type
        assertEq(
            retrievedAddr.length,
            0,
            "Non-Ethereum addresses should not be retrievable via getAddr"
        );

        // The generic coin type record should be retrievable as raw bytes
        bytes memory nonEth = resolver.getAddr(TEST_LABEL, nonEthereumCoinType);
        assertEq(
            nonEth,
            abi.encodePacked(testAddr),
            "Non-Ethereum coin type should be stored and retrievable"
        );

        vm.stopPrank();

        console.log("Successfully handled non-Ethereum coin type");
    }

    function test_011____startsWith__________________NoOverrideForDataKeysShorterThanPrefix()
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
        string memory retrievedValue = resolver.getText(TEST_LABEL, shortKey);
        assertEq(
            retrievedValue,
            "test-value",
            "Short key should be stored as regular text"
        );

        vm.stopPrank();

        console.log("Successfully handled data shorter than prefix");
    }

    function test_012____startsWith__________________NoOverrideForPrefixMismatch()
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
            TEST_LABEL,
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

    function test_013____bytesToAddress_______________ValidAddressConversion()
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
        bytes4 addrSelector = bytes4(keccak256("addr(bytes32)"));
        bytes memory addrData = abi.encodeWithSelector(
            addrSelector,
            TEST_LABELHASH
        );
        bytes memory result = resolver.resolve(name, addrData);
        address resolvedAddr = abi.decode(result, (address));

        // Should return the same address
        assertEq(resolvedAddr, testAddr);

        vm.stopPrank();

        console.log("Successfully converted valid address bytes");
    }

    //////
    /// BASE NAME RECORDS TESTS
    //////

    function test_014____setText_____________________BaseNameTextRecord() public {
        vm.startPrank(admin);
        resolver = deployResolver(admin);
        vm.stopPrank();

        // Owner sets text record for base name (bytes32(0))
        vm.startPrank(admin);
        resolver.setText(bytes32(0), "url", "https://example.com");
        resolver.setText(bytes32(0), "description", "Base name description");
        vm.stopPrank();


        console.log("Successfully set text records for base name");
    }

    function test_015____setText_____________________BaseNameUnauthorized() public {
        vm.startPrank(admin);
        resolver = deployResolver(admin);
        vm.stopPrank();

        // Non-owner tries to set base name text record
        vm.startPrank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IChainResolver.NotChainOwner.selector,
                user1,
                bytes32(0)
            )
        );
        resolver.setText(bytes32(0), "url", "https://hacked.com");
        vm.stopPrank();


        console.log("Successfully prevented unauthorized base name text setting");
    }

    function test_016____setContenthash______________BaseNameContenthash() public {
        vm.startPrank(admin);
        resolver = deployResolver(admin);
        vm.stopPrank();

        bytes memory contenthash = hex"e30101701220deadbeef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";

        // Owner sets contenthash for base name
        vm.startPrank(admin);
        resolver.setContenthash(bytes32(0), contenthash);
        vm.stopPrank();


        console.log("Successfully set contenthash for base name");
    }

    function test_017____setAddr_____________________BaseNameAddress() public {
        vm.startPrank(admin);
        resolver = deployResolver(admin);
        vm.stopPrank();

        address testAddr = address(0x1234567890123456789012345678901234567890);

        // Owner sets address for base name
        vm.startPrank(admin);
        resolver.setAddr(bytes32(0), 60, abi.encodePacked(testAddr));
        vm.stopPrank();


        console.log("Successfully set address for base name");
    }

    function test_018____setData_____________________BaseNameDataRecord() public {
        vm.startPrank(admin);
        resolver = deployResolver(admin);
        vm.stopPrank();

        bytes memory testData = hex"deadbeef";

        // Owner sets data record for base name
        vm.startPrank(admin);
        resolver.setData(bytes32(0), "custom-key", testData);
        vm.stopPrank();


        console.log("Successfully set data record for base name");
    }

    function test_019____batchSetText________________BaseNameBatchText() public {
        vm.startPrank(admin);
        resolver = deployResolver(admin);
        vm.stopPrank();

        // Owner batch sets text records for base name
        vm.startPrank(admin);
        string[] memory keys = new string[](3);
        string[] memory values = new string[](3);
        keys[0] = "url";
        keys[1] = "description";
        keys[2] = "notice";
        values[0] = "https://example.com";
        values[1] = "Base name description";
        values[2] = "Base name notice";

        resolver.batchSetText(bytes32(0), keys, values);
        vm.stopPrank();


        console.log("Successfully batch set text records for base name");
    }

    function test_020____batchSetData________________BaseNameBatchData() public {
        vm.startPrank(admin);
        resolver = deployResolver(admin);
        vm.stopPrank();

        // Owner batch sets data records for base name
        vm.startPrank(admin);
        string[] memory keys = new string[](2);
        bytes[] memory data = new bytes[](2);
        keys[0] = "custom-1";
        keys[1] = "custom-2";
        data[0] = hex"deadbeef";
        data[1] = hex"cafebabe";

        resolver.batchSetData(bytes32(0), keys, data);
        vm.stopPrank();


        console.log("Successfully batch set data records for base name");
    }

    function test_021____resolve_____________________BaseNameViaResolve() public {
        vm.startPrank(admin);
        resolver = deployResolver(admin);
        vm.stopPrank();

        // Set a text record for base name
        vm.startPrank(admin);
        resolver.setText(bytes32(0), "url", "https://example.com");
        vm.stopPrank();

        // Resolve base name via ENSIP-10
        bytes memory baseName = dnsEncode(PARENT_DOMAIN);
        bytes32 baseNamehash = NameCoder.namehash(NameCoder.encode(PARENT_DOMAIN), 0);

        // Test text() resolution
        bytes4 textSelector = bytes4(keccak256("text(bytes32,string)"));
        bytes memory textCalldata = abi.encodeWithSelector(
            textSelector,
            baseNamehash,
            "url"
        );
        bytes memory textResponse = resolver.resolve(baseName, textCalldata);
        string memory resolvedUrl = abi.decode(textResponse, (string));

        assertEq(resolvedUrl, "https://example.com");

        console.log("Successfully resolved base name via ENSIP-10");
    }

    function test_022____supportedTextKeys___________BaseNameSupportedKeys() public {
        vm.startPrank(admin);
        resolver = deployResolver(admin);
        vm.stopPrank();

        // Set text records for base name
        vm.startPrank(admin);
        resolver.setText(bytes32(0), "url", "https://example.com");
        resolver.setText(bytes32(0), "description", "Base description");
        vm.stopPrank();

        // Get supported text keys for base name
        bytes32 baseNamehash = NameCoder.namehash(NameCoder.encode(PARENT_DOMAIN), 0);
        string[] memory keys = resolver.supportedTextKeys(baseNamehash);

        // Should include the keys we set
        assertTrue(keys.length >= 2);
        bool hasUrl = false;
        bool hasDescription = false;
        for (uint256 i = 0; i < keys.length; i++) {
            if (keccak256(bytes(keys[i])) == keccak256(bytes("url"))) {
                hasUrl = true;
            }
            if (keccak256(bytes(keys[i])) == keccak256(bytes("description"))) {
                hasDescription = true;
            }
        }
        assertTrue(hasUrl);
        assertTrue(hasDescription);

        console.log("Successfully retrieved supported text keys for base name");
    }

    function test_023____supportedDataKeys___________BaseNameSupportedDataKeys() public {
        vm.startPrank(admin);
        resolver = deployResolver(admin);
        vm.stopPrank();

        // Set data records for base name
        vm.startPrank(admin);
        resolver.setData(bytes32(0), "custom-1", hex"deadbeef");
        resolver.setData(bytes32(0), "custom-2", hex"cafebabe");
        vm.stopPrank();

        // Get supported data keys for base name
        bytes32 baseNamehash = NameCoder.namehash(NameCoder.encode(PARENT_DOMAIN), 0);
        string[] memory keys = resolver.supportedDataKeys(baseNamehash);

        // Should include the keys we set
        assertTrue(keys.length >= 2);
        bool hasCustom1 = false;
        bool hasCustom2 = false;
        for (uint256 i = 0; i < keys.length; i++) {
            if (keccak256(bytes(keys[i])) == keccak256(bytes("custom-1"))) {
                hasCustom1 = true;
            }
            if (keccak256(bytes(keys[i])) == keccak256(bytes("custom-2"))) {
                hasCustom2 = true;
            }
        }
        assertTrue(hasCustom1);
        assertTrue(hasCustom2);

        console.log("Successfully retrieved supported data keys for base name");
    }
}
