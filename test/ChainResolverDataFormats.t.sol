// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/ChainResolver.sol";
import "../src/interfaces/IChainResolver.sol";
import {NameCoder} from "@ensdomains/ens-contracts/contracts/utils/NameCoder.sol";

contract ChainResolverDataFormatsTest is Test {
    ChainResolver public resolver;

    address public admin = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    address public attacker = address(0x999);
    address public maliciousContract = address(0x666);

    // Test data - using 7930 chain ID format
    string public constant CHAIN_NAME = "optimism";
    bytes public constant CHAIN_ID = hex"00010001010a00";
    bytes32 public constant LABEL_HASH = keccak256(bytes(CHAIN_NAME));

    function setUp() public {
        vm.startPrank(admin);
        bytes32 parentNamehash = NameCoder.namehash(NameCoder.encode("cid.eth"), 0);
        resolver = new ChainResolver(admin, parentNamehash);
        vm.stopPrank();
    }

    // Identify the file being tested
    function test1000________________________________________________________________________________() public {}
    function test1100_____________________________DATA_FORMATS____________________________________() public {}
    function test1200________________________________________________________________________________() public {}

    function test_001____resolve_____________________ComplexDNSEncodingHandling() public {
        vm.startPrank(admin);

        // Register a chain
        resolver.register(IChainResolver.ChainRegistrationData({label: CHAIN_NAME, chainName: CHAIN_NAME, owner: user1, interoperableAddress: CHAIN_ID}));

        vm.stopPrank();

        // Use a non-standard DNS-encoded name (extra bytes after the label)
        bytes memory maliciousName = abi.encodePacked(
            bytes1(0x08), // Length byte
            "optimism",
            bytes1(0x00), // Null terminator
            bytes1(0x05), // Additional length byte (extra)
            "evil",
            bytes1(0x00)
        );

        bytes memory textData = abi.encodeWithSelector(resolver.TEXT_SELECTOR(), LABEL_HASH, "chain-id");

        // Should resolve despite malicious DNS encoding
        resolver.resolve(maliciousName, textData);
    }

    function test_002____setText_____________________SpecialCharactersAndLongText() public {
        vm.startPrank(admin);

        // Register a chain
        resolver.register(IChainResolver.ChainRegistrationData({label: CHAIN_NAME, chainName: CHAIN_NAME, owner: user1, interoperableAddress: CHAIN_ID}));

        vm.stopPrank();

        // Set and retrieve assorted text values
        vm.startPrank(user1);

        // Test with various special characters and unicode
        string memory specialText = "Test with special chars: !@#$%^&*()_+-=[]{}|;':\",./<>?";
        string memory unicodeText = "Test with unicode: Hello World";
        string memory longText = string(
            abi.encodePacked(
                "Very long text that might cause issues: ",
                "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. ",
                "Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. ",
                "Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur."
            )
        );

        // All should work without issues
        resolver.setText(LABEL_HASH, "special", specialText);
        resolver.setText(LABEL_HASH, "unicode", unicodeText);
        resolver.setText(LABEL_HASH, "long", longText);

        vm.stopPrank();

        // Verify all text was stored correctly
        assertEq(resolver.getText(LABEL_HASH, "special"), specialText, "Special characters should be preserved");
        assertEq(resolver.getText(LABEL_HASH, "unicode"), unicodeText, "Unicode should be preserved");
        assertEq(resolver.getText(LABEL_HASH, "long"), longText, "Long text should be preserved");

        console.log("Successfully handled special characters and long text");
    }

    function test_003____setData_____________________VariousDataPatterns() public {
        vm.startPrank(admin);

        // Register a chain
        resolver.register(IChainResolver.ChainRegistrationData({label: CHAIN_NAME, chainName: CHAIN_NAME, owner: user1, interoperableAddress: CHAIN_ID}));

        vm.stopPrank();

        // Store a variety of data byte patterns
        vm.startPrank(user1);

        // Test with various data patterns
        bytes memory pattern1 = hex"deadbeefcafebabe";
        bytes memory pattern2 = hex"0000000000000000";
        bytes memory pattern3 = hex"ffffffffffffffff";
        bytes memory pattern4 = hex"1234567890abcdef";

        // Complex data encoded with nested types (sanity check)
        bytes memory complexData = abi.encode(
            uint256(123456789),
            address(0x1234567890123456789012345678901234567890),
            string("complex data"),
            bytes32(0x1234567890123456789012345678901234567890123456789012345678901234)
        );

        // All variants should round-trip without issues
        resolver.setData(LABEL_HASH, "pattern1", pattern1);
        resolver.setData(LABEL_HASH, "pattern2", pattern2);
        resolver.setData(LABEL_HASH, "pattern3", pattern3);
        resolver.setData(LABEL_HASH, "pattern4", pattern4);
        resolver.setData(LABEL_HASH, "complex", complexData);

        vm.stopPrank();

        // Verify all data was stored correctly
        assertEq(resolver.getData(LABEL_HASH, "pattern1"), pattern1, "Pattern 1 should be preserved");
        assertEq(resolver.getData(LABEL_HASH, "pattern2"), pattern2, "Pattern 2 should be preserved");
        assertEq(resolver.getData(LABEL_HASH, "pattern3"), pattern3, "Pattern 3 should be preserved");
        assertEq(resolver.getData(LABEL_HASH, "pattern4"), pattern4, "Pattern 4 should be preserved");
        assertEq(resolver.getData(LABEL_HASH, "complex"), complexData, "Complex data should be preserved");

        console.log("Successfully handled various data patterns");
    }

    function test_004____setAddr_____________________VariousAddressTypes() public {
        vm.startPrank(admin);

        // Register a chain
        resolver.register(IChainResolver.ChainRegistrationData({label: CHAIN_NAME, chainName: CHAIN_NAME, owner: user1, interoperableAddress: CHAIN_ID}));

        vm.stopPrank();

        // Set and retrieve addresses across different coin types
        vm.startPrank(user1);

        // Test with various address types
        address[] memory testAddresses = new address[](4);
        testAddresses[0] = address(0x1); // Low address (ETH)
        testAddresses[1] = address(0x1234567890123456789012345678901234567890); // Normal address (Polygon)
        testAddresses[2] = address(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF); // Max address (Arbitrum)
        testAddresses[3] = address(this); // Contract address (Custom)

        uint256[] memory coinTypes = new uint256[](4);
        coinTypes[0] = 60; // ETH
        coinTypes[1] = 137; // Polygon
        coinTypes[2] = 42161; // Arbitrum
        coinTypes[3] = 999999; // Custom coin type

        // EVM examples: ETH via convenience, others via bytes
        resolver.setAddr(LABEL_HASH, 60, abi.encodePacked(testAddresses[0])); // coinType 60
        resolver.setAddr(LABEL_HASH, coinTypes[1], abi.encodePacked(testAddresses[1]));
        resolver.setAddr(LABEL_HASH, coinTypes[2], abi.encodePacked(testAddresses[2]));
        resolver.setAddr(LABEL_HASH, coinTypes[3], abi.encodePacked(testAddresses[3]));

        // Bitcoin (bech32) example - coin type 0 (SLIP-44)
        // Store the bech32 string bytes directly
        bytes memory btcBech32 = bytes("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kygt080");
        resolver.setAddr(LABEL_HASH, 0, btcBech32);

        // Solana (base58) example - coin type 501 (SLIP-44)
        // Store the base58 string bytes directly
        bytes memory solBase58 = bytes("11111111111111111111111111111111");
        resolver.setAddr(LABEL_HASH, 501, solBase58);

        vm.stopPrank();

        // Verify all addresses were set correctly
        // Verify packed 20-byte values for EVM-like addresses
        assertEq(
            resolver.getAddr(LABEL_HASH, 60), abi.encodePacked(testAddresses[0]), "ETH address should be preserved"
        );
        assertEq(
            resolver.getAddr(LABEL_HASH, coinTypes[1]),
            abi.encodePacked(testAddresses[1]),
            "Polygon address should be preserved"
        );
        assertEq(
            resolver.getAddr(LABEL_HASH, coinTypes[2]),
            abi.encodePacked(testAddresses[2]),
            "Arbitrum address should be preserved"
        );
        assertEq(
            resolver.getAddr(LABEL_HASH, coinTypes[3]),
            abi.encodePacked(testAddresses[3]),
            "Custom address should be preserved"
        );

        // Verify Bitcoin and Solana records were stored (raw string bytes)
        assertEq(resolver.getAddr(LABEL_HASH, 0), btcBech32, "Bitcoin bech32 address bytes should be preserved");
        assertEq(resolver.getAddr(LABEL_HASH, 501), solBase58, "Solana base58 address bytes should be preserved");

        console.log("Successfully handled various address types");
    }

    function test_005____setContenthash______________VariousContentHashFormats() public {
        vm.startPrank(admin);

        // Register a chain
        resolver.register(IChainResolver.ChainRegistrationData({label: CHAIN_NAME, chainName: CHAIN_NAME, owner: user1, interoperableAddress: CHAIN_ID}));

        vm.stopPrank();

        // Exercise contenthash with multiple encodings and lengths
        vm.startPrank(user1);

        // Test with various content hash formats
        bytes memory ipfsHash = hex"e301017012201234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";
        bytes memory swarmHash = hex"e401017012201234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";
        bytes memory emptyHash = hex"";
        bytes memory invalidHash = hex"deadbeefcafebabe";
        bytes memory veryLongHash = new bytes(1000);

        // Fill very long hash with pattern
        for (uint256 i = 0; i < veryLongHash.length; i++) {
            veryLongHash[i] = bytes1(uint8(i % 256));
        }

        // All should work without issues
        resolver.setContenthash(LABEL_HASH, ipfsHash);
        assertEq(resolver.getContenthash(LABEL_HASH), ipfsHash, "IPFS hash should be preserved");

        resolver.setContenthash(LABEL_HASH, swarmHash);
        assertEq(resolver.getContenthash(LABEL_HASH), swarmHash, "Swarm hash should be preserved");

        resolver.setContenthash(LABEL_HASH, emptyHash);
        assertEq(resolver.getContenthash(LABEL_HASH), emptyHash, "Empty hash should be preserved");

        resolver.setContenthash(LABEL_HASH, invalidHash);
        assertEq(resolver.getContenthash(LABEL_HASH), invalidHash, "Invalid hash should be preserved");

        resolver.setContenthash(LABEL_HASH, veryLongHash);
        assertEq(resolver.getContenthash(LABEL_HASH), veryLongHash, "Very long hash should be preserved");

        vm.stopPrank();

        console.log("Successfully handled various content hash formats");
    }

    function test_006____register____________________MultiRegistrationVariousInputs() public {
        vm.startPrank(admin);

        // Registration edge cases (names/owners/IDs of varying shapes)
        string[] memory testNames = new string[](5);
        testNames[0] = ""; // Empty name
        testNames[1] = "a"; // Single character
        testNames[2] = "test-chain_123.eth"; // Special characters
        testNames[3] =
            "VERY_LONG_CHAIN_NAME_THAT_IS_MUCH_LONGER_THAN_NORMAL_CHAIN_NAMES_USED_IN_BLOCKCHAIN_ECOSYSTEMS_AND_SHOULD_TEST_THE_LIMITS_OF_THE_REGISTRATION_SYSTEM_AND_GAS_CONSUMPTION_AND_EDGE_CASES"; // Very long
        testNames[4] = "optimism"; // Normal name

        address[] memory testOwners = new address[](5);
        testOwners[0] = address(0x0); // Zero address
        testOwners[1] = address(0x1); // Low address
        testOwners[2] = address(0x1234567890123456789012345678901234567890); // Normal address
        testOwners[3] = address(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF); // Max address
        testOwners[4] = address(this); // Contract address

        bytes[] memory testChainIds = new bytes[](5);
        testChainIds[0] = hex""; // Empty chain ID
        testChainIds[1] = hex"00010001010a00"; // Normal chain ID
        testChainIds[2] = hex"00010001016600"; // Another normal chain ID
        testChainIds[3] = new bytes(1000); // Very long chain ID
        testChainIds[4] = hex"00010001010a00"; // Duplicate chain ID

        // Fill very long chain ID
        for (uint256 i = 0; i < testChainIds[3].length; i++) {
            testChainIds[3][i] = bytes1(uint8(i % 256));
        }

        // Register all test cases
        for (uint256 i = 0; i < testNames.length; i++) {
            bytes32 labelHash = keccak256(bytes(testNames[i]));
            resolver.register(IChainResolver.ChainRegistrationData({label: testNames[i], chainName: testNames[i], owner: testOwners[i], interoperableAddress: testChainIds[i]}));

            // Verify registration
            assertEq(
                resolver.getChainAdmin(labelHash),
                testOwners[i],
                string(abi.encodePacked("Owner ", vm.toString(i), " should be set correctly"))
            );
            assertEq(
                resolver.interoperableAddress(labelHash),
                testChainIds[i],
                string(abi.encodePacked("Chain ID ", vm.toString(i), " should be set correctly"))
            );
        }

        vm.stopPrank();

        console.log("Successfully handled batch registration various inputs");
    }

    function test_007____setData_____________________LargeDataHandling() public {
        vm.startPrank(admin);

        // Register a chain
        resolver.register(IChainResolver.ChainRegistrationData({label: CHAIN_NAME, chainName: CHAIN_NAME, owner: user1, interoperableAddress: CHAIN_ID}));

        vm.stopPrank();

        // Test with very large data record
        vm.startPrank(user1);

        // Create large data (100KB - more reasonable for testing)
        bytes memory largeData = new bytes(1024 * 100);
        for (uint256 i = 0; i < largeData.length; i++) {
            largeData[i] = bytes1(uint8(i % 256));
        }

        // This should work without overflow
        resolver.setData(LABEL_HASH, "large_data", largeData);

        // Verify data was stored correctly
        bytes memory retrievedData = resolver.getData(LABEL_HASH, "large_data");
        assertEq(retrievedData.length, largeData.length, "Large data should be stored correctly");

        vm.stopPrank();

        console.log("Successfully handled large data");
    }

    // Invalid DNS encoding test moved to EdgeCases suite
}
