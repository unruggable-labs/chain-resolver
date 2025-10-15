// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "../src/ChainResolver.sol";

contract ChainResolverAuthTest is Test {
    ChainResolver public resolver;

    address public admin = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    address public attacker = address(0x999);

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

    function test1100_____________________________CHAIN_RESOLVER_AUTH________________________________() public {}

    function test1200________________________________________________________________________________() public {}

    function test_001____register____________________UnauthorizedRegistration() public {
        vm.startPrank(admin);

        // Register a chain legitimately
        resolver.register(CHAIN_NAME, user1, CHAIN_ID);

        vm.stopPrank();

        // Attacker tries to register a chain
        vm.startPrank(attacker);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        resolver.register("attacker-label", attacker, hex"0101");

        vm.stopPrank();

        // Verify registration failed
        assertEq(resolver.chainName(hex"0101"), hex"", "Unauthorized registration failed");

        console.log("Successfully prevented unauthorized registration");
    }

    function test_002____setLabelOwner_______________UnauthorizedOwnershipTransfer() public {
        vm.startPrank(admin);

        // Register a chain
        resolver.register(CHAIN_NAME, user1, CHAIN_ID);

        vm.stopPrank();

        // Attacker tries to transfer ownership
        vm.startPrank(attacker);

        vm.expectRevert(abi.encodeWithSelector(IChainResolver.NotAuthorized.selector, attacker, LABEL_HASH));
        resolver.setLabelOwner(LABEL_HASH, attacker);

        vm.stopPrank();

        // Verify original ownership is intact
        assertEq(resolver.getOwner(LABEL_HASH), user1, "Original owner should remain");

        console.log("Successfully prevented unauthorized ownership transfer");
    }

    function test_003____setAddr_____________________UnauthorizedAddressSetting() public {
        vm.startPrank(admin);

        // Register a chain
        resolver.register(CHAIN_NAME, user1, CHAIN_ID);

        vm.stopPrank();

        // Attacker tries to set address records
        vm.startPrank(attacker);

        vm.expectRevert(abi.encodeWithSelector(IChainResolver.NotAuthorized.selector, attacker, LABEL_HASH));
        resolver.setAddr(LABEL_HASH, attacker);

        vm.stopPrank();

        console.log("Successfully prevented unauthorized address setting");
    }

    function test_004____setText_____________________UnauthorizedTextSetting() public {
        vm.startPrank(admin);

        // Register a chain
        resolver.register(CHAIN_NAME, user1, CHAIN_ID);

        vm.stopPrank();

        // Attacker tries to set text records
        vm.startPrank(attacker);

        vm.expectRevert(abi.encodeWithSelector(IChainResolver.NotAuthorized.selector, attacker, LABEL_HASH));
        resolver.setText(LABEL_HASH, "website", "https://hacked.com");

        vm.stopPrank();

        // Verify no text was set
        assertEq(resolver.getText(LABEL_HASH, "website"), "", "No text should be set");

        console.log("Successfully prevented unauthorized text setting");
    }

    function test_005____setData_____________________UnauthorizedDataSetting() public {
        vm.startPrank(admin);

        // Register a chain
        resolver.register(CHAIN_NAME, user1, CHAIN_ID);

        vm.stopPrank();

        // Attacker tries to set data records
        vm.startPrank(attacker);

        vm.expectRevert(abi.encodeWithSelector(IChainResolver.NotAuthorized.selector, attacker, LABEL_HASH));
        resolver.setData(LABEL_HASH, "custom", hex"deadbeef");

        vm.stopPrank();

        // Verify no data was set
        assertEq(resolver.getData(LABEL_HASH, "custom"), "", "No data should be set");

        console.log("Successfully prevented unauthorized data setting");
    }

    function test_006____setContenthash______________UnauthorizedContentHashSetting() public {
        vm.startPrank(admin);

        // Register a chain
        resolver.register(CHAIN_NAME, user1, CHAIN_ID);

        vm.stopPrank();

        // Attacker tries to set content hash
        vm.startPrank(attacker);

        vm.expectRevert(abi.encodeWithSelector(IChainResolver.NotAuthorized.selector, attacker, LABEL_HASH));
        resolver.setContenthash(
            LABEL_HASH, hex"e30101701220deadbeef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
        );

        vm.stopPrank();

        // Verify no content hash was set
        assertEq(resolver.getContenthash(LABEL_HASH), "", "No content hash should be set");

        console.log("Successfully prevented unauthorized content hash setting");
    }

    function test_007____setOperator_________________AuthorizationLogic() public {
        vm.startPrank(admin);

        // Register a chain
        resolver.register(CHAIN_NAME, user1, CHAIN_ID);

        vm.stopPrank();

        // Operator management scenarios (add/remove per-owner operators)
        vm.startPrank(user1);

        // Set multiple operators
        resolver.setOperator(user2, true);
        resolver.setOperator(attacker, true);
        resolver.setOperator(address(this), true);

        // Verify all are authorized
        assertTrue(resolver.isAuthorized(LABEL_HASH, user2), "User2 should be authorized");
        assertTrue(resolver.isAuthorized(LABEL_HASH, attacker), "Attacker should be authorized");
        assertTrue(resolver.isAuthorized(LABEL_HASH, address(this)), "Contract should be authorized");

        // Test operator interactions
        vm.stopPrank();
        vm.startPrank(user1);

        // User1 removes attacker
        resolver.setOperator(attacker, false);

        // Assert label owner removed label authorization
        assertFalse(resolver.isAuthorized(LABEL_HASH, attacker));
        vm.stopPrank();

        vm.startPrank(user2);

        // User2 tries to set new operator (this works because setOperator is per-caller)
        resolver.setOperator(address(0x777), true);
        // But this doesn't make address(0x777) authorized for the label hash
        assertFalse(
            resolver.isAuthorized(LABEL_HASH, address(0x777)), "New operator should not be authorized for label hash"
        );

        vm.stopPrank();

        console.log("Successfully handled operator management");
    }
}
