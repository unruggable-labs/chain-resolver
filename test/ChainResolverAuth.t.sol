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

        // Attacker tries to register the same chain name
        vm.startPrank(attacker);

        vm.expectRevert(); // Should fail due to onlyOwner modifier
        resolver.register(CHAIN_NAME, attacker, CHAIN_ID);

        vm.stopPrank();

        // Verify original registration is intact
        assertEq(resolver.getOwner(LABEL_HASH), user1, "Original owner should remain");

        console.log("Successfully prevented unauthorized registration");
    }

    function test_002____setLabelOwner_______________UnauthorizedOwnershipTransfer() public {
        vm.startPrank(admin);

        // Register a chain
        resolver.register(CHAIN_NAME, user1, CHAIN_ID);

        vm.stopPrank();

        // Attacker tries to transfer ownership
        vm.startPrank(attacker);

        vm.expectRevert();
        resolver.setLabelOwner(LABEL_HASH, attacker);

        vm.stopPrank();

        // Verify original ownership is intact
        assertEq(resolver.getOwner(LABEL_HASH), user1, "Original owner should remain");

        console.log("Successfully prevented unauthorized ownership transfer");
    }

    function test_003____setOperator_________________UnauthorizedOperatorSetting() public {
        vm.startPrank(admin);

        // Register a chain
        resolver.register(CHAIN_NAME, user1, CHAIN_ID);

        vm.stopPrank();

        // Attacker tries to set themselves as operator
        vm.startPrank(attacker);

        // This works but doesn't make attacker authorized for the label hash
        resolver.setOperator(attacker, true);

        vm.stopPrank();

        // Verify attacker is still not authorized for the label hash
        assertFalse(resolver.isAuthorized(LABEL_HASH, attacker), "Attacker should not be authorized for label hash");

        console.log("Successfully prevented unauthorized operator setting");
    }

    function test_004____setAddr_____________________UnauthorizedAddressSetting() public {
        vm.startPrank(admin);

        // Register a chain
        resolver.register(CHAIN_NAME, user1, CHAIN_ID);

        vm.stopPrank();

        // Attacker tries to set address records
        vm.startPrank(attacker);

        vm.expectRevert();
        resolver.setAddr(LABEL_HASH, 60, attacker);

        vm.stopPrank();

        // Verify no address was set
        assertEq(resolver.getAddr(LABEL_HASH, 60), address(0), "No address should be set");

        console.log("Successfully prevented unauthorized address setting");
    }

    function test_005____setText_____________________UnauthorizedTextSetting() public {
        vm.startPrank(admin);

        // Register a chain
        resolver.register(CHAIN_NAME, user1, CHAIN_ID);

        vm.stopPrank();

        // Attacker tries to set text records
        vm.startPrank(attacker);

        vm.expectRevert();
        resolver.setText(LABEL_HASH, "website", "https://hacked.com");

        vm.stopPrank();

        // Verify no text was set
        assertEq(resolver.getText(LABEL_HASH, "website"), "", "No text should be set");

        console.log("Successfully prevented unauthorized text setting");
    }

    function test_006____setData_____________________UnauthorizedDataSetting() public {
        vm.startPrank(admin);

        // Register a chain
        resolver.register(CHAIN_NAME, user1, CHAIN_ID);

        vm.stopPrank();

        // Attacker tries to set data records
        vm.startPrank(attacker);

        vm.expectRevert();
        resolver.setData(LABEL_HASH, "custom", hex"deadbeef");

        vm.stopPrank();

        // Verify no data was set
        assertEq(resolver.getData(LABEL_HASH, "custom"), "", "No data should be set");

        console.log("Successfully prevented unauthorized data setting");
    }

    function test_007____setContenthash______________UnauthorizedContentHashSetting() public {
        vm.startPrank(admin);

        // Register a chain
        resolver.register(CHAIN_NAME, user1, CHAIN_ID);

        vm.stopPrank();

        // Attacker tries to set content hash
        vm.startPrank(attacker);

        vm.expectRevert();
        resolver.setContenthash(
            LABEL_HASH, hex"e30101701220deadbeef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
        );

        vm.stopPrank();

        // Verify no content hash was set
        assertEq(resolver.getContenthash(LABEL_HASH), "", "No content hash should be set");

        console.log("Successfully prevented unauthorized content hash setting");
    }

    function test_008____resolve_____________________InvalidDNSEncodingReverts() public {
        vm.startPrank(admin);

        // Register a chain
        resolver.register(CHAIN_NAME, user1, CHAIN_ID);

        vm.stopPrank();

        // Invalid DNS-encoded name should revert
        bytes memory maliciousName = abi.encodePacked(
            bytes1(0xff), // Invalid length byte
            "optimism",
            bytes1(0x00)
        );

        bytes memory textData = abi.encodeWithSelector(resolver.TEXT_SELECTOR(), LABEL_HASH, "description");

        // This should revert due to invalid DNS encoding
        vm.expectRevert();
        resolver.resolve(maliciousName, textData);

        console.log("Successfully handled invalid DNS encoding");
    }

    function test_009____isAuthorized_________________AuthorizationLogic() public {
        vm.startPrank(admin);

        // Register a chain
        resolver.register(CHAIN_NAME, user1, CHAIN_ID);

        vm.stopPrank();

        // Test various authorization bypass attempts
        assertFalse(resolver.isAuthorized(LABEL_HASH, attacker), "Attacker should not be authorized");
        assertFalse(resolver.isAuthorized(LABEL_HASH, address(0)), "Zero address should not be authorized");
        assertFalse(resolver.isAuthorized(LABEL_HASH, address(this)), "Contract should not be authorized");

        // Verify legitimate authorization works
        assertTrue(resolver.isAuthorized(LABEL_HASH, user1), "Owner should be authorized");

        // Set operator and verify
        vm.startPrank(user1);
        resolver.setOperator(user2, true);
        vm.stopPrank();

        assertTrue(resolver.isAuthorized(LABEL_HASH, user2), "Operator should be authorized");

        console.log("Successfully handled authorization logic");
    }
}
