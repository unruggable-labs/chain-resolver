// Shared chain registration data
// Used by both tests and deployment scripts

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
}

// List of Chains to register
export const CHAINS: ChainData[] = [
  {
    label: "optimism",
    chainName: "OP Mainnet",
    interoperableAddressHex: "0x00010001010a00",
    aliases: ["op"],
    textRecords: {
      //"avatar": "https://optimism.io/avatar.png",
      "description": "Optimism is a Layer 2 scaling solution for Ethereum.",
      "url": "https://optimism.io",
      "com.github": "https://github.com/ethereum-optimism",
      "com.x": "https://twitter.com/optimism",
    }
  },
  {
    label: "base",
    chainName: "Base",
    interoperableAddressHex: "0x00010001022105",
    aliases: [],
  },
  {
    label: "arbitrum",
    chainName: "Arbitrum One",
    interoperableAddressHex: "0x0001000102a4b1",
    aliases: ["arb", "arb1"],
  },
];

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

