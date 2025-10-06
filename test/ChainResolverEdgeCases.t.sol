// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "../src/ChainResolver.sol";

contract ChainResolverEdgeCasesTest is Test {
    ChainResolver public resolver;

    address public admin = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    address public operator = address(0x4);
    address public zeroAddress = address(0x0);

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
    function test1100_____________________________CHAINRESOLVER_EDGE_CASES________________________() public {}
    function test1200________________________________________________________________________________() public {}

    function test_001____register____________________EmptyChainName() public {
        vm.startPrank(admin);

        // Try to register with empty chain name
        string memory emptyName = "";
        bytes32 emptyLabelHash = keccak256(bytes(emptyName));

        // This should work - empty string is valid
        resolver.register(emptyName, user1, CHAIN_ID);

        // Verify registration
        assertEq(resolver.getOwner(emptyLabelHash), user1, "Empty chain name should be registrable");
        assertEq(resolver.chainId(emptyLabelHash), CHAIN_ID, "Chain ID should be set for empty name");

        vm.stopPrank();

        console.log("Successfully registered empty chain name");
    }

    function test_002____register____________________VeryLongChainName() public {
        vm.startPrank(admin);

        // Try to register with very long chain name
        string memory longName =
            "this_is_a_very_long_chain_name_that_is_much_longer_than_normal_chain_names_used_in_blockchain_ecosystems_and_should_test_the_limits_of_the_registration_system";
        bytes32 longLabelHash = keccak256(bytes(longName));

        // This should work - long names are valid
        resolver.register(longName, user1, CHAIN_ID);

        // Verify registration
        assertEq(resolver.getOwner(longLabelHash), user1, "Long chain name should be registrable");
        assertEq(resolver.chainId(longLabelHash), CHAIN_ID, "Chain ID should be set for long name");

        vm.stopPrank();

        console.log("Successfully registered very long chain name");
    }

    function test_003____register____________________EmptyChainId() public {
        vm.startPrank(admin);

        // Try to register with empty chain ID
        bytes memory emptyChainId = "";

        resolver.register(CHAIN_NAME, user1, emptyChainId);

        // Verify registration
        assertEq(resolver.getOwner(LABEL_HASH), user1, "Owner should be set");
        assertEq(resolver.chainId(LABEL_HASH), emptyChainId, "Empty chain ID should be stored");
        assertEq(resolver.chainName(emptyChainId), CHAIN_NAME, "Chain name should be stored");

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

        resolver.register(CHAIN_NAME, user1, longChainId);

        // Verify registration
        assertEq(resolver.getOwner(LABEL_HASH), user1, "Owner should be set");
        assertEq(resolver.chainId(LABEL_HASH), longChainId, "Long chain ID should be stored");
        assertEq(resolver.chainName(longChainId), CHAIN_NAME, "Chain name should be stored");

        vm.stopPrank();

        console.log("Successfully registered with very long chain ID");
    }

    function test_005____setOperator_________________RemoveOperator() public {
        vm.startPrank(admin);

        // Register a chain
        resolver.register(CHAIN_NAME, user1, CHAIN_ID);

        vm.stopPrank();

        // User1 sets operator
        vm.startPrank(user1);
        resolver.setOperator(operator, true);
        assertTrue(resolver.isAuthorized(LABEL_HASH, operator), "Operator should be authorized");

        // Remove operator
        resolver.setOperator(operator, false);
        assertFalse(resolver.isAuthorized(LABEL_HASH, operator), "Operator should no longer be authorized");

        vm.stopPrank();

        console.log("Successfully removed operator");
    }

    function test_006____resolve_____________________SelectorHandling() public {
        vm.startPrank(admin);

        // Register a chain
        resolver.register(CHAIN_NAME, user1, CHAIN_ID);

        vm.stopPrank();

        // Unknown selector should return empty bytes
        bytes4 maliciousSelector = 0x00000000; // Zero selector

        bytes memory name = abi.encodePacked(bytes1(uint8(bytes(CHAIN_NAME).length)), bytes(CHAIN_NAME), bytes1(0x00));
        bytes memory maliciousData = abi.encodeWithSelector(maliciousSelector, LABEL_HASH);

        // This should return empty bytes, not crash
        bytes memory result = resolver.resolve(name, maliciousData);
        bytes memory emptyResult = abi.encode("");
        assertEq(result, emptyResult, "Should return empty bytes for unknown selector");

        console.log("Successfully handled selector resolution");
    }

    function test_007____supportsInterface___________InterfaceSupport() public view {
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
                string(abi.encodePacked("Interface ", vm.toString(i), " should return expected result"))
            );
        }

        console.log("Successfully handled interface support");
    }
}
