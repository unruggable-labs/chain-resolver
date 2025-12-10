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

    function test_009____registerAlias_________________SuccessfulAliasRegistration()
        public
    {
        vm.startPrank(admin);

        // First register the canonical chain
        registerTestChain();

        // Register an alias "op" pointing to "optimism"
        string memory aliasLabel = "op";
        resolver.registerAlias(aliasLabel, TEST_LABELHASH);

        // Verify alias was registered
        bytes32 aliasHash = keccak256(bytes(aliasLabel));
        assertEq(
            resolver.getCanonicalLabelhash(aliasHash),
            TEST_LABELHASH,
            "Alias should point to canonical labelhash"
        );

        // Verify alias resolves to same data as canonical
        assertEq(
            resolver.interoperableAddress(aliasHash),
            TEST_INTEROPERABLE_ADDRESS,
            "Alias should resolve to same interoperable address"
        );
        assertEq(
            resolver.getChainAdmin(aliasHash),
            user1,
            "Alias should resolve to same chain admin"
        );

        vm.stopPrank();

        console.log("Successfully registered alias");
    }

    function test_010____registerAlias_________________RevertsWhenCanonicalNotRegistered()
        public
    {
        vm.startPrank(admin);

        // Try to register alias without registering canonical first
        bytes32 unregisteredLabelhash = keccak256(bytes("unregistered"));
        vm.expectRevert("Canonical not registered");
        resolver.registerAlias("alias", unregisteredLabelhash);

        vm.stopPrank();

        console.log("Correctly reverted when canonical not registered");
    }

    function test_011____registerAlias_________________RevertsWhenAliasingToAlias()
        public
    {
        vm.startPrank(admin);

        // Register canonical chain
        registerTestChain();

        // Register first alias
        resolver.registerAlias("op", TEST_LABELHASH);

        // Try to alias to the alias - should fail
        bytes32 aliasHash = keccak256(bytes("op"));
        vm.expectRevert("Cannot alias to an alias");
        resolver.registerAlias("o", aliasHash);

        vm.stopPrank();

        console.log("Correctly reverted when aliasing to an alias");
    }

    function test_012____batchRegisterAlias____________SuccessfulBatchAliasRegistration()
        public
    {
        vm.startPrank(admin);

        // Register two canonical chains
        registerTestChain(); // optimism
        registerChain(CHAIN_LABEL_2, "Arbitrum", user2, CHAIN_ID_2); // arbitrum

        // Prepare batch alias data
        string[] memory aliases = new string[](2);
        bytes32[] memory canonicals = new bytes32[](2);
        aliases[0] = "op";
        aliases[1] = "arb";
        canonicals[0] = TEST_LABELHASH; // optimism
        canonicals[1] = LABELHASH_2; // arbitrum

        // Register batch aliases
        resolver.batchRegisterAlias(aliases, canonicals);

        // Verify aliases were registered
        assertEq(
            resolver.getCanonicalLabelhash(keccak256(bytes("op"))),
            TEST_LABELHASH,
            "First alias should point to optimism"
        );
        assertEq(
            resolver.getCanonicalLabelhash(keccak256(bytes("arb"))),
            LABELHASH_2,
            "Second alias should point to arbitrum"
        );

        // Verify aliases resolve correctly
        assertEq(
            resolver.interoperableAddress(keccak256(bytes("op"))),
            TEST_INTEROPERABLE_ADDRESS,
            "op alias should resolve to optimism interoperable address"
        );
        assertEq(
            resolver.interoperableAddress(keccak256(bytes("arb"))),
            CHAIN_ID_2,
            "arb alias should resolve to arbitrum interoperable address"
        );

        vm.stopPrank();

        console.log("Successfully registered batch of aliases");
    }

    function test_013____batchRegisterAlias____________RevertsOnArrayLengthMismatch()
        public
    {
        vm.startPrank(admin);

        registerTestChain();

        // Prepare mismatched arrays
        string[] memory aliases = new string[](2);
        bytes32[] memory canonicals = new bytes32[](1);
        aliases[0] = "op";
        aliases[1] = "o";
        canonicals[0] = TEST_LABELHASH;

        // Should revert due to length mismatch
        vm.expectRevert("Array length mismatch");
        resolver.batchRegisterAlias(aliases, canonicals);

        vm.stopPrank();

        console.log("Correctly reverted on array length mismatch");
    }

    function test_014____batchRegisterAlias____________EmptyArrays() public {
        vm.startPrank(admin);

        // Prepare empty arrays
        string[] memory aliases = new string[](0);
        bytes32[] memory canonicals = new bytes32[](0);

        // Should not revert with empty arrays
        resolver.batchRegisterAlias(aliases, canonicals);

        vm.stopPrank();

        console.log("Successfully handled empty alias arrays");
    }
}
