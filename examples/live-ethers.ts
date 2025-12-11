// Live demo of ChainResolver using ethers
// Demonstrates forward and reverse resolution for optimism
// Usage: bun run examples/live-ethers.ts

import * as ethers from "ethers";
import { JsonRpcProvider, Contract, Interface, dnsEncode, namehash, hexlify } from "ethers";
import {
  selectNetwork,
  validateNetwork,
  printConnectionInfo,
  printSummary,
  section,
  log,
  INTEROPERABLE_ADDRESS_DATA_KEY,
  CHAIN_LABEL_PREFIX,
  OPTIMISM,
} from "./shared";
import { RESOLVER_ABI, TEXT_ABI, DATA_ABI } from "./abis";

// ENSIP interfaces for encoding calldata
const ENSIP_5_INTERFACE = new Interface(TEXT_ABI);
const ENSIP_24_INTERFACE = new Interface(DATA_ABI);

async function main() {
  const network = await selectNetwork();
  validateNetwork(network);
  printConnectionInfo(network);

  // Connect to network
  const provider = new JsonRpcProvider(network.rpc!);
  const resolver = new Contract(network.proxyAddress!, [...RESOLVER_ABI], provider);

  // Verify connection
  const chainCount = await resolver.chainCount!();
  console.log("Registered chains:", chainCount.toString());

  const SECOND_LEVEL_DOMAIN = network.domain;

  // ============================================================
  // FORWARD RESOLUTION
  // ============================================================
  section("FORWARD RESOLUTION: optimism → Interoperable Address");

  console.log("\n📥 Input:");
  log(`Chain label: "${OPTIMISM.label}"`);

  // Method 1: Using the direct getter
  console.log("\n📤 Method 1: Direct getter (interoperableAddress)");
  const labelhash = ethers.keccak256(ethers.toUtf8Bytes(OPTIMISM.label));
  log("Labelhash:", labelhash);

  const interopAddr = await resolver.interoperableAddress!(labelhash);
  log("Interoperable Address:", interopAddr);

  if (interopAddr === OPTIMISM.interoperableAddressHex) {
    console.log("  ✅ Matches expected value!");
  } else if (interopAddr === "0x") {
    console.log("  ⚠️  Chain not registered yet");
  }

  // Method 2: Using ENSIP-10 resolve() with ENSIP-24 data()
  console.log("\n📤 Method 2: ENSIP-10 resolve() with ENSIP-24 data()");
  const ensName = `${OPTIMISM.label}.${SECOND_LEVEL_DOMAIN}`;
  const dnsEncodedName = dnsEncode(ensName, 255);
  const nameNamehash = namehash(ensName);

  log("ENS name:", ensName);
  log("DNS-encoded:", hexlify(dnsEncodedName));

  const dataCalldata = ENSIP_24_INTERFACE.encodeFunctionData("data(bytes32,string)", [
    nameNamehash,
    INTEROPERABLE_ADDRESS_DATA_KEY,
  ]);

  const dataResponse = await resolver.resolve!(dnsEncodedName, dataCalldata);
  const [resolvedInteropAddr] = ENSIP_24_INTERFACE.decodeFunctionResult(
    "data(bytes32,string)",
    dataResponse
  );

  log("Resolved Interoperable Address:", resolvedInteropAddr);

  if (resolvedInteropAddr === OPTIMISM.interoperableAddressHex) {
    console.log("  ✅ Matches expected value!");
  } else if (resolvedInteropAddr === "0x") {
    console.log("  ⚠️  Chain not registered yet");
  }

  // ============================================================
  // REVERSE RESOLUTION
  // ============================================================
  section("REVERSE RESOLUTION: Interoperable Address → optimism");

  console.log("\n📥 Input:");
  log(`Interoperable Address: ${OPTIMISM.interoperableAddressHex}`);

  // Method 1: Using direct getters
  console.log("\n📤 Method 1: Direct getters (chainLabel, chainName)");

  const interopAddrBytes = ethers.getBytes(OPTIMISM.interoperableAddressHex);

  const resolvedLabel = await resolver.chainLabel!(interopAddrBytes);
  log("Chain label:", resolvedLabel || "(empty)");

  const resolvedChainName = await resolver.chainName!(interopAddrBytes);
  log("Chain name:", resolvedChainName || "(empty)");

  if (resolvedLabel === OPTIMISM.label && resolvedChainName === OPTIMISM.chainName) {
    console.log("  ✅ Both match expected values!");
  } else if (!resolvedLabel) {
    console.log("  ⚠️  Chain not registered yet");
  }

  // Method 2: Using ENSIP-10 resolve() with ENSIP-5 text()
  console.log("\n📤 Method 2: ENSIP-10 resolve() with ENSIP-5 text()");

  const reverseName = `reverse.${SECOND_LEVEL_DOMAIN}`;
  const reverseDnsEncoded = dnsEncode(reverseName, 255);
  const reverseNamehash = namehash(reverseName);

  const reverseKey = `${CHAIN_LABEL_PREFIX}${OPTIMISM.interoperableAddressHex.replace(/^0x/, "")}`;

  log("Reverse name:", reverseName);
  log("Text key:", reverseKey);

  const textCalldata = ENSIP_5_INTERFACE.encodeFunctionData("text(bytes32,string)", [
    reverseNamehash,
    reverseKey,
  ]);

  const textResponse = await resolver.resolve!(reverseDnsEncoded, textCalldata);
  const [resolvedLabelViaText] = ENSIP_5_INTERFACE.decodeFunctionResult(
    "text(bytes32,string)",
    textResponse
  );

  log("Resolved chain label:", resolvedLabelViaText || "(empty)");

  if (resolvedLabelViaText === OPTIMISM.label) {
    console.log("  ✅ Matches expected value!");
  } else if (!resolvedLabelViaText) {
    console.log("  ⚠️  Chain not registered yet");
  }

  // ============================================================
  // SUMMARY
  // ============================================================
  printSummary(network, interopAddr, resolvedLabel, resolvedChainName);
}

main().catch((e) => {
  console.error("Error:", e.message || e);
  process.exit(1);
});
