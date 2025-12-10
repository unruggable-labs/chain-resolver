// SPDX-License-Identifier: MIT

// Tests for registering chains. Both single chains, and batch registration.

pragma solidity ^0.8.25;

import "./ChainResolverTestBase.sol";

contract ChainResolverRegistryTest is ChainResolverTestBase {
    address public operator = address(0x4);

    // Second chain for multi-chain tests
    string public constant CHAIN_LABEL_2 = "arbitrum";
    bytes public constant CHAIN_ID_2 = hex"00010001016600";
    bytes32 public constant LABELHASH_2 = keccak256(bytes(CHAIN_LABEL_2));

    function setUp() public {
        vm.startPrank(admin);
        resolver = deployResolver(admin);
        vm.stopPrank();
    }

    function test_001____register____________________SuccessfulChainRegistration()
        public
    {
        vm.startPrank(admin);
        registerTestChain();

        // Verify registration
        assertEq(resolver.owner(), admin, "Admin should be contract owner");
        assertEq(
            resolver.getChainAdmin(TEST_LABELHASH),
            user1,
            "User1 should own the label"
        );
        assertEq(
            resolver.interoperableAddress(TEST_LABELHASH),
            TEST_INTEROPERABLE_ADDRESS,
            "Chain ID should be set correctly"
        );
        assertEq(
            resolver.chainName(TEST_INTEROPERABLE_ADDRESS),
            TEST_CHAIN_NAME,
            "Chain name should be set correctly"
        );

        vm.stopPrank();

        console.log("Successfully registered chain:", TEST_LABEL);
    }

    function test_002____register____________________AllowsOverwritingExistingRegistration()
        public
    {
        vm.startPrank(admin);

        // Register a chain first time
        registerTestChain();

        // Try to register the same chain again - should succeed (overwrites existing registration)
        registerTestChainWithOwner(user2);

        vm.stopPrank();

        // Verify second registration overwrote the first
        assertEq(
            resolver.getChainAdmin(TEST_LABELHASH),
            user2,
            "Second owner should overwrite first"
        );

        console.log(
            "Correctly allowed duplicate chain registration (overwrite)"
        );
    }

    function test_003____setChainAdmin_______________TransfersLabelOwnership()
        public
    {
        vm.startPrank(admin);
        registerTestChain();
        vm.stopPrank();

        // User1 transfers ownership to user2
        vm.startPrank(user1);
        resolver.setChainAdmin(TEST_LABELHASH, user2);

        // Verify transfer
        assertEq(
            resolver.getChainAdmin(TEST_LABELHASH),
            user2,
            "User2 should now own the label"
        );

        vm.stopPrank();

        // User2 should now be the owner
        vm.startPrank(user2);

        // Test that new owner can perform authorized actions
        resolver.setChainAdmin(TEST_LABELHASH, user1); // Transfer back to user1
        assertEq(
            resolver.getChainAdmin(TEST_LABELHASH),
            user1,
            "New owner should be able to transfer ownership"
        );

        vm.stopPrank();

        console.log("Successfully transferred label ownership");
    }

    function test_004____batchRegister_______________SuccessfulBatchRegistration()
        public
    {
        vm.startPrank(admin);

        // Prepare batch data
        IChainResolver.ChainRegistrationData[]
            memory items = new IChainResolver.ChainRegistrationData[](2);
        items[0] = IChainResolver.ChainRegistrationData({
            label: "optimism",
            chainName: "optimism",
            owner: user1,
            interoperableAddress: hex"000000010001010a00"
        });
        items[1] = IChainResolver.ChainRegistrationData({
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
        assertEq(
            resolver.interoperableAddress(keccak256(bytes("optimism"))),
            items[0].interoperableAddress
        );
        assertEq(
            resolver.interoperableAddress(keccak256(bytes("arbitrum"))),
            items[1].interoperableAddress
        );

        vm.stopPrank();

        console.log("Successfully registered batch of chains");
    }

    function test_007____batchRegister_______________EmptyArrays() public {
        vm.startPrank(admin);

        // Prepare empty items
        IChainResolver.ChainRegistrationData[]
            memory items0 = new IChainResolver.ChainRegistrationData[](0);
        // Should not revert with empty arrays
        resolver.batchRegister(items0);

        vm.stopPrank();

        console.log("Successfully handled empty arrays");
    }

    function test_008____batchRegister_______________SingleItemBatch() public {
        vm.startPrank(admin);

        // Prepare single item batch
        IChainResolver.ChainRegistrationData[]
            memory one = new IChainResolver.ChainRegistrationData[](1);
        one[0] = IChainResolver.ChainRegistrationData({
            label: "optimism",
            chainName: "optimism",
            owner: user1,
            interoperableAddress: hex"000000010001010a00"
        });

        // Register single item
        resolver.batchRegister(one);

        // Verify registration
        assertEq(resolver.getChainAdmin(keccak256(bytes("optimism"))), user1);
        assertEq(
            resolver.interoperableAddress(keccak256(bytes("optimism"))),
            one[0].interoperableAddress
        );

        vm.stopPrank();

        console.log("Successfully registered single item batch");
    }
}
