// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/ChainResolver.sol";
import "../src/interfaces/IChainResolver.sol";
import {NameCoder} from "@ensdomains/ens-contracts/contracts/utils/NameCoder.sol";

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
    bytes public constant CHAIN_ID = hex"00010001010a00";
    bytes32 public constant LABEL_HASH = keccak256(bytes(CHAIN_NAME));

    // Expected namehash for events (namehash("optimism.cid.eth"))
    bytes32 public EXPECTED_NAMEHASH;

    function setUp() public {
        vm.startPrank(admin);
        bytes32 parentNamehash = NameCoder.namehash(NameCoder.encode("cid.eth"), 0);
        EXPECTED_NAMEHASH = keccak256(abi.encodePacked(parentNamehash, LABEL_HASH));
        resolver = new ChainResolver(admin, parentNamehash);
        vm.stopPrank();
    }

    // Identify the file being tested
    function test1000________________________________________________________________________________() public {}
    function test1100_____________________________ENS_FORWARD____________________________________() public {}
    function test1200________________________________________________________________________________() public {}

    function test_001____setAddr_____________________SetsAddressRecords() public {
        vm.startPrank(admin);

        // Register a chain
        resolver.register(IChainResolver.ChainRegistrationData({label: CHAIN_NAME, chainName: CHAIN_NAME, owner: user1, interoperableAddress: CHAIN_ID}));

        vm.stopPrank();

        // User1 sets address record
        vm.startPrank(user1);

        address testAddr = address(0x123);
        resolver.setAddr(LABEL_HASH, 60, abi.encodePacked(testAddr)); // ETH coin type

        // Verify address record (packed 20-byte value)
        bytes memory ethVal = resolver.getAddr(LABEL_HASH, 60);
        assertEq(ethVal, abi.encodePacked(testAddr), "Address record should be set");

        vm.stopPrank();

        console.log("Successfully set address record");
    }

    function test_002____setText_____________________SetsTextRecords() public {
        vm.startPrank(admin);

        // Register a chain
        resolver.register(IChainResolver.ChainRegistrationData({label: CHAIN_NAME, chainName: CHAIN_NAME, owner: user1, interoperableAddress: CHAIN_ID}));

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
        resolver.register(IChainResolver.ChainRegistrationData({label: CHAIN_NAME, chainName: CHAIN_NAME, owner: user1, interoperableAddress: CHAIN_ID}));

        vm.stopPrank();

        // User1 sets data record
        vm.startPrank(user1);

        bytes memory testData = hex"deadbeef";
        vm.expectEmit(true, true, false, true);
        emit IChainResolver.DataChanged(EXPECTED_NAMEHASH, "custom", keccak256(bytes("custom")), keccak256(testData));
        resolver.setData(LABEL_HASH, "custom", testData);

        // Verify data record
        assertEq(resolver.getData(LABEL_HASH, "custom"), testData, "Data record should be set");

        vm.stopPrank();

        console.log("Successfully set data record");
    }

    function test_004____setContenthash______________SetsContentHash() public {
        vm.startPrank(admin);

        // Register a chain
        resolver.register(IChainResolver.ChainRegistrationData({label: CHAIN_NAME, chainName: CHAIN_NAME, owner: user1, interoperableAddress: CHAIN_ID}));

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

    function test_005____setText_____________________RevertsOnImmutableKey() public {
        vm.startPrank(admin);

        // Register a chain
        resolver.register(IChainResolver.ChainRegistrationData({label: CHAIN_NAME, chainName: CHAIN_NAME, owner: user1, interoperableAddress: CHAIN_ID}));

        vm.stopPrank();

        // Manually set a conflicting value for the special key to prove overrides apply
        // Even if a user sets textRecords["chain-id"] = "hacked",
        // _getTextWithOverrides ignores it and returns the canonical hex from internal mapping.
        vm.startPrank(user1);
        vm.expectRevert();
        resolver.setText(LABEL_HASH, "interoperable-address", "hacked");
        vm.stopPrank();
    }

    function test_006____resolve_____________________ResolvesChainIdDataRecord() public {
        vm.startPrank(admin);

        // Register a chain
        resolver.register(IChainResolver.ChainRegistrationData({label: CHAIN_NAME, chainName: CHAIN_NAME, owner: user1, interoperableAddress: CHAIN_ID}));

        vm.stopPrank();

        // Test resolve function for chain-id data record (raw bytes) with proper DNS encoding
        bytes memory name = abi.encodePacked(bytes1(uint8(bytes(CHAIN_NAME).length)), bytes(CHAIN_NAME), bytes1(0x00));
        bytes memory data = abi.encodeWithSelector(resolver.DATA_SELECTOR(), LABEL_HASH, "interoperable-address");
        bytes memory result = resolver.resolve(name, data);
        bytes memory resolvedChainIdBytes = abi.decode(result, (bytes));

        // Should return the raw 7930 bytes
        assertEq(resolvedChainIdBytes, CHAIN_ID, "Should resolve chain-id as raw bytes via data()");

        console.log("Successfully resolved chain-id via data record");
    }

    function test_007____resolve_____________________ResolvesCustomDataRecord() public {
        vm.startPrank(admin);

        // Register a chain
        resolver.register(IChainResolver.ChainRegistrationData({label: CHAIN_NAME, chainName: CHAIN_NAME, owner: user1, interoperableAddress: CHAIN_ID}));

        vm.stopPrank();

        // Test that we can set and retrieve a custom data record via resolve function
        vm.startPrank(user1);

        bytes memory customData = hex"deadbeef";
        resolver.setData(LABEL_HASH, "custom", customData);

        vm.stopPrank();

        // Test resolve function for custom data record with proper DNS encoding
        bytes memory name = abi.encodePacked(bytes1(uint8(bytes(CHAIN_NAME).length)), bytes(CHAIN_NAME), bytes1(0x00));
        bytes memory data = abi.encodeWithSelector(resolver.DATA_SELECTOR(), LABEL_HASH, "custom");
        bytes memory result = resolver.resolve(name, data);
        bytes memory resolvedData = abi.decode(result, (bytes));

        // Should return the custom data we set
        assertEq(resolvedData, customData, "Should resolve custom data record via resolve function");

        console.log("Successfully resolved custom data record via resolve function");
    }

    function test_008____setAddr_____________________RevertsOnInvalidEthBytes() public {
        vm.startPrank(admin);
        resolver.register(IChainResolver.ChainRegistrationData({label: CHAIN_NAME, chainName: CHAIN_NAME, owner: user1, interoperableAddress: CHAIN_ID}));
        vm.stopPrank();

        // Attempt to set ETH address using bytes with invalid length should revert
        vm.startPrank(user1);
        vm.expectRevert();
        resolver.setAddr(LABEL_HASH, 60, hex"deadbeef");
        vm.stopPrank();

        // Ensure nothing was written
        assertEq(resolver.getAddr(LABEL_HASH, 60), hex"", "ETH address storage should remain empty on invalid bytes");
    }

    function test_009____supportsInterface___________ReturnsCorrectInterfaceIds() public view {
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

    function test_010____resolve_____________________ContentHashSelector() public {
        vm.startPrank(admin);
        resolver.register(IChainResolver.ChainRegistrationData({label: CHAIN_NAME, chainName: CHAIN_NAME, owner: user1, interoperableAddress: CHAIN_ID}));
        vm.stopPrank();

        vm.startPrank(user1);

        // Set a content hash
        bytes memory testContentHash = hex"e301017012201234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";
        resolver.setContenthash(LABEL_HASH, testContentHash);

        // Now resolve it with CONTENTHASH_SELECTOR
        bytes memory name = abi.encodePacked(bytes1(uint8(bytes(CHAIN_NAME).length)), bytes(CHAIN_NAME), bytes1(0x00));
        bytes memory contentHashData = abi.encodeWithSelector(resolver.CONTENTHASH_SELECTOR(), LABEL_HASH);
        bytes memory result = resolver.resolve(name, contentHashData);
        bytes memory resolvedContentHash = abi.decode(result, (bytes));

        // Should return the same content hash
        assertEq(resolvedContentHash, testContentHash);

        vm.stopPrank();

        console.log("Successfully resolved content hash via CONTENTHASH_SELECTOR");
    }

    function test_011____resolve_____________________CustomTextRecords() public {
        vm.startPrank(admin);
        resolver.register(IChainResolver.ChainRegistrationData({label: CHAIN_NAME, chainName: CHAIN_NAME, owner: user1, interoperableAddress: CHAIN_ID}));
        vm.stopPrank();

        // User1 sets a custom text record
        vm.startPrank(user1);

        string memory customTextKey = "profile:bio";
        string memory customTextVal = "gm-chain-resolver";
        resolver.setText(LABEL_HASH, customTextKey, customTextVal);

        vm.stopPrank();

        // Prepare DNS-encoded name for resolve()
        bytes memory name = abi.encodePacked(bytes1(uint8(bytes(CHAIN_NAME).length)), bytes(CHAIN_NAME), bytes1(0x00));

        // Resolve custom text record
        bytes memory textCalldata = abi.encodeWithSelector(resolver.TEXT_SELECTOR(), LABEL_HASH, customTextKey);
        bytes memory textAnswer = resolver.resolve(name, textCalldata);
        string memory resolvedText = abi.decode(textAnswer, (string));
        assertEq(resolvedText, customTextVal, "Should resolve custom text record via resolve");

        console.log("Successfully resolved custom text");
    }
}
