// Register chains from shared data to deployed ChainResolver proxy
// Usage: bun run deploy/RegisterChains.ts

import "dotenv/config";
import { init } from "./libs/init.ts";
import {
  initSmith,
  shutdownSmith,
  loadDeployment,
} from "./libs/utils.ts";
import { askQuestion, promptContinueOrExit } from "../shared/utils.ts";
import { RESOLVER_ABI } from "../shared/abis.ts";
import { Contract, keccak256, toUtf8Bytes, getBytes } from "ethers";
import { CHAINS, getAllAliases } from "../data/chains.ts";
import { existsSync, readFileSync } from "fs";
import { join, basename } from "path";

// Image keys that should be uploaded to IPFS if they're local file paths
const IMAGE_KEYS = ["avatar", "header"];

// Shared website contenthash (IPFS CID) - set for all chains
const WEBSITE_CONTENTHASH = "bafkreiefxr2ca3q6zveqejonezevph4h57m5q657t3dvfcfa7zvzliojvm";

/**
 * Check if a value looks like a local file path
 */
function isLocalFilePath(value: string): boolean {
  // Skip if it's already a URL
  if (value.startsWith("http://") || value.startsWith("https://") || value.startsWith("ipfs://")) {
    return false;
  }
  // Check if it looks like a file path and exists
  const fullPath = value.startsWith("/") ? value : join(process.cwd(), value);
  return existsSync(fullPath);
}

/**
 * Upload a file to Pinata IPFS and return the ipfs:// URL
 * Requires PINATA_JWT environment variable
 */
async function uploadToPinata(filePath: string): Promise<string> {
  const token = process.env.PINATA_JWT;
  if (!token) {
    throw new Error("PINATA_JWT environment variable not set. Get one at https://pinata.cloud");
  }

  const fullPath = filePath.startsWith("/") ? filePath : join(process.cwd(), filePath);
  const fileContent = readFileSync(fullPath);
  const fileName = basename(fullPath);

  console.log(`    Uploading ${fileName} to Pinata...`);

  // Create form data with the file
  const formData = new FormData();
  const blob = new Blob([fileContent]);
  formData.append("file", blob, fileName);

  // Optional: add metadata
  const metadata = JSON.stringify({ name: fileName });
  formData.append("pinataMetadata", metadata);

  const response = await fetch("https://api.pinata.cloud/pinning/pinFileToIPFS", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
    },
    body: formData,
  });

  if (!response.ok) {
    const error = await response.text();
    throw new Error(`Pinata upload failed: ${response.status} ${error}`);
  }

  const result = await response.json() as { IpfsHash: string };
  const ipfsUrl = `ipfs://${result.IpfsHash}`;
  console.log(`    ✓ Uploaded: ${ipfsUrl}`);
  
  return ipfsUrl;
}

/**
 * Find local image files in text records that could be uploaded
 */
function findLocalImages(textRecords: Record<string, string>): { key: string; path: string }[] {
  const localImages: { key: string; path: string }[] = [];
  for (const [key, value] of Object.entries(textRecords)) {
    if (IMAGE_KEYS.includes(key) && isLocalFilePath(value)) {
      localImages.push({ key, path: value });
    }
  }
  return localImages;
}

/**
 * Process text records, optionally uploading local image files to IPFS via Pinata
 * @param textRecords The text records to process
 * @param imagesToUpload List of images to upload (already confirmed by user)
 */
async function processTextRecords(
  textRecords: Record<string, string>,
  imagesToUpload: { key: string; path: string }[]
): Promise<Record<string, string>> {
  const processed: Record<string, string> = {};
  const uploadKeys = new Set(imagesToUpload.map((i) => i.key));

  for (const [key, value] of Object.entries(textRecords)) {
    if (uploadKeys.has(key)) {
      try {
        processed[key] = await uploadToPinata(value);
      } catch (e: any) {
        console.warn(`    ⚠️  Failed to upload ${key}: ${e.message}`);
        console.warn(`    Using original value: ${value}`);
        processed[key] = value;
      }
    } else {
      processed[key] = value;
    }
  }

  return processed;
}

// RESOLVER_ABI imported from shared/abis.ts

