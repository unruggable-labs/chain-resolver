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
import { Contract, keccak256, toUtf8Bytes, getBytes, dnsEncode, namehash, Interface, AbiCoder, hexlify } from "ethers";
import { CHAINS, getAllAliases } from "../data/chains.ts";
import { existsSync, readFileSync } from "fs";
import { join, basename } from "path";

// Image keys that should be uploaded to IPFS if they're local file paths
const IMAGE_KEYS = ["avatar", "header"];

const WEBSITE_CONTENTHASH = {
  sepolia: "0xe3010155122085bc74206e1ecd490225cd2649579f87efd9d87bbf9ec75288a0fe6b95a1c9ab",
  mainnet: "0xe30101551220bcfedd3b3076c10f119ad4ec22e2dbe60d46e737a17f94971b7824457dfb4044"
}

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
      const existingAdmin = await resolver.getChainAdmin!(chain.label).catch(() => null);
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

      console.log(aliases);

      for (const aliasData of aliases) {
        // Check on-chain registration via getCanonicalLabel (not text records)
        const [ canonicalLabel, canonicalLabelhash ] = await resolver.getCanonicalLabel!(aliasData.alias).catch(() => null);

        console.log(canonicalLabel, canonicalLabelhash);
        
        const isRegistered = canonicalLabelhash && canonicalLabelhash !== "0x0000000000000000000000000000000000000000000000000000000000000000";
        
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
        // Filter out aliases where the canonical chain isn't registered yet
        const registeredChainLabels = new Set(registeredChains.map(c => c.label.toLowerCase()));
        const validAliases = unregisteredAliases.filter(
          (a) => registeredChainLabels.has(a.canonicalLabel.toLowerCase())
        );
        const invalidAliases = unregisteredAliases.filter(
          (a) => !registeredChainLabels.has(a.canonicalLabel.toLowerCase())
        );

        if (invalidAliases.length > 0) {
          console.log(`\n⚠️  Skipping ${invalidAliases.length} alias(es) - canonical chain not registered:`);
          for (const { alias, canonicalLabel } of invalidAliases) {
            console.log(`  - ${alias} → ${canonicalLabel} (${canonicalLabel} not registered)`);
          }
        }

        if (validAliases.length > 0) {
          console.log(`\n○ Not registered (${validAliases.length}):`);
          for (const { alias, canonicalLabel } of validAliases) {
            console.log(`  - ${alias} → ${canonicalLabel}`);
          }

          const shouldRegisterAliases = await promptContinueOrExit(
            rl,
            `\nRegister all ${validAliases.length} unregistered aliases? (y/n)`
          );

          if (shouldRegisterAliases) {
            console.log("\nRegistering aliases...\n");

            if (validAliases.length === 1) {
              // Single alias - use registerAlias
              const { alias, canonicalLabel } = validAliases[0]!;
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
              const aliasStrings = validAliases.map((a) => a.alias);
              const canonicalHashes = validAliases.map((a) =>
                keccak256(toUtf8Bytes(a.canonicalLabel))
              );

              try {
                console.log(`Using batchRegisterAlias for ${validAliases.length} aliases...`);
                const tx = await resolver.batchRegisterAlias!(aliasStrings, canonicalHashes);
                await tx.wait();
                for (const { alias, canonicalLabel } of validAliases) {
                  console.log(`✓ ${alias} → ${canonicalLabel}: Registered`);
                }
              } catch (e: any) {
                const msg = e?.shortMessage || e?.message || String(e);
                console.error(`✗ batchRegisterAlias failed: ${msg}`);

                // Fallback to individual registration
                console.log("\nFalling back to individual registration...\n");
                for (const { alias, canonicalLabel } of validAliases) {
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
        }
      } else {
        console.log("\nAll aliases are already registered.");
      }
    }

    // Check and set text records for all registered chains 
    // (includes auto-generated aliases and shared contenthash)
    // Only process chains that have been registered
    const chainsWithRecords = registeredChains;
    
    if (chainsWithRecords.length > 0) {
      console.log(`\nChecking text records for ${chainsWithRecords.length} registered chain(s)...`);

      for (const chain of chainsWithRecords) {
        // Build text records, including auto-generated aliases
        const chainTextRecords: Record<string, string> = { ...chain.textRecords };
        if (chain.aliases && chain.aliases.length > 0) {
          chainTextRecords["aliases"] = chain.aliases.join(", ");
        }
        
        // Check for local images that could be uploaded
        const localImages = findLocalImages(chainTextRecords);
        let imagesToUpload: { key: string; path: string }[] = [];

        if (localImages.length > 0) {
          // Check existing image records on-chain
          console.log(`\n${chain.label}: Checking image records...`);
          const existingImages: { key: string; value: string }[] = [];
          for (const key of IMAGE_KEYS) {
            try {
              const existingValue = await resolver.getText!(chain.label, key).catch(() => "");
              if (existingValue) {
                existingImages.push({ key, value: existingValue });
              }
            } catch {}
          }

          if (existingImages.length > 0) {
            console.log(`  Existing image records:`);
            for (const { key, value } of existingImages) {
              const displayValue = value.length > 60 ? value.slice(0, 57) + "..." : value;
              console.log(`    - ${key}: ${displayValue}`);
            }
          }

          console.log(`\n  Found ${localImages.length} local image(s) to upload:`);
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
            // Allow user to specify which keys to upload
            const keysToUploadInput = (await askQuestion(
              rl,
              `Enter specific image key(s) to upload (comma-separated, e.g., "avatar" or "avatar,header"), or press Enter to skip: `
            )).trim();

            if (keysToUploadInput) {
              const requestedKeys = keysToUploadInput.split(",").map((k) => k.trim().toLowerCase());
              imagesToUpload = localImages.filter((img) => requestedKeys.includes(img.key.toLowerCase()));
              
              if (imagesToUpload.length === 0) {
                console.log("  No matching image keys found, skipping image upload");
                // Remove image keys from text records if no matches
                for (const { key } of localImages) {
                  delete chainTextRecords[key];
                }
              } else {
                console.log(`  Will upload ${imagesToUpload.length} image(s): ${imagesToUpload.map(i => i.key).join(", ")}`);
                // Ensure the keys to upload are in chainTextRecords (they should be, but just in case)
                for (const { key, path } of imagesToUpload) {
                  if (!chainTextRecords[key]) {
                    chainTextRecords[key] = path;
                  }
                }
              }
            } else {
              // Remove image keys from text records if not uploading
              for (const { key } of localImages) {
                delete chainTextRecords[key];
              }
              console.log("  Skipping image records, continuing with other text records");
            }
          }
        }

        // Process text records - upload confirmed images to IPFS
        console.log(`\nProcessing ${chain.label} text records...`);
        const textRecords = await processTextRecords(chainTextRecords, imagesToUpload);
        
        // Remove image keys that are local file paths but weren't uploaded
        // Keep keys that were uploaded (now IPFS URLs) or are already URLs
        const uploadedImageKeys = new Set(imagesToUpload.map(img => img.key));
        for (const key of IMAGE_KEYS) {
          if (textRecords[key]) {
            // If this key was uploaded, it should now be an IPFS URL (not a local path)
            // So we keep it - it will be included in recordsToSet
            if (uploadedImageKeys.has(key)) {
              // Key was uploaded, keep it (should already be IPFS URL from processTextRecords)
              continue;
            }
            // If it's still a local file path and wasn't uploaded, remove it
            if (isLocalFilePath(textRecords[key]!)) {
              delete textRecords[key];
            }
            // Otherwise keep it (already a URL/IPFS link, just not uploaded in this run)
          }
        }
        
        const keys = Object.keys(textRecords);

        // Check which records need to be set
        const recordsToSet: { key: string; value: string }[] = [];

        for (const key of keys) {
          const existingValue = await resolver.getText!(chain.label, key).catch(() => "");
          const newValue = textRecords[key]!;
          
          if (existingValue !== newValue) {
            recordsToSet.push({ key, value: newValue });
          }
        }

        if (recordsToSet.length === 0) {
          console.log(`✓ ${chain.label}: All ${keys.length} text records already set`);
        } else {

        console.log(`\n○ ${chain.label}: ${recordsToSet.length} text record(s) to set:`);
        for (const { key, value } of recordsToSet) {
          const displayValue = value.length > 50 ? value.slice(0, 47) + "..." : value;
          console.log(`    - ${key}: ${displayValue}`);
        }

        const shouldSetRecords = await promptContinueOrExit(
          rl,
          `Set ${recordsToSet.length} text record(s) for ${chain.label}? (y/n)`
        );

        let finalRecordsToSet = recordsToSet;

        if (!shouldSetRecords) {
          // Allow user to specify which keys to set
          const keysToSetInput = (await askQuestion(
            rl,
            `Enter specific text record key(s) to set (comma-separated, e.g., "description" or "description,url"), or press Enter to skip: `
          )).trim();

          if (keysToSetInput) {
            const requestedKeys = keysToSetInput.split(",").map((k) => k.trim().toLowerCase());
            finalRecordsToSet = recordsToSet.filter((r) => requestedKeys.includes(r.key.toLowerCase()));
            
            if (finalRecordsToSet.length === 0) {
              console.log("  No matching text record keys found, skipping");
            } else {
              console.log(`  Will set ${finalRecordsToSet.length} text record(s): ${finalRecordsToSet.map(r => r.key).join(", ")}`);
            }
          } else {
            finalRecordsToSet = [];
            console.log("  Skipping text record updates");
          }
        }

        if (finalRecordsToSet.length > 0) {
          try {
            if (finalRecordsToSet.length === 1) {
              // Single record - use setText
              const { key, value } = finalRecordsToSet[0]!;
              const tx = await resolver.setText!(keccak256(toUtf8Bytes(chain.label)), key, value);
              await tx.wait();
              console.log(`✓ ${chain.label}: Set ${key}`);
            } else {
              // Multiple records - use batchSetText
              const keysToSet = finalRecordsToSet.map((r) => r.key);
              const valuesToSet = finalRecordsToSet.map((r) => r.value);

              console.log(`Using batchSetText for ${finalRecordsToSet.length} records...`);
              const tx = await resolver.batchSetText!(keccak256(toUtf8Bytes(chain.label)), keysToSet, valuesToSet);
              await tx.wait();
              for (const { key } of finalRecordsToSet) {
                console.log(`✓ ${chain.label}: Set ${key}`);
              }
            }
          } catch (e: any) {
            const msg = e?.shortMessage || e?.message || String(e);
            console.error(`✗ ${chain.label}: Failed to set text records - ${msg}`);

            // Fallback to individual if batch failed
            if (finalRecordsToSet.length > 1) {
              console.log("\nFalling back to individual setText calls...\n");
              for (const { key, value } of finalRecordsToSet) {
                try {
                  const tx = await resolver.setText!(keccak256(toUtf8Bytes(chain.label)), key, value);
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

        console.log("WAAAAAAT");
        // Check contenthash
        try {
          // Determine expected contenthash: use chain.contenthash if set, otherwise use WEBSITE_CONTENTHASH
          const expectedContenthash = chain.contenthash ?? WEBSITE_CONTENTHASH[chainInfo.name as keyof typeof WEBSITE_CONTENTHASH];
          
          console.log("expectedContenthash", expectedContenthash);
          console.log("chain.contenthash", chain.contenthash);
          console.log("chain.label", chain.label);

          if (expectedContenthash) {
            // Get current contenthash from chain
            const currentContenthash = await resolver.getContenthash!(chain.label);
            const currentHex = hexlify(currentContenthash).toLowerCase();
            const expectedHex = expectedContenthash.toLowerCase();
            
            // If different, ask to update
            if (currentHex !== expectedHex) {
              console.log(`\n${chain.label}: Contenthash differs from expected`);
              console.log(`  Current: ${currentHex.slice(0, 20)}...${currentHex.slice(-10)}`);
              console.log(`  Expected: ${expectedHex.slice(0, 20)}...${expectedHex.slice(-10)}`);
              
              const shouldUpdate = await promptContinueOrExit(
                rl,
                `Update contenthash for ${chain.label}? (y/n)`
              );

              if (shouldUpdate) {
                try {
                  const chainLabelhash = keccak256(toUtf8Bytes(chain.label));
                  const contenthashBytes = getBytes(expectedContenthash);
                  const tx = await resolver.setContenthash!(chainLabelhash, contenthashBytes);
                  await tx.wait();
                  console.log(`✓ ${chain.label}: Updated contenthash`);
                } catch (e: any) {
                  const msg = e?.shortMessage || e?.message || String(e);
                  console.error(`✗ ${chain.label}: Failed to update contenthash - ${msg}`);
                }
              }
            }
          }
        } catch (e) {
          console.warn(`  Could not check contenthash for ${chain.label}`);
        }
      }
    }

    // Set base name records (cid.eth/on.eth)
    const BASE_NAME_LABELHASH = "0x0000000000000000000000000000000000000000000000000000000000000000";
    const baseNameTextRecords: Record<string, string> = {
      // Add default base name records here, or leave empty to skip
      // Example:
      // "url": "https://example.com",
      "description": "ERC-7828 Chain Registry/Resolver",
    };

    if (Object.keys(baseNameTextRecords).length > 0) {
      console.log(`\n=== Base Name Records ===`);
      console.log(`Setting records for base name (${chainInfo.domain})...\n`);

      // Check which records need to be set using resolve path for base name
      const baseRecordsToSet: { key: string; value: string }[] = [];

      // Get parent namehash and DNS-encode the base name
      const parentNamehash = await resolver.parentNamehash!();
      const baseNameDnsEncoded = dnsEncode(chainInfo.domain);
      const baseNamehash = namehash(chainInfo.domain);

      // Interface for text() function
      const textInterface = new Interface([
        "function text(bytes32,string) view returns (string)"
      ]);

      for (const [key, value] of Object.entries(baseNameTextRecords)) {
        try {
          // Use resolve() to get text record for base name
          const textCalldata = textInterface.encodeFunctionData("text", [baseNamehash, key]);
          const resolveResponse = await resolver.resolve!(baseNameDnsEncoded, textCalldata);
          const existingValue = textInterface.decodeFunctionResult("text", resolveResponse)[0] as string;
          
          if (existingValue !== value) {
            baseRecordsToSet.push({ key, value });
          }
        } catch (e) {
          // If resolve fails, assume we need to set it
          baseRecordsToSet.push({ key, value });
        }
      }

      if (baseRecordsToSet.length === 0) {
        console.log(`✓ Base name: All ${Object.keys(baseNameTextRecords).length} text records already set`);
      } else {
        console.log(`○ Base name: ${baseRecordsToSet.length} text record(s) to set:`);
        for (const { key, value } of baseRecordsToSet) {
          const displayValue = value.length > 50 ? value.slice(0, 47) + "..." : value;
          console.log(`    - ${key}: ${displayValue}`);
        }

        const shouldSetBaseRecords = await promptContinueOrExit(
          rl,
          `Set ${baseRecordsToSet.length} text record(s) for base name? (y/n)`
        );

        if (shouldSetBaseRecords) {
          try {
            if (baseRecordsToSet.length === 1) {
              // Single record - use setText
              const { key, value } = baseRecordsToSet[0]!;
              const tx = await resolver.setText!(BASE_NAME_LABELHASH, key, value);
              await tx.wait();
              console.log(`✓ Base name: Set ${key}`);
            } else {
              // Multiple records - use batchSetText
              const keysToSet = baseRecordsToSet.map((r) => r.key);
              const valuesToSet = baseRecordsToSet.map((r) => r.value);

              console.log(`Using batchSetText for ${baseRecordsToSet.length} records...`);
              const tx = await resolver.batchSetText!(BASE_NAME_LABELHASH, keysToSet, valuesToSet);
              await tx.wait();
              for (const { key } of baseRecordsToSet) {
                console.log(`✓ Base name: Set ${key}`);
              }
            }
          } catch (e: any) {
            const msg = e?.shortMessage || e?.message || String(e);
            console.error(`✗ Base name: Failed to set text records - ${msg}`);

            // Fallback to individual if batch failed
            if (baseRecordsToSet.length > 1) {
              console.log("\nFalling back to individual setText calls...\n");
              for (const { key, value } of baseRecordsToSet) {
                try {
                  const tx = await resolver.setText!(BASE_NAME_LABELHASH, key, value);
                  await tx.wait();
                  console.log(`✓ Base name: Set ${key}`);
                } catch (e2: any) {
                  const msg2 = e2?.shortMessage || e2?.message || String(e2);
                  console.error(`✗ Base name: Failed to set ${key} - ${msg2}`);
                }
              }
            }
          }
        }
      }
    }

    // Set default contenthash (used for base name and all chains if they don't have a specific contenthash)
    if (WEBSITE_CONTENTHASH) {
      console.log(`\n=== Default Contenthash ===`);

      // WEBSITE_CONTENTHASH is already in ENS contenthash format (hex string with 0x prefix)
      const contenthashBytes: string = WEBSITE_CONTENTHASH[chainInfo.name as keyof typeof WEBSITE_CONTENTHASH];

      if (contenthashBytes) {
        // Check existing default contenthash
        let existingDefaultContenthash = "";
        try {
          const existing = await resolver.defaultContenthash!();
          existingDefaultContenthash = existing.toLowerCase();
        } catch {}

        if (existingDefaultContenthash !== contenthashBytes.toLowerCase()) {
          console.log(`Current default contenthash: ${existingDefaultContenthash || "(not set)"}`);
          console.log(`New default contenthash: ${contenthashBytes}`);
          
          const shouldSetDefaultContenthash = await promptContinueOrExit(
            rl,
            `Update default contenthash? (y/n)`
          );

          if (shouldSetDefaultContenthash) {
            try {
              // setDefaultContenthash expects bytes, so convert hex string to bytes
              const contenthashBytesArray = getBytes(contenthashBytes);
              const tx = await resolver.setDefaultContenthash!(contenthashBytesArray);
              await tx.wait();
              console.log(`✓ Default contenthash updated`);
            } catch (e: any) {
              const msg = e?.shortMessage || e?.message || String(e);
              console.error(`✗ Failed to set default contenthash - ${msg}`);
            }
          } else {
            console.log(`  Skipping default contenthash update`);
          }
        } else {
          console.log(`✓ Default contenthash already set (matches expected value)`);
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

