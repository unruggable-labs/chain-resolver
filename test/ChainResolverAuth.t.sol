// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/ChainResolver.sol";
import "../src/interfaces/IChainResolver.sol";

contract ChainResolverAuthTest is Test {
    ChainResolver public resolver;

    address public admin = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    address public attacker = address(0x999);

    // Coin type constants
    uint256 public constant ETHEREUM_COIN_TYPE = 60;

    // Test data - using 7930 chain ID format
    string public constant LABEL = "optimism";
    string public constant CHAIN_NAME = "optimism";
    bytes public constant CHAIN_INTEROPERABLE_ADDRESS = hex"00010001010a00";
    bytes32 public constant LABEL_HASH = keccak256(bytes(LABEL));

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
        resolver.register(IChainResolver.ChainRegistrationData({label: LABEL, chainName: CHAIN_NAME, owner: user1, interoperableAddress: CHAIN_INTEROPERABLE_ADDRESS}));

        vm.stopPrank();

        // Attacker tries to register a chain
        vm.startPrank(attacker);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        resolver.register(IChainResolver.ChainRegistrationData({label: "attacker-label", chainName: "attacker-label", owner: attacker, interoperableAddress: hex"0101"}));

        vm.stopPrank();

        // Verify registration failed
        assertEq(resolver.chainName(hex"0101"), "", "Unauthorized registration failed");

        console.log("Successfully prevented unauthorized registration");
    }

    function test_002____setLabelOwner_______________UnauthorizedOwnershipTransfer() public {
        vm.startPrank(admin);

        // Register a chain
        resolver.register(IChainResolver.ChainRegistrationData({label: LABEL, chainName: CHAIN_NAME, owner: user1, interoperableAddress: CHAIN_INTEROPERABLE_ADDRESS}));

        vm.stopPrank();

        // Attacker tries to transfer ownership
        vm.startPrank(attacker);

        vm.expectRevert(abi.encodeWithSelector(IChainResolver.NotChainOwner.selector, attacker, LABEL_HASH));
        resolver.setChainAdmin(LABEL_HASH, attacker);

        vm.stopPrank();

        // Verify original ownership is intact
        assertEq(resolver.getChainAdmin(LABEL_HASH), user1, "Original owner should remain");

        console.log("Successfully prevented unauthorized ownership transfer");
    }

    function test_003____setAddr_____________________UnauthorizedAddressSetting() public {
        vm.startPrank(admin);

        // Register a chain
        resolver.register(IChainResolver.ChainRegistrationData({label: LABEL, chainName: CHAIN_NAME, owner: user1, interoperableAddress: CHAIN_INTEROPERABLE_ADDRESS}));

        vm.stopPrank();

        // Attacker tries to set address records
        vm.startPrank(attacker);

        vm.expectRevert(abi.encodeWithSelector(IChainResolver.NotChainOwner.selector, attacker, LABEL_HASH));
        resolver.setAddr(LABEL_HASH, ETHEREUM_COIN_TYPE, abi.encodePacked(attacker));

        vm.stopPrank();

        console.log("Successfully prevented unauthorized address setting");
    }

    function test_004____setText_____________________UnauthorizedTextSetting() public {
        vm.startPrank(admin);

        // Register a chain
        resolver.register(IChainResolver.ChainRegistrationData({label: LABEL, chainName: CHAIN_NAME, owner: user1, interoperableAddress: CHAIN_INTEROPERABLE_ADDRESS}));

        vm.stopPrank();

        // Attacker tries to set text records
        vm.startPrank(attacker);

        vm.expectRevert(abi.encodeWithSelector(IChainResolver.NotChainOwner.selector, attacker, LABEL_HASH));
        resolver.setText(LABEL_HASH, "website", "https://hacked.com");

        vm.stopPrank();

        // Verify no text was set
        assertEq(resolver.getText(LABEL_HASH, "website"), "", "No text should be set");

        console.log("Successfully prevented unauthorized text setting");
    }

    function test_005____setData_____________________UnauthorizedDataSetting() public {
        vm.startPrank(admin);

        // Register a chain
        resolver.register(IChainResolver.ChainRegistrationData({label: LABEL, chainName: CHAIN_NAME, owner: user1, interoperableAddress: CHAIN_INTEROPERABLE_ADDRESS}));

        vm.stopPrank();

        // Attacker tries to set data records
        vm.startPrank(attacker);

        vm.expectRevert(abi.encodeWithSelector(IChainResolver.NotChainOwner.selector, attacker, LABEL_HASH));
        resolver.setData(LABEL_HASH, "custom", hex"deadbeef");

        vm.stopPrank();

        // Verify no data was set
        assertEq(resolver.getData(LABEL_HASH, "custom"), "", "No data should be set");

        console.log("Successfully prevented unauthorized data setting");
    }

    function test_006____setContenthash______________UnauthorizedContentHashSetting() public {
        vm.startPrank(admin);

        // Register a chain
        resolver.register(IChainResolver.ChainRegistrationData({label: LABEL, chainName: CHAIN_NAME, owner: user1, interoperableAddress: CHAIN_INTEROPERABLE_ADDRESS}));

        vm.stopPrank();

        // Attacker tries to set content hash
        vm.startPrank(attacker);

        vm.expectRevert(abi.encodeWithSelector(IChainResolver.NotChainOwner.selector, attacker, LABEL_HASH));
        resolver.setContenthash(
            LABEL_HASH, hex"e30101701220deadbeef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
        );

        vm.stopPrank();

        // Verify no content hash was set
        assertEq(resolver.getContenthash(LABEL_HASH), "", "No content hash should be set");

        console.log("Successfully prevented unauthorized content hash setting");
    }
}
