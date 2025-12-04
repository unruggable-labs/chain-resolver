// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "./ChainResolverTestBase.sol";

contract ChainResolverEnumerationTest is ChainResolverTestBase {
    // Example 7930 chain IDs
    bytes public constant OP_ID = hex"00010001010a00"; // Optimism
    bytes public constant ARB_ID = hex"00010001016600"; // Arbitrum

    function setUp() public {
        vm.startPrank(admin);
        resolver = deployResolver(admin);
        vm.stopPrank();
    }

    // Identify the file being tested
    function test1000________________________________________________________________________________() public {}
    function test1100_____________________________ENUMERATION____________________________________() public {}
    function test1200________________________________________________________________________________() public {}

    function test_001____enumeration_____________________SingleInsertAndUpdate() public {
        vm.startPrank(admin);
        // First insert
        resolver.register(IChainResolver.ChainRegistrationData({label: "optimism", chainName: "Optimism", owner: user1, interoperableAddress: OP_ID}));
        assertEq(resolver.chainCount(), 1, "chainCount should be 1 after first insert");
        // Verify index 0
        (string memory lbl0, string memory name0, bytes memory i0) = resolver.getChainAtIndex(0);
        assertEq(lbl0, "optimism");
        assertEq(name0, "Optimism");
        // Update same label with new owner + name + id
        resolver.register(IChainResolver.ChainRegistrationData({label: "optimism", chainName: "OP Mainnet", owner: user2, interoperableAddress: OP_ID}));
        assertEq(resolver.chainCount(), 1, "chainCount should not increment on update");
        (string memory lbl1, string memory name1, bytes memory i1) = resolver.getChainAtIndex(0);
        assertEq(lbl1, "optimism");
        assertEq(name1, "OP Mainnet");
        vm.stopPrank();
    }

    function test_002____enumeration_____________________BatchInsert() public {
        vm.startPrank(admin);

        // Build batch structs
        IChainResolver.ChainRegistrationData[] memory items = new IChainResolver.ChainRegistrationData[](2);
        items[0] = IChainResolver.ChainRegistrationData({label: "optimism", chainName: "Optimism", owner: user1, interoperableAddress: OP_ID});
        items[1] = IChainResolver.ChainRegistrationData({label: "arbitrum", chainName: "Arbitrum", owner: user2, interoperableAddress: ARB_ID});

        // Register in a single batch
        resolver.batchRegister(items);

        // chainCount reflects unique labels
        assertEq(resolver.chainCount(), 2, "chainCount should equal number of unique labels");

        // Verify enumeration order matches insertion order
        (string memory l0, string memory n0, bytes memory i0) = resolver.getChainAtIndex(0);
        (string memory l1, string memory n1, bytes memory i1) = resolver.getChainAtIndex(1);
        assertEq(l0, "optimism");
        assertEq(n0, "Optimism");
        assertEq(l1, "arbitrum");
        assertEq(n1, "Arbitrum");

        vm.stopPrank();
    }

    function test_003____enumeration_____________________OutOfBoundsReverts() public {
        vm.startPrank(admin);

        // Seed with a single entry
        resolver.register(IChainResolver.ChainRegistrationData({label: "optimism", chainName: "Optimism", owner: user1, interoperableAddress: OP_ID}));
        vm.stopPrank();

        // Index 1 is out-of-bounds; expect revert
        vm.expectRevert(IChainResolver.IndexOutOfRange.selector);
        resolver.getChainAtIndex(1);
    }
}
