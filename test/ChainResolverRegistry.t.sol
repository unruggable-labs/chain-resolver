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
            resolver.getChainAdmin(TEST_LABEL),
            user1,
            "User1 should own the label"
        );
        assertEq(
            resolver.interoperableAddress(TEST_LABEL),
            TEST_INTEROPERABLE_ADDRESS,
            "Chain ID should be set correctly"
        );
        assertEq(
            resolver.chainName(TEST_LABEL),
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
            resolver.getChainAdmin(TEST_LABEL),
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
            resolver.getChainAdmin(TEST_LABEL),
            user2,
            "User2 should now own the label"
        );

        vm.stopPrank();

        // User2 should now be the owner
        vm.startPrank(user2);

        // Test that new owner can perform authorized actions
        resolver.setChainAdmin(TEST_LABELHASH, user1); // Transfer back to user1
        assertEq(
            resolver.getChainAdmin(TEST_LABEL),
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
        assertEq(resolver.getChainAdmin("optimism"), user1);
        assertEq(resolver.getChainAdmin("arbitrum"), user2);
        assertEq(
            resolver.interoperableAddress("optimism"),
            items[0].interoperableAddress
        );
        assertEq(
            resolver.interoperableAddress("arbitrum"),
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
        assertEq(resolver.getChainAdmin("optimism"), user1);
        assertEq(
            resolver.interoperableAddress("optimism"),
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
        IChainResolver.CanonicalLabelInfo memory info = resolver.getCanonicalLabel(aliasLabel);
        assertEq(
            info.labelhash,
            TEST_LABELHASH,
            "Alias should point to canonical labelhash"
        );

        // Verify alias resolves to same data as canonical
        assertEq(
            resolver.interoperableAddress(aliasLabel),
            TEST_INTEROPERABLE_ADDRESS,
            "Alias should resolve to same interoperable address"
        );
        assertEq(
            resolver.getChainAdmin(aliasLabel),
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
        vm.expectRevert(IChainResolver.CanonicalNotRegistered.selector);
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
        vm.expectRevert(IChainResolver.CannotAliasToAlias.selector);
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
        IChainResolver.CanonicalLabelInfo memory info1 = resolver.getCanonicalLabel("op");
        assertEq(
            info1.labelhash,
            TEST_LABELHASH,
            "First alias should point to optimism"
        );
        IChainResolver.CanonicalLabelInfo memory info2 = resolver.getCanonicalLabel("arb");
        assertEq(
            info2.labelhash,
            LABELHASH_2,
            "Second alias should point to arbitrum"
        );

        // Verify aliases resolve correctly
        assertEq(
            resolver.interoperableAddress("op"),
            TEST_INTEROPERABLE_ADDRESS,
            "op alias should resolve to optimism interoperable address"
        );
        assertEq(
            resolver.interoperableAddress("arb"),
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
        vm.expectRevert(IChainResolver.ArrayLengthMismatch.selector);
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

    //////
    /// LABEL STRING GETTERS TESTS
    //////

    function test_015____chainName_____________________LabelStringGetter() public {
        vm.startPrank(admin);
        registerTestChain();
        vm.stopPrank();

        // Test chainName with label string (new overload)
        string memory resolvedName = resolver.chainName(TEST_LABEL);
        assertEq(
            resolvedName,
            TEST_CHAIN_NAME,
            "chainName(label) should return correct chain name"
        );

        console.log("Successfully retrieved chain name using label string");
    }

    function test_016____chainName_____________________LabelStringGetterForUnregistered() public {
        vm.startPrank(admin);
        registerTestChain();
        vm.stopPrank();

        // Test chainName with unregistered label string
        string memory unregisteredLabel = "unregistered";
        string memory resolvedName = resolver.chainName(unregisteredLabel);
        assertEq(
            resolvedName,
            "",
            "chainName(label) should return empty string for unregistered label"
        );

        console.log("Successfully returned empty string for unregistered label");
    }

    function test_017____interoperableAddress__________LabelStringGetter() public {
        vm.startPrank(admin);
        registerTestChain();
        vm.stopPrank();

        // Test interoperableAddress with label string (new overload)
        bytes memory resolvedAddress = resolver.interoperableAddress(TEST_LABEL);
        assertEq(
            resolvedAddress,
            TEST_INTEROPERABLE_ADDRESS,
            "interoperableAddress(label) should return correct interoperable address"
        );

        console.log("Successfully retrieved interoperable address using label string");
    }

    function test_018____interoperableAddress__________LabelStringGetterForUnregistered() public {
        vm.startPrank(admin);
        registerTestChain();
        vm.stopPrank();

        // Test interoperableAddress with unregistered label string
        string memory unregisteredLabel = "unregistered";
        bytes memory resolvedAddress = resolver.interoperableAddress(unregisteredLabel);
        assertEq(
            resolvedAddress.length,
            0,
            "interoperableAddress(label) should return empty bytes for unregistered label"
        );

        console.log("Successfully returned empty bytes for unregistered label");
    }

    function test_019____chainName_____________________LabelStringGetterForAlias() public {
        vm.startPrank(admin);
        registerTestChain();

        // Register an alias
        string memory aliasLabel = "op";
        resolver.registerAlias(aliasLabel, TEST_LABELHASH);
        vm.stopPrank();

        // Test chainName with alias label string
        string memory resolvedName = resolver.chainName(aliasLabel);
        assertEq(
            resolvedName,
            TEST_CHAIN_NAME,
            "chainName(alias) should resolve to canonical chain name"
        );

        // Verify it matches the canonical
        string memory canonicalName = resolver.chainName(TEST_LABEL);
        assertEq(
            resolvedName,
            canonicalName,
            "Alias should resolve to same chain name as canonical"
        );

        console.log("Successfully retrieved chain name using alias label string");
    }

    function test_020____interoperableAddress__________LabelStringGetterForAlias() public {
        vm.startPrank(admin);
        registerTestChain();

        // Register an alias
        string memory aliasLabel = "op";
        resolver.registerAlias(aliasLabel, TEST_LABELHASH);
        vm.stopPrank();

        // Test interoperableAddress with alias label string
        bytes memory resolvedAddress = resolver.interoperableAddress(aliasLabel);
        assertEq(
            resolvedAddress,
            TEST_INTEROPERABLE_ADDRESS,
            "interoperableAddress(alias) should resolve to canonical interoperable address"
        );

        // Verify it matches the canonical
        bytes memory canonicalAddress = resolver.interoperableAddress(TEST_LABEL);
        assertEq(
            resolvedAddress,
            canonicalAddress,
            "Alias should resolve to same interoperable address as canonical"
        );

        console.log("Successfully retrieved interoperable address using alias label string");
    }

    function test_021____chainName_____________________LabelStringGetterForBatchRegistered() public {
        vm.startPrank(admin);

        // Register multiple chains via batch
        IChainResolver.ChainRegistrationData[]
            memory items = new IChainResolver.ChainRegistrationData[](2);
        items[0] = IChainResolver.ChainRegistrationData({
            label: "optimism",
            chainName: "Optimism",
            owner: user1,
            interoperableAddress: hex"000000010001010a00"
        });
        items[1] = IChainResolver.ChainRegistrationData({
            label: "arbitrum",
            chainName: "Arbitrum",
            owner: user2,
            interoperableAddress: hex"000000010001016600"
        });

        resolver.batchRegister(items);
        vm.stopPrank();

        // Test both chains with label string getters
        string memory optLabel = "optimism";
        string memory arbLabel = "arbitrum";
        assertEq(resolver.chainName(optLabel), "Optimism");
        assertEq(resolver.chainName(arbLabel), "Arbitrum");

        // Test interoperable addresses
        assertEq(
            resolver.interoperableAddress(optLabel),
            hex"000000010001010a00"
        );
        assertEq(
            resolver.interoperableAddress(arbLabel),
            hex"000000010001016600"
        );

        console.log("Successfully retrieved data for batch registered chains using label strings");
    }
}
