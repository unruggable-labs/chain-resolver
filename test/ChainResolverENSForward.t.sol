// SPDX-License-Identifier: MIT

// Tests for forward resolution of all record types.
// This includes address, text, data, and contenthash records.

pragma solidity ^0.8.25;

import "./ChainResolverTestBase.sol";

contract ChainResolverENSForwardTest is ChainResolverTestBase {
    address public operator = address(0x4);

    // Expected namehash for events (namehash("optimism.PARENT_DOMAIN"))
    bytes32 public EXPECTED_NAMEHASH;

    function setUp() public {
        vm.startPrank(admin);
        bytes32 parentNamehash = NameCoder.namehash(
            NameCoder.encode(PARENT_DOMAIN),
            0
        );
        EXPECTED_NAMEHASH = keccak256(
            abi.encodePacked(parentNamehash, TEST_LABELHASH)
        );
        resolver = deployResolverWithNamehash(admin, parentNamehash);
        vm.stopPrank();
    }

    function test_001____setAddr_____________________SetsAddressRecords()
        public
    {
        vm.startPrank(admin);
        registerTestChain();
        vm.stopPrank();

        // User1 sets address record
        vm.startPrank(user1);

        address testAddr = address(0x123);
        resolver.setAddr(TEST_LABELHASH, 60, abi.encodePacked(testAddr)); // ETH coin type

        // Verify address record (packed 20-byte value)
        bytes memory ethVal = resolver.getAddr(TEST_LABEL, 60);
        assertEq(
            ethVal,
            abi.encodePacked(testAddr),
            "Address record should be set"
        );

        vm.stopPrank();

        console.log("Successfully set address record");
    }

    function test_002____setText_____________________SetsTextRecords() public {
        vm.startPrank(admin);
        registerTestChain();
        vm.stopPrank();

        // User1 sets text record
        vm.startPrank(user1);

        resolver.setText(TEST_LABELHASH, "description", "Optimism Layer 2");
        resolver.setText(TEST_LABELHASH, "url", "https://optimism.io");

        // Verify text records
        assertEq(
            resolver.getText(TEST_LABEL, "description"),
            "Optimism Layer 2",
            "Description should be set"
        );
        assertEq(
            resolver.getText(TEST_LABEL, "url"),
            "https://optimism.io",
            "Website should be set"
        );

        vm.stopPrank();

        console.log("Successfully set text records");
    }

    function test_003____setData_____________________SetsDataRecords() public {
        vm.startPrank(admin);
        registerTestChain();
        vm.stopPrank();

        // User1 sets data record
        vm.startPrank(user1);

        bytes memory testData = hex"deadbeef";
        vm.expectEmit(true, true, false, true);
        emit IChainResolver.DataChanged(
            EXPECTED_NAMEHASH,
            "custom",
            "custom",
            testData
        );
        resolver.setData(TEST_LABELHASH, "custom", testData);

        // Verify data record
        assertEq(
            resolver.getData(TEST_LABEL, "custom"),
            testData,
            "Data record should be set"
        );

        vm.stopPrank();

        console.log("Successfully set data record");
    }

    function test_004____setContenthash______________SetsContentHash() public {
        vm.startPrank(admin);
        registerTestChain();
        vm.stopPrank();

        // User1 sets content hash
        vm.startPrank(user1);

        bytes
            memory contentHash = hex"e301017012201234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";
        resolver.setContenthash(TEST_LABELHASH, contentHash);

        // Verify content hash
        assertEq(
            resolver.getContenthash(TEST_LABEL),
            contentHash,
            "Content hash should be set"
        );

        vm.stopPrank();

        console.log("Successfully set content hash");
    }

    function test_005____resolve_____________________ResolvesInteroperableAddressDataRecord()
        public
    {
        vm.startPrank(admin);
        registerTestChain();
        vm.stopPrank();

        // Test resolve function for interoperable-address data record (raw bytes) with proper DNS encoding
        bytes memory name = dnsEncodeLabel(TEST_LABEL);
        bytes4 dataSelector = bytes4(keccak256("data(bytes32,string)"));
        bytes memory data = abi.encodeWithSelector(
            dataSelector,
            TEST_LABELHASH,
            "interoperable-address"
        );
        bytes memory result = resolver.resolve(name, data);
        bytes memory resolvedChainIdBytes = abi.decode(result, (bytes));

        // Should return the raw 7930 bytes
        assertEq(
            resolvedChainIdBytes,
            TEST_INTEROPERABLE_ADDRESS,
            "Should resolve interoperable-address as raw bytes via data()"
        );

        console.log("Successfully resolved interoperable-address via data record");
    }

    function test_007____resolve_____________________ResolvesCustomDataRecord()
        public
    {
        vm.startPrank(admin);
        registerTestChain();
        vm.stopPrank();

        // Test that we can set and retrieve a custom data record via resolve function
        vm.startPrank(user1);

        bytes memory customData = hex"deadbeef";
        resolver.setData(TEST_LABELHASH, "custom", customData);

        vm.stopPrank();

        // Test resolve function for custom data record with proper DNS encoding
        bytes memory name = dnsEncodeLabel(TEST_LABEL);
        bytes4 dataSelector = bytes4(keccak256("data(bytes32,string)"));
        bytes memory data = abi.encodeWithSelector(
            dataSelector,
            TEST_LABELHASH,
            "custom"
        );
        bytes memory result = resolver.resolve(name, data);
        bytes memory resolvedData = abi.decode(result, (bytes));

        // Should return the custom data we set
        assertEq(
            resolvedData,
            customData,
            "Should resolve custom data record via resolve function"
        );

        console.log(
            "Successfully resolved custom data record via resolve function"
        );
    }

    function test_008____setAddr_____________________RevertsOnInvalidEthBytes()
        public
    {
        vm.startPrank(admin);
        registerTestChain();
        vm.stopPrank();

        // Attempt to set ETH address using bytes with invalid length should revert
        vm.startPrank(user1);
        vm.expectRevert();
        resolver.setAddr(TEST_LABELHASH, 60, hex"deadbeef");
        vm.stopPrank();

        // Ensure nothing was written
        assertEq(
            resolver.getAddr(TEST_LABEL, 60),
            hex"",
            "ETH address storage should remain empty on invalid bytes"
        );
    }

    function test_009____supportsInterface___________ReturnsCorrectInterfaceIds()
        public
        view
    {
        // Test IERC165
        assertTrue(
            resolver.supportsInterface(type(IERC165).interfaceId),
            "Should support IERC165"
        );

        // Test IExtendedResolver
        assertTrue(
            resolver.supportsInterface(type(IExtendedResolver).interfaceId),
            "Should support IExtendedResolver"
        );

        // Test IChainResolver
        assertTrue(
            resolver.supportsInterface(type(IChainResolver).interfaceId),
            "Should support IChainResolver"
        );

        // Test unsupported interface
        assertFalse(
            resolver.supportsInterface(0x12345678),
            "Should not support random interface"
        );

        console.log("Successfully verified interface support");
    }

    function test_010____resolve_____________________ContentHashSelector()
        public
    {
        vm.startPrank(admin);
        registerTestChain();
        vm.stopPrank();

        vm.startPrank(user1);

        // Set a content hash
        bytes
            memory testContentHash = hex"e301017012201234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";
        resolver.setContenthash(TEST_LABELHASH, testContentHash);

        // Now resolve it with CONTENTHASH_SELECTOR
        bytes memory name = dnsEncodeLabel(TEST_LABEL);
        bytes4 contenthashSelector = bytes4(keccak256("contenthash(bytes32)"));
        bytes memory contentHashData = abi.encodeWithSelector(
            contenthashSelector,
            TEST_LABELHASH
        );
        bytes memory result = resolver.resolve(name, contentHashData);
        bytes memory resolvedContentHash = abi.decode(result, (bytes));

        // Should return the same content hash
        assertEq(resolvedContentHash, testContentHash);

        vm.stopPrank();

        console.log(
            "Successfully resolved content hash via CONTENTHASH_SELECTOR"
        );
    }

    function test_011____resolve_____________________CustomTextRecords()
        public
    {
        vm.startPrank(admin);
        registerTestChain();
        vm.stopPrank();

        // User1 sets a custom text record
        vm.startPrank(user1);

        string memory customTextKey = "profile:bio";
        string memory customTextVal = "gm-chain-resolver";
        resolver.setText(TEST_LABELHASH, customTextKey, customTextVal);

        vm.stopPrank();

        // Prepare DNS-encoded name for resolve()
        bytes memory name = dnsEncodeLabel(TEST_LABEL);

        // Resolve custom text record
        bytes4 textSelector = bytes4(keccak256("text(bytes32,string)"));
        bytes memory textCalldata = abi.encodeWithSelector(
            textSelector,
            TEST_LABELHASH,
            customTextKey
        );
        bytes memory textAnswer = resolver.resolve(name, textCalldata);
        string memory resolvedText = abi.decode(textAnswer, (string));
        assertEq(
            resolvedText,
            customTextVal,
            "Should resolve custom text record via resolve"
        );

        console.log("Successfully resolved custom text");
    }

    function test_012____resolve_____________________ContenthashEmptyForUnregisteredLabel()
        public
    {
        bytes memory defaultCh = hex"e30101701220deadbeef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";

        vm.startPrank(admin);
        resolver.setDefaultContenthash(defaultCh);
        vm.stopPrank();

        // Query contenthash for a label that was never registered.
        bytes memory name = dnsEncodeLabel("never-registered");
        bytes4 contenthashSelector = bytes4(keccak256("contenthash(bytes32)"));
        bytes memory data = abi.encodeWithSelector(
            contenthashSelector,
            keccak256("never-registered")
        );
        bytes memory result = resolver.resolve(name, data);
        bytes memory ch = abi.decode(result, (bytes));

        assertEq(
            ch.length,
            0,
            "Unregistered label must not return the default contenthash"
        );

        console.log("Unregistered label returns empty contenthash");
    }

    function test_013____resolve_____________________ContenthashDefaultForBaseName()
        public
    {
        bytes memory defaultCh = hex"e30101701220deadbeef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";

        vm.startPrank(admin);
        resolver.setDefaultContenthash(defaultCh);
        vm.stopPrank();

        // The bare parent name (e.g. on.eth) resolves to defaultContenthash.
        bytes memory name = dnsEncode(PARENT_DOMAIN);
        bytes4 contenthashSelector = bytes4(keccak256("contenthash(bytes32)"));
        bytes memory data = abi.encodeWithSelector(
            contenthashSelector,
            bytes32(0)
        );
        bytes memory result = resolver.resolve(name, data);
        bytes memory ch = abi.decode(result, (bytes));

        assertEq(ch, defaultCh, "Base name should return defaultContenthash");

        console.log("Base name returns defaultContenthash");
    }

    function test_014____resolve_____________________ContenthashDefaultForRegisteredLabel()
        public
    {
        bytes memory defaultCh = hex"e30101701220deadbeef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";

        vm.startPrank(admin);
        resolver.setDefaultContenthash(defaultCh);
        registerTestChain();
        vm.stopPrank();

        // Registered label with no specific contenthash falls back to default.
        bytes memory name = dnsEncodeLabel(TEST_LABEL);
        bytes4 contenthashSelector = bytes4(keccak256("contenthash(bytes32)"));
        bytes memory data = abi.encodeWithSelector(
            contenthashSelector,
            TEST_LABELHASH
        );
        bytes memory result = resolver.resolve(name, data);
        bytes memory ch = abi.decode(result, (bytes));

        assertEq(
            ch,
            defaultCh,
            "Registered label should fall back to defaultContenthash"
        );

        console.log("Registered label falls back to defaultContenthash");
    }

    function test_015____resolve_____________________ContenthashDefaultForAlias()
        public
    {
        bytes memory defaultCh = hex"e30101701220deadbeef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";

        vm.startPrank(admin);
        resolver.setDefaultContenthash(defaultCh);
        registerTestChain();
        resolver.registerAlias("op", TEST_LABELHASH);
        vm.stopPrank();

        // Alias of a registered chain still resolves through to defaultContenthash.
        bytes memory name = dnsEncodeLabel("op");
        bytes4 contenthashSelector = bytes4(keccak256("contenthash(bytes32)"));
        bytes memory data = abi.encodeWithSelector(
            contenthashSelector,
            keccak256("op")
        );
        bytes memory result = resolver.resolve(name, data);
        bytes memory ch = abi.decode(result, (bytes));

        assertEq(ch, defaultCh, "Alias should resolve to defaultContenthash");

        console.log("Alias of registered chain falls back to defaultContenthash");
    }

    function test_016____resolve_____________________ContenthashEmptyForDeepUnregisteredName()
        public
    {
        bytes memory defaultCh = hex"e30101701220deadbeef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";

        vm.startPrank(admin);
        resolver.setDefaultContenthash(defaultCh);
        registerTestChain();
        vm.stopPrank();

        // A deeply-nested name like "a.b.optimism.cid.eth" has first label "a"
        // which is unregistered, so it must return empty contenthash. This is
        // the abuse vector eth.limo wildcards exposed.
        bytes memory name = dnsEncode(
            string(abi.encodePacked("a.b.", TEST_LABEL, ".", PARENT_DOMAIN))
        );
        bytes4 contenthashSelector = bytes4(keccak256("contenthash(bytes32)"));
        bytes memory data = abi.encodeWithSelector(
            contenthashSelector,
            keccak256("a")
        );
        bytes memory result = resolver.resolve(name, data);
        bytes memory ch = abi.decode(result, (bytes));

        assertEq(
            ch.length,
            0,
            "Deep name with unregistered first label must return empty"
        );

        console.log("Deep unregistered name returns empty contenthash");
    }

    function test_017____getContenthash______________EmptyForUnregisteredLabel()
        public
    {
        bytes memory defaultCh = hex"e30101701220deadbeef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";

        vm.startPrank(admin);
        resolver.setDefaultContenthash(defaultCh);
        vm.stopPrank();

        // Direct getter must also return empty for unknown labels.
        assertEq(
            resolver.getContenthash("never-registered").length,
            0,
            "Unregistered label must return empty from getContenthash"
        );

        console.log("getContenthash returns empty for unregistered label");
    }
}
