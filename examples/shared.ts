// Shared configuration and utilities for ChainResolver demos

import "dotenv/config";
import * as readline from "readline";

// Network configurations (loaded from environment variables)
export const NETWORKS = {
  sepolia: {
    name: "Sepolia",
    chainId: 11155111,
    rpcEnvVar: "SEPOLIA_RPC_URL",
    proxyEnvVar: "SEPOLIA_PROXY_ADDRESS",
    rpc: process.env.SEPOLIA_RPC_URL,
    proxyAddress: process.env.SEPOLIA_PROXY_ADDRESS,
    domain: "cid.eth",
  },
  mainnet: {
    name: "Ethereum Mainnet",
    chainId: 1,
    rpcEnvVar: "MAINNET_RPC_URL",
    proxyEnvVar: "MAINNET_PROXY_ADDRESS",
    rpc: process.env.MAINNET_RPC_URL,
    proxyAddress: process.env.MAINNET_PROXY_ADDRESS,
    domain: "on.eth",
  },
};

export type NetworkConfig = typeof NETWORKS.sepolia;

// Constants
export const INTEROPERABLE_ADDRESS_DATA_KEY = "interoperable-address";
export const CHAIN_LABEL_PREFIX = "chain-label:";

// Optimism chain data (for demo)
export const OPTIMISM = {
  label: "optimism",
  chainName: "OP Mainnet",
  interoperableAddressHex: "0x00010001010a00",
};

// Helper functions
export const section = (name: string) =>
  console.log(`\n${"=".repeat(50)}\n${name}\n${"=".repeat(50)}`);

export const log = (...args: any[]) => console.log("  →", ...args);

// Prompt user for input
export function askQuestion(rl: readline.Interface, question: string): Promise<string> {
  return new Promise((resolve) => {
    rl.question(question, (answer) => {
      resolve(answer.trim().toLowerCase());
    });
  });
}

// Select network interactively
export async function selectNetwork(): Promise<NetworkConfig> {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  console.log("\n🔗 ChainResolver Live Demo\n");
  console.log("Available networks:");
  console.log("  1. Sepolia (cid.eth)");
  console.log("  2. Mainnet (on.eth)");
  console.log("");

  const choice = await askQuestion(rl, "Select network (1 or 2): ");
  rl.close();

  if (choice === "1" || choice === "sepolia") {
    return NETWORKS.sepolia;
  } else if (choice === "2" || choice === "mainnet") {
    return NETWORKS.mainnet;
  } else {
    console.log("Invalid choice. Defaulting to Sepolia.");
    return NETWORKS.sepolia;
  }
}

// Validate required environment variables
export function validateNetwork(network: NetworkConfig): void {
  const missingVars: string[] = [];

  if (!network.rpc) {
    missingVars.push(network.rpcEnvVar);
  }
  if (!network.proxyAddress) {
    missingVars.push(network.proxyEnvVar);
  }

  if (missingVars.length > 0) {
    console.error(`\n❌ Missing required environment variables for ${network.name}:`);
    for (const varName of missingVars) {
      console.error(`   - ${varName}`);
    }
    console.error("\nPlease set these in your .env file. See .env.example for reference.");
    process.exit(1);
  }
}

// Print connection info
export function printConnectionInfo(network: NetworkConfig): void {
  console.log(`\n📡 Connecting to ${network.name}...`);
  console.log("Proxy address:", network.proxyAddress);
  console.log("Domain:", network.domain);
  console.log("RPC:", network.rpc);
}

// Print summary
export function printSummary(
  network: NetworkConfig,
  interopAddr: string,
  resolvedLabel: string,
  resolvedChainName: string
): void {
  section("SUMMARY");

  console.log(`\n Network: ${network.name} (${network.domain})`);

  console.log("\n Forward Resolution (label → address):");
  console.log(`   "${OPTIMISM.label}" → ${interopAddr || "(not registered)"}`);

  console.log("\n Reverse Resolution (address → label):");
  console.log(
    `   ${OPTIMISM.interoperableAddressHex} → "${resolvedLabel || "(not registered)"}" (${resolvedChainName || "N/A"})`
  );

  console.log("\n✅ Demo complete!\n");
}

// DNS encode a name
export function dnsEncode(name: string): `0x${string}` {
  const labels = name.split(".");
  let result = "";
  for (const label of labels) {
    const length = label.length;
    result += length.toString(16).padStart(2, "0");
    for (let i = 0; i < label.length; i++) {
      result += label.charCodeAt(i).toString(16).padStart(2, "0");
    }
  }
  result += "00"; // null terminator
  return `0x${result}`;
}

