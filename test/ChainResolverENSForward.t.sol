// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "../src/ChainResolver.sol";

contract ChainResolverENSForwardTest is Test {
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
    function test1100_____________________________ENS_FORWARD____________________________________() public {}
    function test1200________________________________________________________________________________() public {}

    function test_001____setAddr_____________________SetsAddressRecords() public {
        vm.startPrank(admin);

        // Register a chain
        resolver.register(CHAIN_NAME, user1, CHAIN_ID);

        vm.stopPrank();

        // User1 sets address record
        vm.startPrank(user1);

        address testAddr = address(0x123);
        resolver.setAddr(LABEL_HASH, 60, testAddr); // ETH coin type

        // Verify address record
        assertEq(resolver.getAddr(LABEL_HASH, 60), testAddr, "Address record should be set");

        vm.stopPrank();

        console.log("Successfully set address record");
    }

    function test_002____setText_____________________SetsTextRecords() public {
        vm.startPrank(admin);

        // Register a chain
        resolver.register(CHAIN_NAME, user1, CHAIN_ID);

        vm.stopPrank();

        // User1 sets text record
        vm.startPrank(user1);

        resolver.setText(LABEL_HASH, "description", "Optimism Layer 2");
        resolver.setText(LABEL_HASH, "website", "https://optimism.io");

        // Verify text records
        assertEq(resolver.getText(LABEL_HASH, "description"), "Optimism Layer 2", "Description should be set");
        assertEq(resolver.getText(LABEL_HASH, "website"), "https://optimism.io", "Website should be set");

        vm.stopPrank();

        console.log("Successfully set text records");
    }

    function test_003____setData_____________________SetsDataRecords() public {
        vm.startPrank(admin);

        // Register a chain
        resolver.register(CHAIN_NAME, user1, CHAIN_ID);

        vm.stopPrank();

        // User1 sets data record
        vm.startPrank(user1);

        bytes memory testData = hex"deadbeef";
        resolver.setData(LABEL_HASH, "custom", testData);

        // Verify data record
        assertEq(resolver.getData(LABEL_HASH, "custom"), testData, "Data record should be set");

        vm.stopPrank();

        console.log("Successfully set data record");
    }

    function test_004____setContenthash______________SetsContentHash() public {
        vm.startPrank(admin);

        // Register a chain
        resolver.register(CHAIN_NAME, user1, CHAIN_ID);

        vm.stopPrank();

        // User1 sets content hash
        vm.startPrank(user1);

        bytes memory contentHash = hex"e301017012201234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";
        resolver.setContenthash(LABEL_HASH, contentHash);

        // Verify content hash
        assertEq(resolver.getContenthash(LABEL_HASH), contentHash, "Content hash should be set");

        vm.stopPrank();

        console.log("Successfully set content hash");
    }

    function test_005____resolve_____________________ResolvesENSRecords() public {
        vm.startPrank(admin);

        // Register a chain
        resolver.register(CHAIN_NAME, user1, CHAIN_ID);

        vm.stopPrank();

        // User1 sets some records
        vm.startPrank(user1);

        address testAddr = address(0x456);
        resolver.setAddr(LABEL_HASH, 60, testAddr);
        resolver.setText(LABEL_HASH, "description", "Test chain");

        vm.stopPrank();

        // Test resolve function with proper DNS encoding
        // DNS format: length byte + name bytes + null terminator
        bytes memory name = abi.encodePacked(bytes1(uint8(bytes(CHAIN_NAME).length)), bytes(CHAIN_NAME), bytes1(0x00));

        // Test addr(bytes32) selector
        bytes memory addrData = abi.encodeWithSelector(resolver.ADDR_SELECTOR(), LABEL_HASH);
        bytes memory result = resolver.resolve(name, addrData);
        address resolvedAddr = abi.decode(result, (address));
        assertEq(resolvedAddr, testAddr, "Should resolve address correctly");

        // Test text(bytes32,string) selector
        bytes memory textData = abi.encodeWithSelector(resolver.TEXT_SELECTOR(), LABEL_HASH, "description");
        bytes memory textResult = resolver.resolve(name, textData);
        string memory resolvedText = abi.decode(textResult, (string));
        assertEq(resolvedText, "Test chain", "Should resolve text correctly");

        console.log("Successfully resolved ENS records via resolve function");
    }

    function test_006____resolve_____________________ResolvesChainIdTextRecord() public {
        vm.startPrank(admin);

        // Register a chain
        resolver.register(CHAIN_NAME, user1, CHAIN_ID);

        vm.stopPrank();

        // Test resolve function for chain-id text record with proper DNS encoding
        bytes memory name = abi.encodePacked(bytes1(uint8(bytes(CHAIN_NAME).length)), bytes(CHAIN_NAME), bytes1(0x00));
        bytes memory textData = abi.encodeWithSelector(resolver.TEXT_SELECTOR(), LABEL_HASH, "chain-id");
        bytes memory result = resolver.resolve(name, textData);
        string memory resolvedChainId = abi.decode(result, (string));

        // Should return hex representation of chain ID (without 0x prefix)
        string memory expectedHex = "000000010001010a00";
        assertEq(resolvedChainId, expectedHex, "Should resolve chain-id as hex string");

        console.log("Successfully resolved chain-id text record");
        console.log("Resolved chain ID:", resolvedChainId);
    }

    function test_007____resolve_____________________ResolvesChainIdDataRecord() public {
        vm.startPrank(admin);

        // Register a chain
        resolver.register(CHAIN_NAME, user1, CHAIN_ID);

        vm.stopPrank();

        // Test that we can set and retrieve a custom data record via resolve function
        vm.startPrank(user1);

        bytes memory customData = hex"deadbeef";
        resolver.setData(LABEL_HASH, "custom", customData);

        vm.stopPrank();

        // Test resolve function for custom data record with proper DNS encoding
        bytes memory name = abi.encodePacked(bytes1(uint8(bytes(CHAIN_NAME).length)), bytes(CHAIN_NAME), bytes1(0x00));
        bytes memory dataData = abi.encodeWithSelector(resolver.DATA_SELECTOR(), LABEL_HASH, "custom");
        bytes memory result = resolver.resolve(name, dataData);
        bytes memory resolvedData = abi.decode(result, (bytes));

        // Should return the custom data we set
        assertEq(resolvedData, customData, "Should resolve custom data record via resolve function");

        console.log("Successfully resolved custom data record via resolve function");
    }

    function test_008____supportsInterface___________ReturnsCorrectInterfaceIds() public view {
        // Test IERC165
        assertTrue(resolver.supportsInterface(type(IERC165).interfaceId), "Should support IERC165");

        // Test IExtendedResolver
        assertTrue(resolver.supportsInterface(type(IExtendedResolver).interfaceId), "Should support IExtendedResolver");

        // Test IChainResolver
        assertTrue(resolver.supportsInterface(type(IChainResolver).interfaceId), "Should support IChainResolver");

        // Test unsupported interface
        assertFalse(resolver.supportsInterface(0x12345678), "Should not support random interface");

        console.log("Successfully verified interface support");
    }
}
