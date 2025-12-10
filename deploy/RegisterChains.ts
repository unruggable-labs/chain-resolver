// Register chains from shared data to deployed ChainResolver proxy
// Usage: bun run deploy/RegisterChains.ts

import "dotenv/config";
import { init } from "./libs/init.ts";
import {
  initSmith,
  shutdownSmith,
  askQuestion,
  promptContinueOrExit,
  loadDeployment,
} from "./libs/utils.ts";
import { Contract, keccak256, toUtf8Bytes, getBytes } from "ethers";
import { CHAINS, getAllAliases } from "../data/chains.ts";

const RESOLVER_ABI = [
  "function owner() view returns (address)",
  "function chainCount() view returns (uint256)",
  "function getChainAdmin(bytes32) view returns (address)",
  "function register((string,string,address,bytes)) external",
  "function batchRegister((string,string,address,bytes)[]) external",
  "function registerAlias(string,bytes32) external",
  "function removeAlias(string) external",
  "function getCanonicalLabelhash(bytes32) view returns (bytes32)",
];

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

          for (const { alias, canonicalLabel } of unregisteredAliases) {
            const canonicalHash = keccak256(toUtf8Bytes(canonicalLabel));

            try {
              const tx = await resolver.registerAlias!(alias, canonicalHash);
              await tx.wait();
              console.log(`✓ ${alias} → ${canonicalLabel}: Registered`);
            } catch (e: any) {
              const msg = e?.shortMessage || e?.message || String(e);
              console.error(`✗ ${alias}: Failed - ${msg}`);
            }
          }
        }
      } else {
        console.log("\nAll aliases are already registered.");
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

