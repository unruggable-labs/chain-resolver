// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "../src/ChainResolver.sol";

contract ChainResolverDataFormatsTest is Test {
    ChainResolver public resolver;

    address public admin = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    address public attacker = address(0x999);
    address public maliciousContract = address(0x666);

    // Test data - using 7930 chain ID format
    string public constant CHAIN_NAME = "optimism";
    bytes public constant CHAIN_ID = hex"000000010001010a00";
    bytes32 public constant LABEL_HASH = keccak256(bytes(CHAIN_NAME));

    function setUp() public {
        vm.startPrank(admin);
        resolver = new ChainResolver(admin);
        vm.stopPrank();
    }

    // Identify the file being tested
    function test1000________________________________________________________________________________() public {}
    function test1100_____________________________DATA_FORMATS____________________________________() public {}
    function test1200________________________________________________________________________________() public {}

    function test_001____resolve_____________________ComplexDNSEncodingHandling() public {
        vm.startPrank(admin);

        // Register a chain
        resolver.register(CHAIN_NAME, user1, CHAIN_ID);

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

        // This should still resolve the chain-id correctly despite extra/odd DNS bytes
        bytes memory result = resolver.resolve(maliciousName, textData);
        bytes memory expectedChainId = abi.encode("000000010001010a00"); // Hex string of CHAIN_ID
        assertEq(result, expectedChainId, "Should resolve chain-id correctly despite extra DNS bytes");

        console.log("Successfully handled complex DNS encoding");
    }

    function test_002____setText_____________________SpecialCharactersAndLongText() public {
        vm.startPrank(admin);

        // Register a chain
        resolver.register(CHAIN_NAME, user1, CHAIN_ID);

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
        resolver.register(CHAIN_NAME, user1, CHAIN_ID);

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
        resolver.register(CHAIN_NAME, user1, CHAIN_ID);

        vm.stopPrank();

        // Set and retrieve addresses across different coin types
        vm.startPrank(user1);

        // Test with various address types
        address[] memory testAddresses = new address[](5);
        testAddresses[0] = address(0x0); // Zero address
        testAddresses[1] = address(0x1); // Low address
        testAddresses[2] = address(0x1234567890123456789012345678901234567890); // Normal address
        testAddresses[3] = address(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF); // Max address
        testAddresses[4] = address(this); // Contract address

        uint256[] memory coinTypes = new uint256[](5);
        coinTypes[0] = 0;
        coinTypes[1] = 60; // ETH
        coinTypes[2] = 137; // Polygon
        coinTypes[3] = 42161; // Arbitrum
        coinTypes[4] = 999999; // Custom coin type

        // Set all addresses
        for (uint256 i = 0; i < testAddresses.length; i++) {
            resolver.setAddr(LABEL_HASH, coinTypes[i], testAddresses[i]);
        }

        vm.stopPrank();

        // Verify all addresses were set correctly
        for (uint256 i = 0; i < testAddresses.length; i++) {
            assertEq(
                resolver.getAddr(LABEL_HASH, coinTypes[i]),
                testAddresses[i],
                string(abi.encodePacked("Address ", vm.toString(i), " should be preserved"))
            );
        }

        console.log("Successfully handled various address types");
    }

    function test_005____setContenthash______________VariousContentHashFormats() public {
        vm.startPrank(admin);

        // Register a chain
        resolver.register(CHAIN_NAME, user1, CHAIN_ID);

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

    function test_006____setOperator_________________OperatorManagement() public {
        vm.startPrank(admin);

        // Register a chain
        resolver.register(CHAIN_NAME, user1, CHAIN_ID);

        vm.stopPrank();

        // Operator management scenarios (add/remove per-owner operators)
        vm.startPrank(user1);

        // Set multiple operators
        resolver.setOperator(user2, true);
        resolver.setOperator(attacker, true);
        resolver.setOperator(address(this), true);

        // Verify all are authorized
        assertTrue(resolver.isAuthorized(LABEL_HASH, user2), "User2 should be authorized");
        assertTrue(resolver.isAuthorized(LABEL_HASH, attacker), "Attacker should be authorized");
        assertTrue(resolver.isAuthorized(LABEL_HASH, address(this)), "Contract should be authorized");

        // Test operator interactions
        vm.stopPrank();
        vm.startPrank(user2);

        // User2 tries to remove attacker (this works because setOperator is per-caller)
        resolver.setOperator(attacker, false);

        // User2 tries to set new operator (this works because setOperator is per-caller)
        resolver.setOperator(address(0x777), true);
        // But this doesn't make address(0x777) authorized for the label hash
        assertFalse(
            resolver.isAuthorized(LABEL_HASH, address(0x777)), "New operator should not be authorized for label hash"
        );

        vm.stopPrank();

        console.log("Successfully handled operator management");
    }

    function test_007____chainName___________________ReverseLookupHandling() public {
        vm.startPrank(admin);

        // Register multiple chains with complex relationships
        resolver.register(CHAIN_NAME, user1, CHAIN_ID);
        resolver.register("arbitrum", user2, hex"000000010001016600");
        resolver.register("polygon", user1, hex"000000010001013700");

        vm.stopPrank();

        // Reverse lookup scenarios across multiple chain IDs
        // Test with various chain IDs
        bytes[] memory testChainIds = new bytes[](4);
        testChainIds[0] = CHAIN_ID;
        testChainIds[1] = hex"000000010001016600";
        testChainIds[2] = hex"000000010001013700";
        testChainIds[3] = hex"000000010001019999"; // Non-existent

        string[] memory expectedNames = new string[](4);
        expectedNames[0] = CHAIN_NAME;
        expectedNames[1] = "arbitrum";
        expectedNames[2] = "polygon";
        expectedNames[3] = "";

        for (uint256 i = 0; i < testChainIds.length; i++) {
            string memory result = resolver.chainName(testChainIds[i]);
            assertEq(
                result,
                expectedNames[i],
                string(abi.encodePacked("Chain name ", vm.toString(i), " should match expected"))
            );
        }

        console.log("Successfully handled reverse lookup");
    }

    function test_008____register____________________LargeBatchRegistration() public {
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
        testChainIds[1] = hex"000000010001010a00"; // Normal chain ID
        testChainIds[2] = hex"000000010001016600"; // Another normal chain ID
        testChainIds[3] = new bytes(1000); // Very long chain ID
        testChainIds[4] = hex"000000010001010a00"; // Duplicate chain ID

        // Fill very long chain ID
        for (uint256 i = 0; i < testChainIds[3].length; i++) {
            testChainIds[3][i] = bytes1(uint8(i % 256));
        }

        // Register all test cases
        for (uint256 i = 0; i < testNames.length; i++) {
            bytes32 labelHash = keccak256(bytes(testNames[i]));
            resolver.register(testNames[i], testOwners[i], testChainIds[i]);

            // Verify registration
            assertEq(
                resolver.getOwner(labelHash),
                testOwners[i],
                string(abi.encodePacked("Owner ", vm.toString(i), " should be set correctly"))
            );
            assertEq(
                resolver.chainId(labelHash),
                testChainIds[i],
                string(abi.encodePacked("Chain ID ", vm.toString(i), " should be set correctly"))
            );
        }

        vm.stopPrank();

        console.log("Successfully handled large batch registration");
    }

    function test_009____setData_____________________LargeDataHandling() public {
        vm.startPrank(admin);

        // Register a chain
        resolver.register(CHAIN_NAME, user1, CHAIN_ID);

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

    function test_010____register____________________GasLimitHandling() public {
        vm.startPrank(admin);

        // Test with very long chain name that might cause gas issues
        string memory veryLongName =
            "this_is_a_very_long_chain_name_that_is_much_longer_than_normal_chain_names_used_in_blockchain_ecosystems_and_should_test_the_limits_of_the_registration_system_and_gas_consumption";

        // This should work without hitting gas limits
        resolver.register(veryLongName, user1, CHAIN_ID);

        bytes32 longLabelHash = keccak256(bytes(veryLongName));
        assertEq(resolver.getOwner(longLabelHash), user1, "Long name registration should work");

        vm.stopPrank();

        console.log("Successfully handled gas limit edge cases");
    }
}
