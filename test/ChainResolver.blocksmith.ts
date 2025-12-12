// Local simulation of ChainResolver functionality
// Usage: bun run test/ChainResolver.blocksmith.ts

import "dotenv/config";
import { Foundry } from "@adraffy/blocksmith";
import {
  Contract,
  Interface,
  dnsEncode,
  keccak256,
  toUtf8Bytes,
  getBytes,
  hexlify,
  namehash,
} from "ethers";
import {
  INTEROPERABLE_ADDRESS_DATA_KEY,
  CHAIN_LABEL_PREFIX,
  ETHEREUM_COIN_TYPE,
} from "../shared/constants.ts";

// Helper functions
const log = (...a: any[]) => console.log("[blocksmith]", ...a);
const section = (name: string) => console.log(`\n=== ${name} ===`);
const hex = (b: any) => {
  try {
    return hexlify(b);
  } catch {
    return String(b);
  }
};

// Log all events from a transaction receipt
const logEvents = (receipt: any, contract: Contract) => {
  for (const logEntry of receipt.logs) {
    try {
      const event = contract.interface.parseLog(logEntry);
      if (event) console.log("Event", event.name, event.args);
    } catch (e) {
      // not an event from this interface
    }
  }
};

// Import shared chain data
import type { ChainData } from "../data/chains.ts";
import { CHAINS, getChainByLabel } from "../data/chains.ts";

// Helper to register a chain
const registerChain = async (
  contract: Contract,
  owner: string,
  chain: ChainData
) => {
  const tx = await contract.register!([
    chain.label,
    chain.chainName,
    owner,
    getBytes(chain.interoperableAddressHex),
  ]);
  const receipt = await tx.wait();
  logEvents(receipt, contract);
  log(`Registered chain: ${chain.label}`);
  return receipt;
};

// The resolver contract
const RESOLVER_FILE_NAME = "ChainResolver.sol";

// Constants imported from shared/constants.ts

// Get test chains from shared data
const OPTIMISM_CHAIN = getChainByLabel("optimism")!;
const BASE_CHAIN = getChainByLabel("base")!;

// Derived constants for optimism (primary test chain)
const TEST_LABEL = OPTIMISM_CHAIN.label;
const TEST_CHAIN_NAME = OPTIMISM_CHAIN.chainName;
const INTEROPERABLE_ADDRESS_AS_HEX = OPTIMISM_CHAIN.interoperableAddressHex;
const TEST_LABELHASH = keccak256(toUtf8Bytes(TEST_LABEL));
const SECOND_LEVEL_DOMAIN = "cid.eth";
const TEST_RESOLUTION_ADDRESS = "0x000000000000000000000000000000000000dEaD";
const TEST_OTHER_COIN_TYPE = 123;
const TEST_RESOLUTION_ADDRESS_TWO = "0x0000000000000000000000000000000000000abc";
const REVERSE_NAME = `reverse.${SECOND_LEVEL_DOMAIN}.eth`;
const REVERSE_NAME_DNS_ENCODED = dnsEncode(REVERSE_NAME, 255);
const REVERSE_NODE = namehash(REVERSE_NAME);
const TEST_ALIAS = "op";
const TEST_ALIAS_LABELHASH = keccak256(toUtf8Bytes(TEST_ALIAS));
const TEST_DESCRIPTION_TEXT = "Set via alias";
const TEST_ALIAS_ENS_NAME = `${TEST_ALIAS}.${SECOND_LEVEL_DOMAIN}.eth`;
const TEST_ALIAS_DNS_ENCODED = dnsEncode(TEST_ALIAS_ENS_NAME, 255);
const TEST_ALIAS_NAMEHASH = namehash(TEST_ALIAS_ENS_NAME);


// Interfaces

// https://docs.ens.domains/ensip/5
const ENSIP_5_INTERFACE = new Interface([
  "function text(bytes32,string) view returns (string)",
]);

