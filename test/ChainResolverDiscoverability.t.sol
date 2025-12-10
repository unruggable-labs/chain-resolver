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
}
