// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "../src/ChainResolver.sol";
import "../src/ChainRegistry.sol";
import "../src/interfaces/IChainResolver.sol";

contract ChainResolverRegistryTest is Test {
    ChainResolver public resolver;
    ChainRegistry public registry;

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
        registry = new ChainRegistry(admin);
        resolver = new ChainResolver(admin, address(registry));
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

    function test_003____setLabelOwner_______________TransfersLabelOwnership() public {
        vm.startPrank(admin);

        // Register a chain
        resolver.register(CHAIN_NAME, user1, CHAIN_ID);

        vm.stopPrank();

        // User1 tries to transfer ownership to user2 - should revert
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(ChainResolver.UseRegistryForOwnershipManagement.selector));
        resolver.setLabelOwner(LABEL_HASH, user2);

        // Verify original ownership is unchanged
        assertEq(resolver.getOwner(LABEL_HASH), user1, "Original owner should remain");

        vm.stopPrank();

        console.log("Successfully prevented ownership transfer - use registry for ownership management");
    }

    function test_004____batchRegister_______________SuccessfulBatchRegistration() public {
        vm.startPrank(admin);

        // Prepare batch data
        string[] memory chainNames = new string[](2);
        address[] memory owners = new address[](2);
        bytes[] memory chainIds = new bytes[](2);

        chainNames[0] = "optimism";
        chainNames[1] = "arbitrum";
        owners[0] = user1;
        owners[1] = user2;
        chainIds[0] = hex"000000010001010a00"; // optimism
        chainIds[1] = hex"000000010001016600"; // arbitrum

        // Register batch
        resolver.batchRegister(chainNames, owners, chainIds);

        // Verify registrations
        assertEq(resolver.getOwner(keccak256(bytes("optimism"))), user1);
        assertEq(resolver.getOwner(keccak256(bytes("arbitrum"))), user2);
        assertEq(resolver.chainId(keccak256(bytes("optimism"))), chainIds[0]);
        assertEq(resolver.chainId(keccak256(bytes("arbitrum"))), chainIds[1]);

        vm.stopPrank();

        console.log("Successfully registered batch of chains");
    }

    function test_005____batchRegister_______________RevertsOnMismatchedArrayLengths() public {
        vm.startPrank(admin);

        // Prepare mismatched arrays
        string[] memory chainNames = new string[](2);
        address[] memory owners = new address[](1); // Different length
        bytes[] memory chainIds = new bytes[](2);

        chainNames[0] = "optimism";
        chainNames[1] = "arbitrum";
        owners[0] = user1;
        chainIds[0] = hex"000000010001010a00";
        chainIds[1] = hex"000000010001016600";

        // Should revert with InvalidDataLength
        vm.expectRevert(IChainResolver.InvalidDataLength.selector);
        resolver.batchRegister(chainNames, owners, chainIds);

        vm.stopPrank();

        console.log("Successfully reverted on mismatched array lengths");
    }

    function test_006____batchRegister_______________RevertsOnMismatchedChainIdsLength() public {
        vm.startPrank(admin);

        // Prepare mismatched arrays
        string[] memory chainNames = new string[](2);
        address[] memory owners = new address[](2);
        bytes[] memory chainIds = new bytes[](1); // Different length

        chainNames[0] = "optimism";
        chainNames[1] = "arbitrum";
        owners[0] = user1;
        owners[1] = user2;
        chainIds[0] = hex"000000010001010a00";

        // Should revert with InvalidDataLength
        vm.expectRevert(IChainResolver.InvalidDataLength.selector);
        resolver.batchRegister(chainNames, owners, chainIds);

        vm.stopPrank();

        console.log("Successfully reverted on mismatched chainIds length");
    }

    function test_007____batchRegister_______________EmptyArrays() public {
        vm.startPrank(admin);

        // Prepare empty arrays
        string[] memory chainNames = new string[](0);
        address[] memory owners = new address[](0);
        bytes[] memory chainIds = new bytes[](0);

        // Should not revert with empty arrays
        resolver.batchRegister(chainNames, owners, chainIds);

        vm.stopPrank();

        console.log("Successfully handled empty arrays");
    }

    function test_008____batchRegister_______________SingleItemBatch() public {
        vm.startPrank(admin);

        // Prepare single item batch
        string[] memory chainNames = new string[](1);
        address[] memory owners = new address[](1);
        bytes[] memory chainIds = new bytes[](1);

        chainNames[0] = "optimism";
        owners[0] = user1;
        chainIds[0] = hex"000000010001010a00";

        // Register single item
        resolver.batchRegister(chainNames, owners, chainIds);

        // Verify registration
        assertEq(resolver.getOwner(keccak256(bytes("optimism"))), user1);
        assertEq(resolver.chainId(keccak256(bytes("optimism"))), chainIds[0]);

        vm.stopPrank();

        console.log("Successfully registered single item batch");
    }
}
