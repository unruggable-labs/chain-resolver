// Shared chain registration data
// Used by both tests and deployment scripts
// This file reads chain data from individual files in data/chains/
// Each chain is a separate JSON file named {label}.json

import { readdirSync, readFileSync } from "fs";
import { join, dirname } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const chainsDir = join(__dirname, "chains");

export interface ChainData {
  // The canonical label (e.g., "optimism")
  label: string;
  // The display name (e.g., "OP Mainnet")
  chainName: string;
  // The ERC-7930 interoperable address as hex string
  interoperableAddressHex: string;
  // Optional aliases that point to this chain (e.g., ["op"] for optimism)
  aliases?: string[];
  // Optional owner address - defaults to contract owner during registration
  owner?: string;
  // Optional text records
  textRecords?: Record<string, string>;
  contenthash?: string;
}

function loadChains(): ChainData[] {
  const files = readdirSync(chainsDir).filter(
    (f) => f.endsWith(".json") && !f.startsWith("_")
  );
  const chains: ChainData[] = [];

  for (const file of files) {
    const content = readFileSync(join(chainsDir, file), "utf8");
    const chain = JSON.parse(content) as ChainData;
    // Skip invalid entries
    if (chain.label && chain.label.trim() !== "") {
      chains.push(chain);
    }
  }

  return chains;
}

// List of Chains to register - loaded from data/chains/*.json
// Each chain submits a PR adding their own file (e.g., data/chains/mychain.json)
// Merging the PR = approval
export const CHAINS: ChainData[] = loadChains();

// Helper to get a chain by label
export function getChainByLabel(label: string): ChainData | undefined {
  return CHAINS.find((c) => c.label === label);
}

// Helper to get a chain by alias
export function getChainByAlias(alias: string): ChainData | undefined {
  return CHAINS.find((c) => c.aliases?.includes(alias));
}

// Helper to get all aliases across all chains
export function getAllAliases(): { alias: string; canonicalLabel: string }[] {
  const result: { alias: string; canonicalLabel: string }[] = [];
  for (const chain of CHAINS) {
    for (const alias of chain.aliases || []) {
      result.push({ alias, canonicalLabel: chain.label });
    }
  }
  return result;
}

