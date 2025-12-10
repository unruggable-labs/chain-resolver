// SPDX-License-Identifier: MIT

// Tests that verify that only the owner of a chain can perform certain actions.
// The owner of a chain is set during registration.

pragma solidity ^0.8.25;

import "./ChainResolverTestBase.sol";
import {
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract ChainResolverAuthTest is ChainResolverTestBase {
    address public attacker = address(0x999);

    // Cointype constants
    uint256 public constant ETHEREUM_COINTYPE = 60;

    function setUp() public {
        vm.startPrank(admin);
        resolver = deployResolver(admin);
        vm.stopPrank();
    }

    // Check that only the owner of the ChainResolver can register a chain
    function test_001____register____________________UnauthorizedRegistration()
        public
    {
        vm.startPrank(admin);
        registerTestChain();
        vm.stopPrank();

        // Attacker tries to register a chain
        vm.startPrank(attacker);

        vm.expectRevert(
            abi.encodeWithSelector(
                OwnableUpgradeable.OwnableUnauthorizedAccount.selector,
                attacker
            )
        );
        registerChain("attacker-label", "attacker-label", attacker, hex"0101");

        vm.stopPrank();

        // Verify registration failed
        assertEq(
            resolver.chainName(hex"0101"),
            "",
            "Unauthorized registration failed"
        );

        console.log("Successfully prevented unauthorized registration");
    }

    // Check that only the owner of a chain can transfer its ownership
    function test_002____setChainAdmin_______________UnauthorizedOwnershipTransfer()
        public
    {
        vm.startPrank(admin);
        registerTestChain();
        vm.stopPrank();

        // Attacker tries to transfer ownership
        vm.startPrank(attacker);

        vm.expectRevert(
            abi.encodeWithSelector(
                IChainResolver.NotChainOwner.selector,
                attacker,
                TEST_LABELHASH
            )
        );
        resolver.setChainAdmin(TEST_LABELHASH, attacker);

        vm.stopPrank();

        // Verify original ownership is intact
        assertEq(
            resolver.getChainAdmin(TEST_LABELHASH),
            user1,
            "Original owner should remain"
        );

        console.log("Successfully prevented unauthorized ownership transfer");
    }


    function test_003____setAddr_____________________UnauthorizedAddressSetting()
        public
    {
        vm.startPrank(admin);
        registerTestChain();
        vm.stopPrank();

        // Attacker tries to set address records
        vm.startPrank(attacker);

        vm.expectRevert(
            abi.encodeWithSelector(
                IChainResolver.NotChainOwner.selector,
                attacker,
                TEST_LABELHASH
            )
        );
        resolver.setAddr(
            TEST_LABELHASH,
            ETHEREUM_COINTYPE,
            abi.encodePacked(attacker)
        );

        vm.stopPrank();

        console.log("Successfully prevented unauthorized address setting");
    }

    // Check that only the owner of a chain can set text records
    function test_004____setText_____________________UnauthorizedTextSetting()
        public
    {
        vm.startPrank(admin);
        registerTestChain();
        vm.stopPrank();

        // Attacker tries to set text records
        vm.startPrank(attacker);

        vm.expectRevert(
            abi.encodeWithSelector(
                IChainResolver.NotChainOwner.selector,
                attacker,
                TEST_LABELHASH
            )
        );
        resolver.setText(TEST_LABELHASH, "url", "https://hacked.com");

        vm.stopPrank();

        // Verify no text was set
        assertEq(
            resolver.getText(TEST_LABELHASH, "url"),
            "",
            "No text should be set"
        );

        console.log("Successfully prevented unauthorized text setting");
    }

    // Check that only the owner of a chain can set data records
    function test_005____setData_____________________UnauthorizedDataSetting()
        public
    {
        vm.startPrank(admin);
        registerTestChain();
        vm.stopPrank();

        // Attacker tries to set data records
        vm.startPrank(attacker);

        vm.expectRevert(
            abi.encodeWithSelector(
                IChainResolver.NotChainOwner.selector,
                attacker,
                TEST_LABELHASH
            )
        );
        resolver.setData(TEST_LABELHASH, "custom", hex"deadbeef");

        vm.stopPrank();

        // Verify no data was set
        assertEq(
            resolver.getData(TEST_LABELHASH, "custom"),
            "",
            "No data should be set"
        );

        console.log("Successfully prevented unauthorized data setting");
    }

    // Check that only the owner of a chain can set the contenthash
    function test_006____setContenthash______________UnauthorizedContentHashSetting()
        public
    {
        vm.startPrank(admin);
        registerTestChain();
        vm.stopPrank();

        // Attacker tries to set content hash
        vm.startPrank(attacker);

        vm.expectRevert(
            abi.encodeWithSelector(
                IChainResolver.NotChainOwner.selector,
                attacker,
                TEST_LABELHASH
            )
        );
        resolver.setContenthash(
            TEST_LABELHASH,
            hex"e30101701220deadbeef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
        );

        vm.stopPrank();

        // Verify no content hash was set
        assertEq(
            resolver.getContenthash(TEST_LABELHASH),
            "",
            "No content hash should be set"
        );

        console.log("Successfully prevented unauthorized content hash setting");
    }


    function test_007____authenticateCaller___________OwnerIsCaller() public {
        vm.startPrank(admin);
        registerTestChain();
        vm.stopPrank();

        // Test _authenticateCaller when owner is the caller
        vm.startPrank(user1);

        // This should not revert because user1 is the owner
        resolver.setText(TEST_LABELHASH, "test-key", "test-value");

        vm.stopPrank();

        console.log("Successfully authenticated owner as caller");
    }
}
