// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "../src/ChainResolver.sol";

contract ChainResolverRegistryTest is Test {
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

    string public constant CHAIN_NAME_2 = "arbitrum";
    // 7930 format: Version(4) + ChainType(2) + ChainRefLen(1) + ChainRef(1) + AddrLen(1) + Addr(0)
    // Version: 0x00000001, ChainType: 0x0001 (Ethereum), ChainRefLen: 0x01, ChainRef: 0x66 (102), AddrLen: 0x00, Addr: (empty)
    bytes public constant CHAIN_ID_2 = hex"000000010001016600";
    bytes32 public constant LABEL_HASH_2 = keccak256(bytes(CHAIN_NAME_2));

    function setUp() public {
        vm.startPrank(admin);
        resolver = new ChainResolver(admin);
        vm.stopPrank();
    }

    // Identify the file being tested
    function test1000________________________________________________________________________________() public {}
    function test1100_______________________________REGISTRY_________________________________________() public {}
    function test1200________________________________________________________________________________() public {}

    function test_001____register____________________SuccessfulChainRegistration() public {
        vm.startPrank(admin);

        // Register a chain
        resolver.register(CHAIN_NAME, user1, CHAIN_ID);

        // Verify registration
        assertEq(resolver.owner(), admin, "Admin should be contract owner");
        assertEq(resolver.getOwner(LABEL_HASH), user1, "User1 should own the label");
        assertEq(resolver.chainId(LABEL_HASH), CHAIN_ID, "Chain ID should be set correctly");
        assertEq(resolver.chainName(CHAIN_ID), CHAIN_NAME, "Chain name should be set correctly");

        vm.stopPrank();

        console.log("Successfully registered chain:", CHAIN_NAME);
        console.log("Chain ID:", string(abi.encodePacked(CHAIN_ID)));
    }

    function test_002____register____________________AllowsOverwritingExistingRegistration() public {
        vm.startPrank(admin);

        // Register a chain first time
        resolver.register(CHAIN_NAME, user1, CHAIN_ID);

        // Try to register the same chain again - should succeed (overwrites existing registration)
        resolver.register(CHAIN_NAME, user2, CHAIN_ID);

        vm.stopPrank();

        // Verify second registration overwrote the first
        assertEq(resolver.getOwner(LABEL_HASH), user2, "Second owner should overwrite first");

        console.log("Correctly allowed duplicate chain registration (overwrite)");
    }

    function test_003____setOperator_________________EnablesOperatorManagement() public {
        vm.startPrank(admin);

        // Register a chain
        resolver.register(CHAIN_NAME, user1, CHAIN_ID);

        vm.stopPrank();

        // User1 sets operator
        vm.startPrank(user1);
        resolver.setOperator(operator, true);
        assertTrue(resolver.isAuthorized(LABEL_HASH, operator), "Operator should be authorized");

        vm.stopPrank();

        // Operator should now be able to perform authorized actions
        vm.startPrank(operator);

        // Test that operator can set label owner (authorized action)
        resolver.setLabelOwner(LABEL_HASH, user2);
        assertEq(resolver.getOwner(LABEL_HASH), user2, "Operator should be able to transfer ownership");

        vm.stopPrank();

        console.log("Successfully demonstrated operator authorization");
    }

    function test_004____setLabelOwner_______________TransfersLabelOwnership() public {
        vm.startPrank(admin);

        // Register a chain
        resolver.register(CHAIN_NAME, user1, CHAIN_ID);

        vm.stopPrank();

        // User1 transfers ownership to user2
        vm.startPrank(user1);
        resolver.setLabelOwner(LABEL_HASH, user2);

        // Verify transfer
        assertEq(resolver.getOwner(LABEL_HASH), user2, "User2 should now own the label");

        vm.stopPrank();

        // User2 should now be the owner
        vm.startPrank(user2);

        // Test that new owner can perform authorized actions
        resolver.setLabelOwner(LABEL_HASH, user1); // Transfer back to user1
        assertEq(resolver.getOwner(LABEL_HASH), user1, "New owner should be able to transfer ownership");

        vm.stopPrank();

        console.log("Successfully transferred label ownership");
    }
}
