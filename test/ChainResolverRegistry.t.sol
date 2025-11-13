// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/ChainResolver.sol";
import "../src/interfaces/IChainResolver.sol";

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
    bytes public constant CHAIN_ID = hex"00010001010a00";
    bytes32 public constant LABEL_HASH = keccak256(bytes(CHAIN_NAME));

    string public constant CHAIN_NAME_2 = "arbitrum";
    // 7930 format: Version(4) + ChainType(2) + ChainRefLen(1) + ChainRef(1) + AddrLen(1) + Addr(0)
    // Version: 0x00000001, ChainType: 0x0001 (Ethereum), ChainRefLen: 0x01, ChainRef: 0x66 (102), AddrLen: 0x00, Addr: (empty)
    bytes public constant CHAIN_ID_2 = hex"00010001016600";
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

        // Register a chain (label and chain name)
        resolver.register(IChainResolver.ChainData({label: CHAIN_NAME, chainName: CHAIN_NAME, owner: user1, interoperableAddress: CHAIN_ID}));

        // Verify registration
        assertEq(resolver.owner(), admin, "Admin should be contract owner");
        assertEq(resolver.getChainAdmin(LABEL_HASH), user1, "User1 should own the label");
        assertEq(resolver.interoperableAddress(LABEL_HASH), CHAIN_ID, "Chain ID should be set correctly");
        assertEq(resolver.chainName(CHAIN_ID), CHAIN_NAME, "Chain name should be set correctly");

        vm.stopPrank();

        console.log("Successfully registered chain:", CHAIN_NAME);
        console.log("Chain ID:", string(abi.encodePacked(CHAIN_ID)));
    }

    function test_002____register____________________AllowsOverwritingExistingRegistration() public {
        vm.startPrank(admin);

        // Register a chain first time
        resolver.register(IChainResolver.ChainData({label: CHAIN_NAME, chainName: CHAIN_NAME, owner: user1, interoperableAddress: CHAIN_ID}));

        // Try to register the same chain again - should succeed (overwrites existing registration)
        resolver.register(IChainResolver.ChainData({label: CHAIN_NAME, chainName: CHAIN_NAME, owner: user2, interoperableAddress: CHAIN_ID}));

        vm.stopPrank();

        // Verify second registration overwrote the first
        assertEq(resolver.getChainAdmin(LABEL_HASH), user2, "Second owner should overwrite first");

        console.log("Correctly allowed duplicate chain registration (overwrite)");
    }

    function test_003____setLabelOwner_______________TransfersLabelOwnership() public {
        vm.startPrank(admin);

        // Register a chain
        resolver.register(IChainResolver.ChainData({label: CHAIN_NAME, chainName: CHAIN_NAME, owner: user1, interoperableAddress: CHAIN_ID}));

        vm.stopPrank();

        // User1 transfers ownership to user2
        vm.startPrank(user1);
        resolver.setChainAdmin(LABEL_HASH, user2);

        // Verify transfer
        assertEq(resolver.getChainAdmin(LABEL_HASH), user2, "User2 should now own the label");

        vm.stopPrank();

        // User2 should now be the owner
        vm.startPrank(user2);

        // Test that new owner can perform authorized actions
        resolver.setChainAdmin(LABEL_HASH, user1); // Transfer back to user1
        assertEq(resolver.getChainAdmin(LABEL_HASH), user1, "New owner should be able to transfer ownership");

        vm.stopPrank();

        console.log("Successfully transferred label ownership");
    }

    function test_004____batchRegister_______________SuccessfulBatchRegistration() public {
        vm.startPrank(admin);

        // Prepare batch data
        IChainResolver.ChainData[] memory items = new IChainResolver.ChainData[](2);
        items[0] = IChainResolver.ChainData({
            label: "optimism",
            chainName: "optimism",
            owner: user1,
            interoperableAddress: hex"000000010001010a00"
        });
        items[1] = IChainResolver.ChainData({
            label: "arbitrum",
            chainName: "arbitrum",
            owner: user2,
            interoperableAddress: hex"000000010001016600"
        });

        // Register batch
        resolver.batchRegister(items);

        // Verify registrations
        assertEq(resolver.getChainAdmin(keccak256(bytes("optimism"))), user1);
        assertEq(resolver.getChainAdmin(keccak256(bytes("arbitrum"))), user2);
        assertEq(resolver.interoperableAddress(keccak256(bytes("optimism"))), items[0].interoperableAddress);
        assertEq(resolver.interoperableAddress(keccak256(bytes("arbitrum"))), items[1].interoperableAddress);

        vm.stopPrank();

        console.log("Successfully registered batch of chains");
    }

    function test_007____batchRegister_______________EmptyArrays() public {
        vm.startPrank(admin);

        // Prepare empty items
        IChainResolver.ChainData[] memory items0 = new IChainResolver.ChainData[](0);
        // Should not revert with empty arrays
        resolver.batchRegister(items0);

        vm.stopPrank();

        console.log("Successfully handled empty arrays");
    }

    function test_008____batchRegister_______________SingleItemBatch() public {
        vm.startPrank(admin);

        // Prepare single item batch
        IChainResolver.ChainData[] memory one = new IChainResolver.ChainData[](1);
        one[0] = IChainResolver.ChainData({
            label: "optimism",
            chainName: "optimism",
            owner: user1,
            interoperableAddress: hex"000000010001010a00"
        });

        // Register single item
        resolver.batchRegister(one);

        // Verify registration
        assertEq(resolver.getChainAdmin(keccak256(bytes("optimism"))), user1);
        assertEq(resolver.interoperableAddress(keccak256(bytes("optimism"))), one[0].interoperableAddress);

        vm.stopPrank();

        console.log("Successfully registered single item batch");
    }
}
