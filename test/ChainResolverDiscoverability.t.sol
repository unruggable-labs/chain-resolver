// SPDX-License-Identifier: MIT

// Tests for the enumeration of chains in the ChainResolver contract.
// For chain discoverability.

pragma solidity ^0.8.25;

import "./ChainResolverTestBase.sol";

contract ChainResolverDiscoverabilityTest is ChainResolverTestBase {
    // Second chain for multi-chain tests
    bytes public constant ARB_INTEROPERABLE_ADDRESS = hex"00010001016600";

    function setUp() public {
        vm.startPrank(admin);
        resolver = deployResolver(admin);
        vm.stopPrank();
    }

    function test_001____enumeration_____________________SingleInsertAndUpdate()
        public
    {
        vm.startPrank(admin);
        // First insert
        registerTestChain();
        assertEq(
            resolver.chainCount(),
            1,
            "chainCount should be 1 after first insert"
        );
        // Verify index 0
        (string memory lbl0, string memory name0, bytes memory i0) = resolver
            .getChainAtIndex(0);
        assertEq(lbl0, TEST_LABEL);
        assertEq(name0, TEST_CHAIN_NAME);
        // Update same label with new owner + name
        registerChain(TEST_LABEL, "OP Mainnet", user2, TEST_INTEROPERABLE_ADDRESS);
        assertEq(
            resolver.chainCount(),
            1,
            "chainCount should not increment on update"
        );
        (string memory lbl1, string memory name1, bytes memory i1) = resolver
            .getChainAtIndex(0);
        assertEq(lbl1, TEST_LABEL);
        assertEq(name1, "OP Mainnet");
        vm.stopPrank();
    }

    function test_002____enumeration_____________________BatchInsert() public {
        vm.startPrank(admin);

        // Build batch structs
        IChainResolver.ChainRegistrationData[]
            memory items = new IChainResolver.ChainRegistrationData[](2);
        items[0] = IChainResolver.ChainRegistrationData({
            label: TEST_LABEL,
            chainName: TEST_CHAIN_NAME,
            owner: user1,
            interoperableAddress: TEST_INTEROPERABLE_ADDRESS
        });
        items[1] = IChainResolver.ChainRegistrationData({
            label: "arbitrum",
            chainName: "Arbitrum",
            owner: user2,
            interoperableAddress: ARB_INTEROPERABLE_ADDRESS
        });

        // Register in a single batch
        resolver.batchRegister(items);

        // chainCount reflects unique labels
        assertEq(
            resolver.chainCount(),
            2,
            "chainCount should equal number of unique labels"
        );

        // Verify enumeration order matches insertion order
        (string memory l0, string memory n0, bytes memory i0) = resolver
            .getChainAtIndex(0);
        (string memory l1, string memory n1, bytes memory i1) = resolver
            .getChainAtIndex(1);
        assertEq(l0, TEST_LABEL);
        assertEq(n0, TEST_CHAIN_NAME);
        assertEq(l1, "arbitrum");
        assertEq(n1, "Arbitrum");

        vm.stopPrank();
    }

    function test_003____enumeration_____________________OutOfBoundsReverts()
        public
    {
        vm.startPrank(admin);
        registerTestChain();
        vm.stopPrank();

        // Index 1 is out-of-bounds; expect revert
        vm.expectRevert(IChainResolver.IndexOutOfRange.selector);
        resolver.getChainAtIndex(1);
    }

    function test_004____supportedDataKeys_______________ReturnsSetKeys()
        public
    {
        vm.startPrank(admin);
        registerTestChain();
        vm.stopPrank();

        // Set some data keys
        vm.startPrank(user1);
        resolver.setData(TEST_LABELHASH, "custom-key-1", hex"1234");
        resolver.setData(TEST_LABELHASH, "custom-key-2", hex"5678");
        vm.stopPrank();

        // Get the node for this chain
        bytes32 node = keccak256(
            abi.encodePacked(
                resolver.parentNamehash(),
                TEST_LABELHASH
            )
        );

        // Query supportedDataKeys
        string[] memory keys = resolver.supportedDataKeys(node);

        // Should have 3 keys: interoperable-address (from registration) + 2 custom
        assertEq(keys.length, 3, "Should have 3 data keys");
        assertEq(keys[0], "interoperable-address", "First key should be interoperable-address");
        assertEq(keys[1], "custom-key-1", "Second key should be custom-key-1");
        assertEq(keys[2], "custom-key-2", "Third key should be custom-key-2");

        console.log("Successfully returned supported data keys");
    }

    function test_005____supportedDataKeys_______________WorksForAliases()
        public
    {
        vm.startPrank(admin);
        registerTestChain();
        resolver.registerAlias("op", TEST_LABELHASH);
        vm.stopPrank();

        // Set data via canonical
        vm.startPrank(user1);
        resolver.setData(TEST_LABELHASH, "custom-key", hex"abcd");
        vm.stopPrank();

        // Get nodes for both canonical and alias
        bytes32 canonicalNode = keccak256(
            abi.encodePacked(
                resolver.parentNamehash(),
                TEST_LABELHASH
            )
        );
        bytes32 aliasLabelhash = keccak256(bytes("op"));
        bytes32 aliasNode = keccak256(
            abi.encodePacked(
                resolver.parentNamehash(),
                aliasLabelhash
            )
        );

        // Both should return the same keys
        string[] memory canonicalKeys = resolver.supportedDataKeys(canonicalNode);
        string[] memory aliasKeys = resolver.supportedDataKeys(aliasNode);

        assertEq(canonicalKeys.length, aliasKeys.length, "Alias should return same number of keys");
        assertEq(canonicalKeys.length, 2, "Should have 2 data keys");

        console.log("Successfully returned data keys via alias node");
    }

    function test_006____supportedDataKeys_______________EmptyForUnregistered()
        public
        view
    {
        // Query for non-existent node
        bytes32 randomNode = keccak256("random");
        string[] memory keys = resolver.supportedDataKeys(randomNode);

        assertEq(keys.length, 0, "Should return empty array for unregistered node");

        console.log("Successfully returned empty for unregistered node");
    }

    function test_007____supportedTextKeys_______________ReturnsSetKeys()
        public
    {
        vm.startPrank(admin);
        registerTestChain();
        vm.stopPrank();

        // Set some text keys
        vm.startPrank(user1);
        resolver.setText(TEST_LABELHASH, "url", "https://optimism.io");
        resolver.setText(TEST_LABELHASH, "description", "Optimism L2");
        vm.stopPrank();

        // Get the node for this chain
        bytes32 node = keccak256(
            abi.encodePacked(
                resolver.parentNamehash(),
                TEST_LABELHASH
            )
        );

        // Query supportedTextKeys
        string[] memory keys = resolver.supportedTextKeys(node);

        // Should have 2 keys (the ones we set)
        assertEq(keys.length, 2, "Should have 2 text keys");
        assertEq(keys[0], "url", "First key should be url");
        assertEq(keys[1], "description", "Second key should be description");

        console.log("Successfully returned supported text keys");
    }

    function test_010____supportedTextKeys_______________WorksForAliases()
        public
    {
        vm.startPrank(admin);
        registerTestChain();
        resolver.registerAlias("op", TEST_LABELHASH);
        vm.stopPrank();

        // Set text via canonical
        vm.startPrank(user1);
        resolver.setText(TEST_LABELHASH, "url", "https://optimism.io");
        vm.stopPrank();

        // Get nodes for both canonical and alias
        bytes32 canonicalNode = keccak256(
            abi.encodePacked(
                resolver.parentNamehash(),
                TEST_LABELHASH
            )
        );
        bytes32 aliasLabelhash = keccak256(bytes("op"));
        bytes32 aliasNode = keccak256(
            abi.encodePacked(
                resolver.parentNamehash(),
                aliasLabelhash
            )
        );

        // Both should return the same keys
        string[] memory canonicalKeys = resolver.supportedTextKeys(canonicalNode);
        string[] memory aliasKeys = resolver.supportedTextKeys(aliasNode);

        assertEq(canonicalKeys.length, aliasKeys.length, "Alias should return same number of keys");
        assertEq(canonicalKeys.length, 1, "Should have 1 text key");

        console.log("Successfully returned text keys via alias node");
    }

    function test_011____supportedTextKeys_______________EmptyForUnregistered()
        public
        view
    {
        // Query for non-existent node
        bytes32 randomNode = keccak256("random");
        string[] memory keys = resolver.supportedTextKeys(randomNode);

        assertEq(keys.length, 0, "Should return empty array for unregistered node");

        console.log("Successfully returned empty for unregistered node");
    }

    function test_012____supportedTextKeys_______________IncludesRegistrationKeys()
        public
    {
        vm.startPrank(admin);
        registerTestChain();
        vm.stopPrank();

        // Get the node for the reverse record (where chain-label: keys are stored)
        bytes32 reverseLabelhash = keccak256(bytes("reverse"));
        bytes32 reverseNode = keccak256(
            abi.encodePacked(
                resolver.parentNamehash(),
                reverseLabelhash
            )
        );

        // Query supportedTextKeys for reverse node
        string[] memory keys = resolver.supportedTextKeys(reverseNode);

        // Should have 1 key from registration (chain-label:<interoperable-address>)
        assertEq(keys.length, 1, "Should have 1 text key from registration");

        console.log("Successfully returned registration text keys");
    }
}
