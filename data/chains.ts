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
  contenthash?: string;
}

// List of Chains to register
export const CHAINS: ChainData[] = [
  {
    label: "optimism",
    chainName: "OP Mainnet",
    interoperableAddressHex: "0x00010000010a00",
    aliases: ["op", "opt"],
    textRecords: {
      "avatar": "images/optimism-avatar.png",
      "header": "images/optimism-header.png",
      "description": "Optimism is a Layer 2 scaling solution for Ethereum.",
      "email": "hello@optimism.io",
      "mail": "123 Optimistic, Rollup, L2 123",
      "notice": "This is a notice",
      "keywords": "optimism, rollup, l2",
      "location": "New York, NY",
      "phone": "+1234567890",
      "url": "https://optimism.io",
      "com.github": "https://github.com/ethereum-optimism",
      "com.x": "https://twitter.com/optimism",
    },
    //contenthash: "0x", //reset to default
  },
  {
    label: "base",
    chainName: "Base",
    interoperableAddressHex: "0x0001000002210500",
    aliases: [],
    textRecords: {
      "avatar": "images/base-avatar.png",
      "header": "images/base-header.png",
      "description": "Base is a Layer 2 scaling solution for Ethereum from Coinbase.",
      "email": "hello@base.org",
      "mail": "123 Base, L2 123",
      //"notice": "This is a notice",
      "keywords": "base, l2, coinbase",
      "url": "https://base.org",
      "com.github": "https://github.com/base-org",
      "com.x": "https://twitter.com/base",
    },
  },
  {
    label: "arbitrum",
    chainName: "Arbitrum One",
    interoperableAddressHex: "0x0001000002a4b100",
    aliases: ["arb", "arb1"],
    textRecords: {
      "avatar": "images/arbitrum-avatar.png",
      "header": "images/arbitrum-header.png",
      "description": "Arbitrum is an Optimistic Layer 2 scaling solution for Ethereum.",
      "email": "hello@arbitrum.org",
      "mail": "123 Arbitrum, L2 123",
      "keywords": "arbitrum, optimistic, l2",
      "url": "https://arbitrum.org",
      "com.github": "https://github.com/arbitrum",
      "com.x": "https://twitter.com/arbitrum",
    },
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

