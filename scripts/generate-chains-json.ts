import axios from "axios";
import { writeFileSync, mkdirSync, existsSync, readFileSync } from "fs";
import { join, extname } from "path";
import { InteropAddressProvider } from "@wonderland/interop-addresses";
import * as viemChains from "viem/chains";

type RoutescanSocialProfileItem = {
  type: string;
  value: string;
};

type RoutescanSocialProfile = {
  items?: RoutescanSocialProfileItem[];
};

type RoutescanChain = {
  chainId: string | number; // Routescan returns as string
  evmChainId?: string | number;
  name: string;
  logo?: string;
  socialProfile?: RoutescanSocialProfile;
  // There are more fields, but we only grab what we need for now
};

type RoutescanResponse = {
  items: RoutescanChain[];
};

type ChainIdMini = {
  chainId: number;
  name: string;
  shortName?: string;
  infoURL?: string;
};

type ChainIdMiniResponse = ChainIdMini[];

// Viem chain type - we'll extract id, name, and testnet status from viem chains
type ViemChain = {
  id: number;
  name: string;
  testnet?: boolean;
};

type ChainOverrides = {
  label?: string;
  aliases?: string[];
  textRecords?: Record<string, string>;
};

type OverridesFile = {
  [chainId: string]: ChainOverrides;
};

type OutputChain = {
  label: string;
  chainName: string;
  interoperableAddressHex: string;
  aliases: string[];
  textRecords: Record<string, string>;
};

const ROUTESCAN_MAINNETS =
  "https://api.routescan.io/v2/network/mainnet/evm/all/blockchains";
const ROUTESCAN_TESTNETS =
  "https://api.routescan.io/v2/network/testnet/evm/all/blockchains";
const CHAINS_MINI = "https://chainid.network/chains_mini.json";
const AVATARS_DIR = "images/avatars";

// Normalize a label to be lowercase and use hyphens for separators
function normalizeLabel(value: string | undefined | null): string | undefined {
  if (!value) return undefined;
  return value
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-") // Replace non-alphanumeric with hyphens
    .replace(/-+/g, "-") // Collapse multiple hyphens
    .replace(/^-|-$/g, ""); // Trim hyphens from start/end
}

// Helper function to download and save avatar image
async function downloadAvatar(
  logoUrl: string,
  label: string
): Promise<string | null> {
  try {
    // Skip generic Routescan fallback logos
    if (logoUrl.includes("routescan-new")) {
      return null;
    }

    // Ensure avatars directory exists
    if (!existsSync(AVATARS_DIR)) {
      mkdirSync(AVATARS_DIR, { recursive: true });
    }

    // Download the image
    const response = await axios.get(logoUrl, {
      responseType: "arraybuffer",
      timeout: 10000, // 10 second timeout
    });

    // Determine file extension from URL or content-type
    let ext = extname(new URL(logoUrl).pathname).toLowerCase();
    if (!ext || ext === "") {
      // Try to get from content-type
      const contentType = response.headers["content-type"];
      if (contentType?.includes("image/png")) {
        ext = ".png";
      } else if (contentType?.includes("image/jpeg") || contentType?.includes("image/jpg")) {
        ext = ".jpg";
      } else if (contentType?.includes("image/svg")) {
        ext = ".svg";
      } else if (contentType?.includes("image/webp")) {
        ext = ".webp";
      } else {
        ext = ".png"; // default fallback
      }
    }

    // Sanitize label for filename
    const sanitizedLabel = label.replace(/[^a-z0-9-]/gi, "-");
    const filename = `${sanitizedLabel}-avatar${ext}`;
    const filepath = join(AVATARS_DIR, filename);

    // Write the file
    writeFileSync(filepath, Buffer.from(response.data));

    // Return the relative path for the textRecord
    return `${AVATARS_DIR}/${filename}`;
  } catch (error) {
    console.warn(`Failed to download avatar for ${label} from ${logoUrl}:`, error);
    return null;
  }
}

