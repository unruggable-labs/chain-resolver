// Live demo of ChainResolver using viem
// Demonstrates forward and reverse resolution for optimism
// Usage: bun run examples/live-viem.ts

import {
  createPublicClient,
  http,
  keccak256,
  toBytes,
  namehash,
  encodeFunctionData,
  decodeFunctionResult,
  parseAbi,
  type Hex,
  type Address,
} from "viem";
import { mainnet, sepolia } from "viem/chains";
import {
  selectNetwork,
  validateNetwork,
  printConnectionInfo,
  printSummary,
  section,
  log,
  dnsEncode,
  INTEROPERABLE_ADDRESS_DATA_KEY,
  CHAIN_LABEL_PREFIX,
  OPTIMISM,
} from "./shared";
import { RESOLVER_ABI, TEXT_ABI, DATA_ABI } from "./abis";

// Parse human-readable ABIs for viem
const resolverAbi = parseAbi(RESOLVER_ABI);
const textAbi = parseAbi(TEXT_ABI);
const dataAbi = parseAbi(DATA_ABI);

// Map network config to viem chain
const CHAIN_MAP = {
  1: mainnet,
  11155111: sepolia,
} as const;

async function main() {
  const network = await selectNetwork();
  validateNetwork(network);
  printConnectionInfo(network);

  // Create viem public client
  const chain = CHAIN_MAP[network.chainId as keyof typeof CHAIN_MAP];
  const client = createPublicClient({
    chain,
    transport: http(network.rpc),
  });

  const proxyAddress = network.proxyAddress as Address;

  // Verify connection
  const chainCount = await client.readContract({
    address: proxyAddress,
    abi: resolverAbi,
    functionName: "chainCount",
  });
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
  const labelhash = keccak256(toBytes(OPTIMISM.label));
  log("Labelhash:", labelhash);

  const interopAddr = await client.readContract({
    address: proxyAddress,
    abi: resolverAbi,
    functionName: "interoperableAddress",
    args: [labelhash],
  });
  log("Interoperable Address:", interopAddr);

  if (interopAddr === OPTIMISM.interoperableAddressHex) {
    console.log("  ✅ Matches expected value!");
  } else if (interopAddr === "0x") {
    console.log("  ⚠️  Chain not registered yet");
  }

  // Method 2: Using ENSIP-10 resolve() with ENSIP-24 data()
  console.log("\n📤 Method 2: ENSIP-10 resolve() with ENSIP-24 data()");
  const ensName = `${OPTIMISM.label}.${SECOND_LEVEL_DOMAIN}`;
  const dnsEncodedName = dnsEncode(ensName);
  const nameNamehash = namehash(ensName);

  log("ENS name:", ensName);
  log("DNS-encoded:", dnsEncodedName);

  const dataCalldata = encodeFunctionData({
    abi: dataAbi,
    functionName: "data",
    args: [nameNamehash, INTEROPERABLE_ADDRESS_DATA_KEY],
  });

  const dataResponse = await client.readContract({
    address: proxyAddress,
    abi: resolverAbi,
    functionName: "resolve",
    args: [dnsEncodedName, dataCalldata],
  });

  const resolvedInteropAddr = decodeFunctionResult({
    abi: dataAbi,
    functionName: "data",
    data: dataResponse,
  });

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

  const resolvedLabel = await client.readContract({
    address: proxyAddress,
    abi: resolverAbi,
    functionName: "chainLabel",
    args: [OPTIMISM.interoperableAddressHex as Hex],
  });
  log("Chain label:", resolvedLabel || "(empty)");

  const resolvedChainName = await client.readContract({
    address: proxyAddress,
    abi: resolverAbi,
    functionName: "chainName",
    args: [OPTIMISM.interoperableAddressHex as Hex],
  });
  log("Chain name:", resolvedChainName || "(empty)");

  if (resolvedLabel === OPTIMISM.label && resolvedChainName === OPTIMISM.chainName) {
    console.log("  ✅ Both match expected values!");
  } else if (!resolvedLabel) {
    console.log("  ⚠️  Chain not registered yet");
  }

  // Method 2: Using ENSIP-10 resolve() with ENSIP-5 text()
  console.log("\n📤 Method 2: ENSIP-10 resolve() with ENSIP-5 text()");

  const reverseName = `reverse.${SECOND_LEVEL_DOMAIN}`;
  const reverseDnsEncoded = dnsEncode(reverseName);
  const reverseNamehash = namehash(reverseName);

  const reverseKey = `${CHAIN_LABEL_PREFIX}${OPTIMISM.interoperableAddressHex.replace(/^0x/, "")}`;

  log("Reverse name:", reverseName);
  log("Text key:", reverseKey);

  const textCalldata = encodeFunctionData({
    abi: textAbi,
    functionName: "text",
    args: [reverseNamehash, reverseKey],
  });

  const textResponse = await client.readContract({
    address: proxyAddress,
    abi: resolverAbi,
    functionName: "resolve",
    args: [reverseDnsEncoded, textCalldata],
  });

  const resolvedLabelViaText = decodeFunctionResult({
    abi: textAbi,
    functionName: "text",
    data: textResponse,
  });

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
