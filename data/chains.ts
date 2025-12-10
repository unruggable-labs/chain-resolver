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
}

// List of Chains to register
export const CHAINS: ChainData[] = [
  {
    label: "optimism",
    chainName: "OP Mainnet",
    interoperableAddressHex: "0x00010001010a00",
    aliases: ["op"],
  },
  {
    label: "base",
    chainName: "Base",
    interoperableAddressHex: "0x000100012105",
    aliases: [],
  },
  {
    label: "arbitrum",
    chainName: "Arbitrum One",
    interoperableAddressHex: "0x0001000142a91cfd",
    aliases: ["arb", "arb1"],
  },
 /* {
    label: "zora",
    chainName: "Zora",
    interoperableAddressHex: "0x000100076adf1edd",
    aliases: [],
  },
  {
    label: "mode",
    chainName: "Mode",
    interoperableAddressHex: "0x0001000834d2f4b5",
    aliases: [],
  },
  {
    label: "fraxtal",
    chainName: "Fraxtal",
    interoperableAddressHex: "0x000100fc",
    aliases: ["frax"],
  },
  {
    label: "worldchain",
    chainName: "World Chain",
    interoperableAddressHex: "0x000100480",
    aliases: ["world", "wld"],
  },
  {
    label: "ink",
    chainName: "Ink",
    interoperableAddressHex: "0x0001b9f1",
    aliases: [],
  },
  {
    label: "unichain",
    chainName: "Unichain",
    interoperableAddressHex: "0x00013054d1",
    aliases: ["uni"],
  },
  {
    label: "soneium",
    chainName: "Soneium",
    interoperableAddressHex: "0x00017648",
    aliases: [],
  },*/
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