async function main() {
  console.log("Fetching Routescan and chainid data...");

  // Build viem chains map by chainId, preferring mainnet over testnet
  // Also track which chainIds have duplicates
  const viemChainsMap = new Map<number, ViemChain>();
  const viemChainCounts = new Map<number, number>(); // Track how many chains exist per id
  for (const [key, chain] of Object.entries(viemChains)) {
    // Skip non-chain exports (like defineChain function)
    if (chain && typeof chain === "object" && "id" in chain && "name" in chain) {
      const viemChain = chain as ViemChain;
      const isTestnet = viemChain.testnet === true;
      
      // Count chains with this id
      const currentCount = viemChainCounts.get(viemChain.id) || 0;
      viemChainCounts.set(viemChain.id, currentCount + 1);
      
      // Check if we already have a chain with this id
      const existing = viemChainsMap.get(viemChain.id);
      if (existing) {
        const existingIsTestnet = existing.testnet === true;
        // Only replace if: existing is testnet AND new is mainnet
        if (existingIsTestnet && !isTestnet) {
          viemChainsMap.set(viemChain.id, viemChain);
        }
        // Otherwise keep the existing one (mainnet stays, or first testnet stays if both are testnet)
      } else {
        // No existing chain, just add it
        viemChainsMap.set(viemChain.id, viemChain);
      }
    }
  }

  // Load overrides if they exist
  const overridesPath = "data/overrides.json";
  let overrides: OverridesFile = {};
  if (existsSync(overridesPath)) {
    try {
      const overridesContent = readFileSync(overridesPath, "utf-8");
      overrides = JSON.parse(overridesContent);
    } catch (error) {
      console.warn(`Failed to read overrides.json:`, error);
    }
  }

  const [mainnetsRes, testnetsRes, chainsMiniRes] = await Promise.all([
    axios.get<RoutescanResponse>(ROUTESCAN_MAINNETS),
    axios.get<RoutescanResponse>(ROUTESCAN_TESTNETS),
    axios.get<ChainIdMiniResponse>(CHAINS_MINI),
  ]);

  const mainnetChains = mainnetsRes.data.items;
  const testnetChains = testnetsRes.data.items;
  const routescanChains = [...mainnetChains, ...testnetChains];
  const chainsMini = chainsMiniRes.data;

  // Build a quick lookup of which chainIds are testnets
  const testnetIds = new Set<number>();
  for (const r of testnetChains) {
    const id = Number(r.evmChainId ?? r.chainId);
    if (!Number.isNaN(id)) {
      testnetIds.add(id);
    }
  }

  const chainIdMap = new Map<number, ChainIdMini>();
  for (const c of chainsMini) {
    chainIdMap.set(c.chainId, c);
  }

  const output: OutputChain[] = [];

  for (const r of routescanChains) {
    // Routescan chainId can be string or number, prefer evmChainId if available
    const chainId = Number(r.evmChainId ?? r.chainId);
    
    const mini = chainIdMap.get(chainId);
    const viemChain = viemChainsMap.get(chainId);
    const shortName = mini?.shortName;
    
    // Build label candidates and normalize them all
    // Priority: viem chain name (normalized) > shortName > mini name > routescan name
    const labelCandidates = [
      viemChain?.name, // First priority: viem chain name
      shortName,
      mini?.name,
      r.name,
    ];
    
    // Find first valid normalized candidate
    // normalizeLabel already lowercases, so all labels will be lowercase
    let label: string = `chain-${chainId}`.toLowerCase(); // Default fallback (lowercased)
    for (const candidate of labelCandidates) {
      const normalized = normalizeLabel(candidate);
      if (normalized && normalized.length > 0) {
        label = normalized; // normalizeLabel already lowercases
        break;
      }
    }
    
    // Final safety check: ensure label is always lowercase
    label = label.toLowerCase();

    // Use viem chain name if available, otherwise fallback to other sources
    const chainName = viemChain?.name ?? mini?.name ?? r.name ?? label;

    // Use InteropAddressProvider.humanReadableToBinary with a CAIP-10 style string.
    // For chain-level only, we use "eip155:<chainId>" (no account address).
    const humanReadable = `@eip155:${chainId}`;
    const interoperableAddressHex =
      await InteropAddressProvider.humanReadableToBinary(humanReadable);

    const aliases: string[] = [];
    // Helper to add alias, checking against current label
    const addAlias = (value: string | undefined, currentLabel?: string) => {
      if (!value) return;
      const labelToCheck = (currentLabel ?? label).toLowerCase();
      const lower = value.toLowerCase();
      // Don't duplicate the label itself, and avoid duplicates in aliases
      if (lower === labelToCheck) return;
      if (!aliases.includes(lower)) {
        aliases.push(lower);
      }
    };

    // shortName (from chains_mini) as alias - only if no duplicate viem chains
    const hasDuplicateViemChains = (viemChainCounts.get(chainId) || 0) > 1;
    if (!hasDuplicateViemChains) {
      addAlias(shortName);
    }

    const textRecords: Record<string, string> = {};
    textRecords["chainId"] = String(chainId);
    if (testnetIds.has(chainId)) {
      textRecords["isTestnet"] = "true";
    }
    
    // Extract URL from Routescan socialProfile "url" type, fallback to mini infoURL
    let urlFound = false;
    if (r.socialProfile?.items) {
      for (const item of r.socialProfile.items) {
        if (item.type === "url" && item.value) {
          textRecords["url"] = item.value;
          urlFound = true;
          break;
        }
      }
    }
    if (!urlFound && mini?.infoURL) {
      textRecords["url"] = mini.infoURL;
    }
    if (r.logo) {
      // Download and save avatar locally
      const localAvatarPath = await downloadAvatar(r.logo, label);
      if (localAvatarPath) {
        textRecords["avatar"] = localAvatarPath;
      }
    }

    // Extract social profile data
    if (r.socialProfile?.items) {
      for (const item of r.socialProfile.items) {
        if (item.type === "twitter" && item.value) {
          textRecords["com.x"] = item.value;
        } else if (item.type === "github" && item.value) {
          textRecords["com.github"] = item.value;
        }
      }
    }

    // Apply overrides if they exist for this chainId
    const chainIdStr = String(chainId);
    const override = overrides[chainIdStr];
    if (override) {
      if (override.label) {
        // normalizeLabel already lowercases, but ensure we always have lowercase
        const overrideLabel = normalizeLabel(override.label);
        label = overrideLabel || label;
        // Ensure label is always lowercase (normalizeLabel should handle this, but be explicit)
        label = label.toLowerCase();
      }
      if (override.aliases) {
        // Merge override aliases (normalized) with existing aliases
        const overrideAliases = override.aliases
          .map((a) => normalizeLabel(a))
          .filter((a): a is string => a !== undefined && a.length > 0 && a !== label.toLowerCase());
        for (const alias of overrideAliases) {
          if (!aliases.includes(alias)) {
            aliases.push(alias);
          }
        }
      }
      if (override.textRecords) {
        // Merge override textRecords with existing ones
        Object.assign(textRecords, override.textRecords);
      }
    }

    // Add normalized viem chain name as alias (after overrides, checking against final label)
    // This ensures viem names are included even if overrides change the label
    if (viemChain?.name) {
      const normalizedViemName = normalizeLabel(viemChain.name);
      if (normalizedViemName && normalizedViemName !== label.toLowerCase()) {
        // Use addAlias with current label to ensure proper check
        addAlias(normalizedViemName, label);
      }
    }

    output.push({
      label,
      chainName,
      interoperableAddressHex,
      aliases,
      textRecords,
    });
  }

  // Sort by chainId for stability
  output.sort((a, b) => {
    const idA = Number(a.textRecords["chainId"]);
    const idB = Number(b.textRecords["chainId"]);
    return idA - idB;
  });

  // Fix duplicate labels by adding -testnet suffix to testnets
  const labelCountMap = new Map<string, OutputChain[]>();
  for (const chain of output) {
    const labelLower = chain.label.toLowerCase();
    if (!labelCountMap.has(labelLower)) {
      labelCountMap.set(labelLower, []);
    }
    labelCountMap.get(labelLower)!.push(chain);
  }

  // Find testnets with duplicate labels and add -testnet suffix
  for (const [labelLower, chains] of labelCountMap.entries()) {
    if (chains.length > 1) {
      // Check if there's a mix of mainnet and testnet
      const testnetChains = chains.filter((c) =>
        testnetIds.has(Number(c.textRecords["chainId"]))
      );
      const mainnetChains = chains.filter(
        (c) => !testnetIds.has(Number(c.textRecords["chainId"]))
      );

      // If we have both mainnet and testnet with same label, add -testnet to testnets
      if (testnetChains.length > 0 && mainnetChains.length > 0) {
        for (const chain of testnetChains) {
          const currentLabelLower = chain.label.toLowerCase();
          if (!currentLabelLower.endsWith("-testnet")) {
            chain.label = `${currentLabelLower}-testnet`;
            console.log(
              `Fixed duplicate label: ChainId ${chain.textRecords["chainId"]} (${chain.chainName}) -> ${chain.label}`
            );
          }
        }
      }
    }
  }

  // Sanity checks
  console.log("\nRunning sanity checks...");
  let hasErrors = false;

  // Check for duplicate chainIds
  const chainIdCheckMap = new Map<number, OutputChain[]>();
  for (const chain of output) {
    const chainId = Number(chain.textRecords["chainId"]);
    if (!chainIdCheckMap.has(chainId)) {
      chainIdCheckMap.set(chainId, []);
    }
    chainIdCheckMap.get(chainId)!.push(chain);
  }
  const duplicateChainIds = Array.from(chainIdCheckMap.entries()).filter(
    ([, chains]) => chains.length > 1
  );
  if (duplicateChainIds.length > 0) {
    console.error(`\n❌ ERROR: Found ${duplicateChainIds.length} duplicate chainId(s):`);
    for (const [chainId, chains] of duplicateChainIds) {
      console.error(`  ChainId ${chainId} appears ${chains.length} times:`);
      for (const chain of chains) {
        console.error(`    - ${chain.label} (${chain.chainName})`);
      }
    }
    hasErrors = true;
  }

  // Check for duplicate labels
  const labelMap = new Map<string, OutputChain[]>();
  for (const chain of output) {
    const label = chain.label.toLowerCase();
    if (!labelMap.has(label)) {
      labelMap.set(label, []);
    }
    labelMap.get(label)!.push(chain);
  }
  const duplicateLabels = Array.from(labelMap.entries()).filter(
    ([, chains]) => chains.length > 1
  );
  if (duplicateLabels.length > 0) {
    console.error(`\n❌ ERROR: Found ${duplicateLabels.length} duplicate label(s):`);
    for (const [label, chains] of duplicateLabels) {
      console.error(`  Label "${label}" appears ${chains.length} times:`);
      for (const chain of chains) {
        const chainId = chain.textRecords["chainId"];
        console.error(`    - ChainId ${chainId} (${chain.chainName})`);
      }
    }
    hasErrors = true;
  }

  // Check for duplicate aliases across chains
  const aliasMap = new Map<string, OutputChain[]>();
  for (const chain of output) {
    for (const alias of chain.aliases) {
      const aliasLower = alias.toLowerCase();
      if (!aliasMap.has(aliasLower)) {
        aliasMap.set(aliasLower, []);
      }
      aliasMap.get(aliasLower)!.push(chain);
    }
  }
  const duplicateAliases = Array.from(aliasMap.entries()).filter(
    ([, chains]) => chains.length > 1
  );
  if (duplicateAliases.length > 0) {
    console.error(`\n❌ ERROR: Found ${duplicateAliases.length} duplicate alias(es):`);
    for (const [alias, chains] of duplicateAliases) {
      console.error(`  Alias "${alias}" appears in ${chains.length} chain(s):`);
      for (const chain of chains) {
        const chainId = chain.textRecords["chainId"];
        console.error(`    - ChainId ${chainId}: ${chain.label} (${chain.chainName})`);
      }
    }
    hasErrors = true;
  }

  // Check for aliases that match labels of other chains
  const allLabels = new Set(output.map((c) => c.label.toLowerCase()));
  for (const chain of output) {
    for (const alias of chain.aliases) {
      const aliasLower = alias.toLowerCase();
      if (allLabels.has(aliasLower)) {
        const conflictingChain = output.find(
          (c) => c.label.toLowerCase() === aliasLower
        );
        if (conflictingChain && conflictingChain !== chain) {
          console.error(
            `\n⚠️  WARNING: ChainId ${chain.textRecords["chainId"]} (${chain.label}) has alias "${alias}" which conflicts with label of ChainId ${conflictingChain.textRecords["chainId"]} (${conflictingChain.label})`
          );
        }
      }
    }
  }

  if (hasErrors) {
    console.error("\n❌ Sanity checks failed! Please fix the errors above.");
    process.exit(1);
  } else {
    console.log("✅ All sanity checks passed!");
  }

  const outPath = "data/chains.generated.json";
  writeFileSync(outPath, JSON.stringify(output, null, 2));
  console.log(`\nWrote ${output.length} chains to ${outPath}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});