async function main() {
  const { chainInfo, privateKey } = await init();

  console.log("\n=== Chain Registration ===\n");
  console.log("Network:", chainInfo.name, `(${chainInfo.id})`);

  const { deployerWallet, smith, rl } = await initSmith(
    chainInfo.name,
    privateKey
  );

  if (!deployerWallet?.provider) {
    throw new Error("No valid deployment wallet");
  }

  try {
    // Find the deployed proxy
    let proxyAddress: string | undefined;

    // Try to load from deployment file
    try {
      const proxyDep = await loadDeployment(chainInfo.id, "[Proxy]ERC1967Proxy");
      const addr = proxyDep.target as string;
      const code = await deployerWallet.provider.getCode(addr);
      if (code && code !== "0x") {
        proxyAddress = addr;
        console.log("Found proxy from deployment file:", proxyAddress);
      }
    } catch {}

    // Try environment variable
    if (!proxyAddress) {
      const envAddr = process.env.CHAIN_RESOLVER_PROXY?.trim();
      if (envAddr) {
        const code = await deployerWallet.provider.getCode(envAddr);
        if (code && code !== "0x") {
          proxyAddress = envAddr;
          console.log("Found proxy from env:", proxyAddress);
        }
      }
    }

    // Prompt for address
    if (!proxyAddress) {
      proxyAddress = (await askQuestion(rl, "Enter ChainResolver proxy address: ")).trim();
    }

    if (!proxyAddress) {
      console.error("Proxy address is required.");
      process.exit(1);
    }

    const resolver = new Contract(proxyAddress, RESOLVER_ABI, deployerWallet);

    // Verify connection
    const owner = await resolver.owner!();
    const chainCount = await resolver.chainCount!();
    console.log("\nProxy address:", proxyAddress);
    console.log("Contract owner:", owner);
    console.log("Current chain count:", chainCount.toString());
    console.log("Caller:", deployerWallet.address);

    if (owner.toLowerCase() !== deployerWallet.address.toLowerCase()) {
      console.warn("\n⚠️  Warning: You are not the contract owner. Registration will fail.");
    }

    // Check registration status for all chains
    console.log(`\nChecking ${CHAINS.length} chains...`);
    const registeredChains: typeof CHAINS = [];
    const unregisteredChains: typeof CHAINS = [];

    for (const chain of CHAINS) {
      const labelhash = keccak256(toUtf8Bytes(chain.label));
      const existingAdmin = await resolver.getChainAdmin!(labelhash).catch(() => null);
      const isRegistered = existingAdmin && existingAdmin !== "0x0000000000000000000000000000000000000000";
      
      if (isRegistered) {
        registeredChains.push(chain);
      } else {
        unregisteredChains.push(chain);
      }
    }

    // Show status
    if (registeredChains.length > 0) {
      console.log(`\n✓ Already registered (${registeredChains.length}):`);
      for (const chain of registeredChains) {
        console.log(`  - ${chain.label}: ${chain.chainName}`);
      }
    }

    if (unregisteredChains.length > 0) {
      console.log(`\n○ Not registered (${unregisteredChains.length}):`);
      for (const chain of unregisteredChains) {
        const aliasStr = chain.aliases?.length ? ` (aliases: ${chain.aliases.join(", ")})` : "";
        console.log(`  - ${chain.label}: ${chain.chainName}${aliasStr}`);
      }
    } else {
      console.log("\nAll chains are already registered.");
    }

    // Register chains
    let chainsToRegister: typeof CHAINS = [];

    if (unregisteredChains.length > 0) {
      const shouldRegisterAll = await promptContinueOrExit(
        rl,
        `\nRegister all ${unregisteredChains.length} unregistered chains? (y/n)`
      );

      if (shouldRegisterAll) {
        chainsToRegister = unregisteredChains;
      } else {
        // Allow specifying specific labels
        const labelsInput = (await askQuestion(
          rl,
          "Enter label(s) to register (comma-separated, or empty to skip): "
        )).trim();

        if (labelsInput) {
          const requestedLabels = labelsInput.split(",").map((l) => l.trim().toLowerCase());
          
          for (const label of requestedLabels) {
            const chain = CHAINS.find((c) => c.label.toLowerCase() === label);
            if (!chain) {
              console.warn(`⚠️  Unknown label: ${label}`);
              continue;
            }
            
            const isAlreadyRegistered = registeredChains.some((c) => c.label === chain.label);
            if (isAlreadyRegistered) {
              console.log(`⏭️  ${chain.label}: Already registered`);
              continue;
            }
            
            chainsToRegister.push(chain);
          }
        }
      }
    }

    if (chainsToRegister.length > 0) {
      console.log(`\nRegistering ${chainsToRegister.length} chain(s)...\n`);

      if (chainsToRegister.length === 1) {
        // Single chain - use register
        const chain = chainsToRegister[0]!;
        try {
          const tx = await resolver.register!([
            chain.label,
            chain.chainName,
            chain.owner || deployerWallet.address,
            getBytes(chain.interoperableAddressHex),
          ]);
          await tx.wait();
          console.log(`✓ ${chain.label}: Registered`);
        } catch (e: any) {
          const msg = e?.shortMessage || e?.message || String(e);
          console.error(`✗ ${chain.label}: Failed - ${msg}`);
        }
      } else {
        // Multiple chains - use batchRegister
        const registrationData = chainsToRegister.map((chain) => [
          chain.label,
          chain.chainName,
          chain.owner || deployerWallet.address,
          getBytes(chain.interoperableAddressHex),
        ]);

        try {
          console.log(`Using batchRegister for ${chainsToRegister.length} chains...`);
          const tx = await resolver.batchRegister!(registrationData);
          await tx.wait();
          for (const chain of chainsToRegister) {
            console.log(`✓ ${chain.label}: Registered`);
          }
        } catch (e: any) {
          const msg = e?.shortMessage || e?.message || String(e);
          console.error(`✗ batchRegister failed: ${msg}`);
          
          // Fallback to individual registration
          console.log("\nFalling back to individual registration...\n");
          for (const chain of chainsToRegister) {
            try {
              const tx = await resolver.register!([
                chain.label,
                chain.chainName,
                chain.owner || deployerWallet.address,
                getBytes(chain.interoperableAddressHex),
              ]);
              await tx.wait();
              console.log(`✓ ${chain.label}: Registered`);
            } catch (e2: any) {
              const msg2 = e2?.shortMessage || e2?.message || String(e2);
              console.error(`✗ ${chain.label}: Failed - ${msg2}`);
            }
          }
        }
      }
    }

    // Check and register aliases
    const aliases = getAllAliases();
    if (aliases.length > 0) {
      console.log(`\nChecking ${aliases.length} aliases...`);
      
      const registeredAliases: typeof aliases = [];
      const unregisteredAliases: typeof aliases = [];

      for (const aliasData of aliases) {
        const aliasHash = keccak256(toUtf8Bytes(aliasData.alias));
        const existingCanonical = await resolver.getCanonicalLabelhash!(aliasHash).catch(() => null);
        const isRegistered = existingCanonical && existingCanonical !== "0x0000000000000000000000000000000000000000000000000000000000000000";
        
        if (isRegistered) {
          registeredAliases.push(aliasData);
        } else {
          unregisteredAliases.push(aliasData);
        }
      }

      if (registeredAliases.length > 0) {
        console.log(`\n✓ Already registered (${registeredAliases.length}):`);
        for (const { alias, canonicalLabel } of registeredAliases) {
          console.log(`  - ${alias} → ${canonicalLabel}`);
        }
      }

      if (unregisteredAliases.length > 0) {
        console.log(`\n○ Not registered (${unregisteredAliases.length}):`);
        for (const { alias, canonicalLabel } of unregisteredAliases) {
          console.log(`  - ${alias} → ${canonicalLabel}`);
        }

        const shouldRegisterAliases = await promptContinueOrExit(
          rl,
          `\nRegister all ${unregisteredAliases.length} unregistered aliases? (y/n)`
        );

        if (shouldRegisterAliases) {
          console.log("\nRegistering aliases...\n");

          if (unregisteredAliases.length === 1) {
            // Single alias - use registerAlias
            const { alias, canonicalLabel } = unregisteredAliases[0]!;
            const canonicalHash = keccak256(toUtf8Bytes(canonicalLabel));

            try {
              const tx = await resolver.registerAlias!(alias, canonicalHash);
              await tx.wait();
              console.log(`✓ ${alias} → ${canonicalLabel}: Registered`);
            } catch (e: any) {
              const msg = e?.shortMessage || e?.message || String(e);
              console.error(`✗ ${alias}: Failed - ${msg}`);
            }
          } else {
            // Multiple aliases - use batchRegisterAlias
            const aliasStrings = unregisteredAliases.map((a) => a.alias);
            const canonicalHashes = unregisteredAliases.map((a) =>
              keccak256(toUtf8Bytes(a.canonicalLabel))
            );

            try {
              console.log(`Using batchRegisterAlias for ${unregisteredAliases.length} aliases...`);
              const tx = await resolver.batchRegisterAlias!(aliasStrings, canonicalHashes);
              await tx.wait();
              for (const { alias, canonicalLabel } of unregisteredAliases) {
                console.log(`✓ ${alias} → ${canonicalLabel}: Registered`);
              }
            } catch (e: any) {
              const msg = e?.shortMessage || e?.message || String(e);
              console.error(`✗ batchRegisterAlias failed: ${msg}`);

              // Fallback to individual registration
              console.log("\nFalling back to individual registration...\n");
              for (const { alias, canonicalLabel } of unregisteredAliases) {
                const canonicalHash = keccak256(toUtf8Bytes(canonicalLabel));

                try {
                  const tx = await resolver.registerAlias!(alias, canonicalHash);
                  await tx.wait();
                  console.log(`✓ ${alias} → ${canonicalLabel}: Registered`);
                } catch (e2: any) {
                  const msg2 = e2?.shortMessage || e2?.message || String(e2);
                  console.error(`✗ ${alias}: Failed - ${msg2}`);
                }
              }
            }
          }
        }
      } else {
        console.log("\nAll aliases are already registered.");
      }
    }

    // Check and set text records for all registered chains 
    // (includes auto-generated aliases and shared contenthash)
    const chainsWithRecords = CHAINS;
    
    if (chainsWithRecords.length > 0) {
      console.log(`\nChecking text records for ${chainsWithRecords.length} chain(s)...`);

      for (const chain of chainsWithRecords) {
        const labelhash = keccak256(toUtf8Bytes(chain.label));
        
        // Build text records, including auto-generated aliases and contenthash
        const chainTextRecords: Record<string, string> = { ...chain.textRecords };
        if (chain.aliases && chain.aliases.length > 0) {
          chainTextRecords["aliases"] = chain.aliases.join(", ");
        }
        if (WEBSITE_CONTENTHASH) {
          chainTextRecords["contentHash"] = WEBSITE_CONTENTHASH;
        }
        
        // Check for local images that could be uploaded
        const localImages = findLocalImages(chainTextRecords);
        let imagesToUpload: { key: string; path: string }[] = [];

        if (localImages.length > 0) {
          console.log(`\n${chain.label}: Found ${localImages.length} local image(s):`);
          for (const { key, path } of localImages) {
            console.log(`    - ${key}: ${path}`);
          }

          const shouldUpload = await promptContinueOrExit(
            rl,
            `Upload ${localImages.length} image(s) to Pinata IPFS? (y/n)`
          );

          if (shouldUpload) {
            imagesToUpload = localImages;
          } else {
            // Remove image keys from text records if not uploading
            for (const { key } of localImages) {
              delete chainTextRecords[key];
            }
            console.log("  Skipping image records, continuing with other text records");
          }
        }

        // Process text records - upload confirmed images to IPFS
        console.log(`\nProcessing ${chain.label} text records...`);
        const textRecords = await processTextRecords(chainTextRecords, imagesToUpload);
        const keys = Object.keys(textRecords);

        // Check which records need to be set
        const recordsToSet: { key: string; value: string }[] = [];

        for (const key of keys) {
          const existingValue = await resolver.getText!(labelhash, key).catch(() => "");
          const newValue = textRecords[key]!;
          
          if (existingValue !== newValue) {
            recordsToSet.push({ key, value: newValue });
          }
        }

        if (recordsToSet.length === 0) {
          console.log(`✓ ${chain.label}: All ${keys.length} text records already set`);
          continue;
        }

        console.log(`\n○ ${chain.label}: ${recordsToSet.length} text record(s) to set:`);
        for (const { key, value } of recordsToSet) {
          const displayValue = value.length > 50 ? value.slice(0, 47) + "..." : value;
          console.log(`    - ${key}: ${displayValue}`);
        }

        const shouldSetRecords = await promptContinueOrExit(
          rl,
          `Set ${recordsToSet.length} text record(s) for ${chain.label}? (y/n)`
        );

        if (shouldSetRecords) {
          try {
            if (recordsToSet.length === 1) {
              // Single record - use setText
              const { key, value } = recordsToSet[0]!;
              const tx = await resolver.setText!(labelhash, key, value);
              await tx.wait();
              console.log(`✓ ${chain.label}: Set ${key}`);
            } else {
              // Multiple records - use batchSetText
              const keysToSet = recordsToSet.map((r) => r.key);
              const valuesToSet = recordsToSet.map((r) => r.value);

              console.log(`Using batchSetText for ${recordsToSet.length} records...`);
              const tx = await resolver.batchSetText!(labelhash, keysToSet, valuesToSet);
              await tx.wait();
              for (const { key } of recordsToSet) {
                console.log(`✓ ${chain.label}: Set ${key}`);
              }
            }
          } catch (e: any) {
            const msg = e?.shortMessage || e?.message || String(e);
            console.error(`✗ ${chain.label}: Failed to set text records - ${msg}`);

            // Fallback to individual if batch failed
            if (recordsToSet.length > 1) {
              console.log("\nFalling back to individual setText calls...\n");
              for (const { key, value } of recordsToSet) {
                try {
                  const tx = await resolver.setText!(labelhash, key, value);
                  await tx.wait();
                  console.log(`✓ ${chain.label}: Set ${key}`);
                } catch (e2: any) {
                  const msg2 = e2?.shortMessage || e2?.message || String(e2);
                  console.error(`✗ ${chain.label}: Failed to set ${key} - ${msg2}`);
                }
              }
            }
          }
        }
      }
    }

    // Summary
    const finalCount = await resolver.chainCount!();
    console.log("\n=== Summary ===");
    console.log(`Chain count: ${chainCount} → ${finalCount}`);
    console.log("Done.");

  } finally {
    await shutdownSmith(rl, smith);
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});