// https://docs.ens.domains/ensip/9
const ENSIP_9_INTERFACE = new Interface([
  "function addr(bytes32,uint256) view returns (bytes)",
]);

// https://docs.ens.domains/ensip/24
const ENSIP_24_INTERFACE = new Interface([
  "function data(bytes32,string) view returns (bytes)",
]);


async function main() {
  const smith = await Foundry.launch({ forge: "forge", infoLog: true });
  const wallet = smith.requireWallet("admin");

  section("Launch (local Foundry)");
  log("wallet", wallet.address);

  // Deploy ChainResolver via ERC1967Proxy
  const deployer = wallet.address;
  const parentNamehash = namehash(SECOND_LEVEL_DOMAIN);
  section(`Deploy ${RESOLVER_FILE_NAME} (via proxy)`);
  log("Deployer address", deployer);
  log(`Parent namehash (${SECOND_LEVEL_DOMAIN})`, parentNamehash);

  // Deploy implementation
  const implementationContract = await smith.deploy({
    from: wallet,
    file: RESOLVER_FILE_NAME,
    args: [],
  });
  log("Implementation deployed at", implementationContract.target);

  // Encode initialize call
  const initInterface = new Interface(["function initialize(address,bytes32)"]);
  const initData = initInterface.encodeFunctionData("initialize", [
    deployer,
    parentNamehash,
  ]);

  // Deploy proxy pointing to implementation
  const proxyContract = await smith.deploy({
    from: wallet,
    import: "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol",
    args: [implementationContract.target, initData],
  });
  log("Proxy deployed at", proxyContract.target);

  // Cast proxy as ChainResolver for interaction
  // Use any to allow dynamic function access on the proxy
  const resolverContract = (implementationContract as any).attach(
    proxyContract.target
  ) as any;
  const castedContract = resolverContract as Contract;
  log("Resolver (via proxy) address", proxyContract.target);

  // Register the test chain
  section("Register test chain data");
  await registerChain(castedContract, deployer, OPTIMISM_CHAIN);

  // Test Forward Resolution of ERC-7930 _Interoperable Address_
  const ensName = `${TEST_LABEL}.${SECOND_LEVEL_DOMAIN}`;
  const nameNamehash = namehash(ensName);
  const dnsEncodedName = dnsEncode(ensName, 255);

  const dataCalldata = ENSIP_24_INTERFACE.encodeFunctionData(
    "data(bytes32,string)",
    [nameNamehash, INTEROPERABLE_ADDRESS_DATA_KEY]
  );
  const dataResponse: string = await resolverContract.resolve!(
    dnsEncodedName,
    dataCalldata
  );
  const [interopableAddressBytes] = ENSIP_24_INTERFACE.decodeFunctionResult(
    "data(bytes32,string)",
    dataResponse
  );

  // Ethers returns a hex representation of the bytes
  if (interopableAddressBytes !== INTEROPERABLE_ADDRESS_AS_HEX) {
    throw new Error(
      `Unexpected Interoperable Address bytes`
    );
  }

  // Set and read an ETH address (coinType 60)
  const ADDR_INTERFACE = new Interface([
    "function addr(bytes32) view returns (address)",
  ]);

  const setAddrTx = await castedContract.setAddr!(TEST_LABELHASH, ETHEREUM_COIN_TYPE, TEST_RESOLUTION_ADDRESS);
  const setAddrReceipt = await setAddrTx.wait();
  logEvents(setAddrReceipt, castedContract);

  const addrCalldata = ADDR_INTERFACE.encodeFunctionData("addr(bytes32)", [
    TEST_LABELHASH,
  ]);
  const addrResponse = await resolverContract.resolve!(dnsEncodedName, addrCalldata);
  const [resolvedAddress] = ADDR_INTERFACE.decodeFunctionResult("addr(bytes32)", addrResponse);
  if (resolvedAddress.toLowerCase() !== TEST_RESOLUTION_ADDRESS.toLowerCase()) {
    throw new Error(`Unexpected ETH address`);
  }

  // Set and read another address (arbitrary coinType)
  const setOtherAddrTx = await castedContract.setAddr!(TEST_LABELHASH, TEST_OTHER_COIN_TYPE, TEST_RESOLUTION_ADDRESS_TWO);
  const setOtherAddrReceipt = await setOtherAddrTx.wait();
  logEvents(setOtherAddrReceipt, castedContract);

  const anotherAddrCalldata = ENSIP_9_INTERFACE.encodeFunctionData("addr(bytes32,uint256)", [
    TEST_LABELHASH,
    TEST_OTHER_COIN_TYPE,
  ]);
  const anotherAddrResponse = await resolverContract.resolve!(dnsEncodedName, anotherAddrCalldata);
  console.log("anotherAddrResponse", anotherAddrResponse);
  const [anotherResolvedAddress] = ENSIP_9_INTERFACE.decodeFunctionResult("addr(bytes32,uint256)", anotherAddrResponse);
  if (anotherResolvedAddress.toLowerCase() !== TEST_RESOLUTION_ADDRESS_TWO.toLowerCase()) {
    console.log("anotherResolvedAddress", anotherResolvedAddress);
    console.log("TEST_RESOLUTION_ADDRESS_TWO", TEST_RESOLUTION_ADDRESS_TWO);

    throw new Error(`Unexpected OTHER address`);
  }


  // Test reverse resolution - discerning the chain label from the interoperable address
  // Get the text record for key, 'chain-label:<7930hex>' for `reverse.${SECOND_LEVEL_DOMAIN}.eth`
  const reverseKey = `${CHAIN_LABEL_PREFIX}${INTEROPERABLE_ADDRESS_AS_HEX.replace(/^0x/, "")}`;

  section("Reverse Resolve (text)");
  const textCalldata = ENSIP_5_INTERFACE.encodeFunctionData(
    "text(bytes32,string)",
    [REVERSE_NODE, reverseKey]
  );
  const textResponse: string = await resolverContract.resolve!(REVERSE_NAME_DNS_ENCODED, textCalldata);
  const [chainLabel] = ENSIP_5_INTERFACE.decodeFunctionResult(
    "text(bytes32,string)",
    textResponse
  );
  log("Chain label", chainLabel);
  if (chainLabel !== TEST_LABEL)
    throw new Error(`Unexpected chain label`);

  // Getter tests
  section("Getter tests");
  const interoperableAddress = await resolverContract.interoperableAddress!(TEST_LABELHASH);
  log("Interoperable address", interoperableAddress);
  if (interoperableAddress !== INTEROPERABLE_ADDRESS_AS_HEX) {
    throw new Error("Interoperable Address mismatch");
  }

  const chainName = await resolverContract.chainName!(interoperableAddress);
  log("Chain name", chainName);
  if (chainName !== TEST_CHAIN_NAME) {
    throw new Error("Chain name mismatch");
  }

  // Alias tests
  section("Alias tests");
  log("Registering alias", TEST_ALIAS, "→", TEST_LABEL);

  // Register the alias (op → optimism)
  const aliasTx = await resolverContract.registerAlias!(TEST_ALIAS, TEST_LABELHASH);
  const aliasReceipt = await aliasTx.wait();
  logEvents(aliasReceipt, castedContract);

  // Verify the alias was registered
  const canonical = await resolverContract.getCanonicalLabelhash!(TEST_ALIAS_LABELHASH);
  if (canonical !== TEST_LABELHASH) {
    throw new Error(
      `Alias not registered correctly`
    );
  }
  log("Alias registered successfully");

  // Read Interoperable Address through getter using alias
  section("Alias - Read through alias");
  const aliasInteropAddr = await resolverContract.interoperableAddress!(
    TEST_ALIAS_LABELHASH
  );
  if (hexlify(aliasInteropAddr) !== INTEROPERABLE_ADDRESS_AS_HEX) {
    throw new Error(
      `Alias interoperableAddress mismatch: got=${hexlify(
        aliasInteropAddr
      )} want=${INTEROPERABLE_ADDRESS_AS_HEX}`
    );
  }
  log("interoperableAddress via alias ✓");

  // Read chain admin through alias
  const aliasAdmin = await resolverContract.getChainAdmin!(TEST_ALIAS_LABELHASH);
  if (aliasAdmin.toLowerCase() !== deployer.toLowerCase()) {
    throw new Error(`Alias admin mismatch: got=${aliasAdmin} want=${deployer}`);
  }
  log("getChainAdmin via alias ✓");

  // Resolve Interoperable Address through ENSIP-24 using alias
  const aliasDataCalldata = ENSIP_24_INTERFACE.encodeFunctionData(
    "data(bytes32,string)",
    [TEST_ALIAS_NAMEHASH, INTEROPERABLE_ADDRESS_DATA_KEY]
  );
  const aliasDataResponse: string = await resolverContract.resolve!(
    TEST_ALIAS_DNS_ENCODED,
    aliasDataCalldata
  );
  const [aliasCidBytes] = ENSIP_24_INTERFACE.decodeFunctionResult(
    "data(bytes32,string)",
    aliasDataResponse
  );
  if (hex(aliasCidBytes) !== INTEROPERABLE_ADDRESS_AS_HEX) {
    throw new Error(
      `Alias resolve data mismatch: got=${hex(
        aliasCidBytes
      )} want=${INTEROPERABLE_ADDRESS_AS_HEX}`
    );
  }
  log(`resolve(${TEST_ALIAS}.${SECOND_LEVEL_DOMAIN}.eth, data) ✓`);

  // Read address record through alias
  const aliasAddrCall = ADDR_INTERFACE.encodeFunctionData("addr(bytes32)", [
    TEST_ALIAS_LABELHASH,
  ]);
  const aliasAddrResponse: string = await resolverContract.resolve!(
    TEST_ALIAS_DNS_ENCODED,
    aliasAddrCall
  );
  const [aliasAddr] = ADDR_INTERFACE.decodeFunctionResult(
    "addr(bytes32)",
    aliasAddrResponse
  );
  if (aliasAddr.toLowerCase() !== TEST_RESOLUTION_ADDRESS.toLowerCase()) {
    throw new Error(
      `Alias addr mismatch`
    );
  }
  log(`resolve(${TEST_ALIAS}.${SECOND_LEVEL_DOMAIN}.eth, addr) ✓`);

  // Set text record through alias (should work since we own the canonical)
  section("Alias - Write through alias");
  const setTextViaAlias = castedContract.getFunction(
    "setText(bytes32,string,string)"
  );
  const aliasTextTx = await setTextViaAlias(
    TEST_ALIAS_LABELHASH,
    "description",
    TEST_DESCRIPTION_TEXT
  );
  const aliasTextReceipt = await aliasTextTx.wait();
  logEvents(aliasTextReceipt, castedContract);
  log("setText via alias ✓");

  // Verify the text record was set on canonical
  const textViaCanonical = await resolverContract.getText!(
    TEST_LABELHASH,
    "description"
  );
  if (textViaCanonical !== TEST_DESCRIPTION_TEXT) {
    throw new Error(
      `Text not set on canonical: got=${textViaCanonical} want='Set via alias'`
    );
  }
  log("Text record accessible via canonical ✓");

  // Also verify readable via alias
  const textViaAlias = await resolverContract.getText!(
    TEST_ALIAS_LABELHASH,
    "description"
  );
  if (textViaAlias !== TEST_DESCRIPTION_TEXT) {
    throw new Error(
      `Text not readable via alias`
    );
  }
  log("Text record accessible via alias ✓");

  //Remove alias
  const removeAliasTx = await resolverContract.removeAlias!(TEST_ALIAS);
  const removeAliasReceipt = await removeAliasTx.wait();
  logEvents(removeAliasReceipt, castedContract);

  // Verify alias is removed
  const removedCanonical = await resolverContract.getCanonicalLabelhash!(
    TEST_ALIAS_LABELHASH
  );
  if (
    removedCanonical !==
    "0x0000000000000000000000000000000000000000000000000000000000000000"
  ) {
    throw new Error(`Alias not removed: got=${removedCanonical}`);
  }
  log("Alias removed successfully ✓");

  // Verify reading via removed alias now returns empty (alias treated as its own labelhash)
  const removedAliasInteropAddr = await resolverContract.interoperableAddress!(
    TEST_ALIAS_LABELHASH
  );
  if (removedAliasInteropAddr !== "0x") {
    throw new Error(
      `Removed alias should return empty: got=${removedAliasInteropAddr}`
    );
  }
  log("Removed alias returns empty data ✓");

  // Discoverability tests
  section("Discoverability tests");

  // Test chainCount
  const count = await resolverContract.chainCount!();
  log("Chain count", count.toString());
  if (count !== 1n) {
    throw new Error(`Unexpected chain count: got=${count} want=1`);
  }
  log("chainCount ✓");

  // Test getChainAtIndex for the registered chain
  const [label, cName, interopAddr] = await resolverContract.getChainAtIndex!(0);
  log("Chain at index 0:", { label, chainName: cName, interopAddr });

  if (label !== TEST_LABEL) {
    throw new Error(`Unexpected label at index 0: got=${label} want=${TEST_LABEL}`);
  }
  if (cName !== TEST_CHAIN_NAME) {
    throw new Error(`Unexpected chainName at index 0: got=${cName} want=${TEST_CHAIN_NAME}`);
  }
  if (interopAddr !== INTEROPERABLE_ADDRESS_AS_HEX) {
    throw new Error(
      `Unexpected interoperableAddress at index 0: got=${interopAddr} want=${INTEROPERABLE_ADDRESS_AS_HEX}`
    );
  }
  log("getChainAtIndex(0) ✓");

  // Test getChainAtIndex with out-of-bounds index (should revert)
  try {
    await resolverContract.getChainAtIndex!(1);
    throw new Error("Expected revert for out-of-bounds index");
  } catch (e: any) {
    if (e.message === "Expected revert for out-of-bounds index") {
      throw e;
    }
    log("getChainAtIndex(1) correctly reverted ✓");
  }

  // Register a second chain to test multiple entries
  section("Register second chain for discoverability");
  await registerChain(castedContract, deployer, BASE_CHAIN);

  // Verify chainCount increased
  const count2 = await resolverContract.chainCount!();
  log("Chain count after second registration", count2.toString());
  if (count2 !== 2n) {
    throw new Error(`Unexpected chain count: got=${count2} want=2`);
  }
  log("chainCount after second registration ✓");

  // Verify getChainAtIndex(1) returns the second chain
  const [label2, cName2, interopAddr2] = await resolverContract.getChainAtIndex!(1);
  log("Chain at index 1:", { label: label2, chainName: cName2, interopAddr: interopAddr2 });

  if (label2 !== BASE_CHAIN.label) {
    throw new Error(`Unexpected label at index 1: got=${label2} want=${BASE_CHAIN.label}`);
  }
  if (cName2 !== BASE_CHAIN.chainName) {
    throw new Error(`Unexpected chainName at index 1: got=${cName2} want=${BASE_CHAIN.chainName}`);
  }
  if (interopAddr2 !== BASE_CHAIN.interoperableAddressHex) {
    throw new Error(
      `Unexpected interoperableAddress at index 1: got=${interopAddr2} want=${BASE_CHAIN.interoperableAddressHex}`
    );
  }
  log("getChainAtIndex(1) ✓");

  // Verify first chain is still accessible at index 0
  const [label0, cName0, interopAddr0] = await resolverContract.getChainAtIndex!(0);
  if (label0 !== TEST_LABEL || cName0 !== TEST_CHAIN_NAME) {
    throw new Error("First chain data changed unexpectedly");
  }
  log("First chain still at index 0 ✓");

  console.log("✓ All tests passed");

  await smith.shutdown();
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
