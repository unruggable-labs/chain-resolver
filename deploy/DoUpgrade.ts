// Test UUPS upgrade functionality
// Usage: bun run deploy/TestUpgrade.ts --chain=sepolia
//
// This script:
// 1. Deploys a new ChainResolver implementation
// 2. Upgrades the proxy to the new implementation
// 3. Verifies data persisted and new implementation is active

import { loadEnvFromAncestors } from "../shared/utils.ts";
loadEnvFromAncestors();

import { init } from "./libs/init.ts";
import {
  initSmith,
  shutdownSmith,
  loadDeployment,
  deployContract,
  verifyContract,
} from "./libs/utils.ts";
import { askQuestion, promptContinueOrExit } from "../shared/utils.ts";
import { RESOLVER_ABI } from "../shared/abis.ts";
import { Contract, Interface, keccak256, toUtf8Bytes } from "ethers";
import {
  getResolverAddress,
  getImplementationAddress,
  getLocalLayout,
  fetchDeployedLayout,
  compareLayouts,
} from "./libs/storageLayout.ts";
import { simulateTransaction } from "./libs/tenderly.ts";

async function main() {
  const { chainInfo, privateKey } = await init();

  console.log("\n=== UUPS Upgrade Test ===\n");
  console.log("Network:", chainInfo.name, `(${chainInfo.id})`);

  const { deployerWallet, smith, rl } = await initSmith(
    chainInfo.name,
    privateKey
  );

  if (!deployerWallet?.provider) {
    throw new Error("No valid deployment wallet");
  }

  try {
    // Find the deployed proxy. Source-of-truth is the ENS resolver record on
    // the parent domain (on.eth on mainnet, cid.eth on sepolia) since that is
    // what actually serves traffic. Deployment file and env var are kept as
    // cross-checks.
    let proxyAddress: string | undefined;
    const ensName = chainInfo.domain;

    try {
      console.log(`\nResolving ${ensName} via ENS registry...`);
      const ensResolver = await getResolverAddress(
        deployerWallet.provider,
        ensName
      );
      proxyAddress = ensResolver;
      console.log(`  ${ensName} resolver → ${ensResolver}`);
    } catch (e: any) {
      console.warn(
        `  ENS lookup failed (${e?.message ?? e}). Falling back to deployment file / env var.`
      );
    }

    let deploymentFileProxy: string | undefined;
    try {
      const proxyDep = await loadDeployment(chainInfo.id, "[Proxy]ERC1967Proxy");
      const addr = proxyDep.target as string;
      const code = await deployerWallet.provider.getCode(addr);
      if (code && code !== "0x") {
        deploymentFileProxy = addr;
        console.log("Deployment file proxy:", deploymentFileProxy);
      }
    } catch {}

    if (proxyAddress && deploymentFileProxy &&
        proxyAddress.toLowerCase() !== deploymentFileProxy.toLowerCase()) {
      console.warn(
        `⚠️  ENS resolver (${proxyAddress}) differs from deployment file proxy (${deploymentFileProxy}). Using ENS.`
      );
    }

    if (!proxyAddress) proxyAddress = deploymentFileProxy;

    if (!proxyAddress) {
      const envAddr = process.env.CHAIN_RESOLVER_PROXY?.trim();
      if (envAddr) {
        proxyAddress = envAddr;
      }
    }

    if (!proxyAddress) {
      proxyAddress = (await askQuestion(rl, "Enter ChainResolver proxy address: ")).trim();
    }

    if (!proxyAddress) {
      console.error("Proxy address is required.");
      process.exit(1);
    }

    const resolver = new Contract(proxyAddress, RESOLVER_ABI, deployerWallet);

    // Get current state
    const owner = await resolver.owner!();
    const chainCount = await resolver.chainCount!();
    const currentImpl = await getImplementationAddress(deployerWallet.provider, proxyAddress);

    console.log("\n--- Current State ---");
    console.log("Proxy address:", proxyAddress);
    console.log("Current implementation:", currentImpl);
    console.log("Owner:", owner);
    console.log("Chain count:", chainCount.toString());
    console.log("Caller:", deployerWallet.address);

    if (owner.toLowerCase() !== deployerWallet.address.toLowerCase()) {
      console.error("\n❌ You are not the contract owner. Cannot upgrade.");
      process.exit(1);
    }

    // --- Storage layout pre-flight ---
    // Rebuild the deployed implementation's storage layout from Etherscan's
    // verified source, compare against the local artifact. Refuses to proceed
    // if any deployed slot has been renamed, retyped, removed, or reordered.
    console.log("\n--- Storage Layout Check ---");
    const etherscanKey = process.env.ETHERSCAN_API_KEY?.trim();
    if (!etherscanKey) {
      console.warn(
        "⚠️  ETHERSCAN_API_KEY not set — skipping storage layout check. This is unsafe; set the key."
      );
      const proceedWithoutLayout = await promptContinueOrExit(
        rl,
        "Proceed without storage layout verification? (y/n)"
      );
      if (!proceedWithoutLayout) {
        console.log("Aborted.");
        return;
      }
    } else {
      try {
        const deployedLayout = await fetchDeployedLayout(
          currentImpl,
          chainInfo.id,
          etherscanKey
        );
        const localLayout = await getLocalLayout();
        const cmp = compareLayouts(deployedLayout, localLayout);

        console.log(
          `  Deployed vars: ${deployedLayout.storage.length}, local vars: ${localLayout.storage.length}`
        );

        if (cmp.appended.length > 0) {
          console.log(`  Appended (safe): ${cmp.appended.map((v) => v.label).join(", ")}`);
        }

        if (!cmp.compatible) {
          console.error("\n❌ STORAGE LAYOUT INCOMPATIBLE — upgrade would corrupt state:");
          for (const issue of cmp.issues) {
            console.error(`   ${issue}`);
          }
          process.exit(1);
        }

        console.log("  ✓ Layout is upgrade-compatible");
      } catch (e: any) {
        console.error(
          `\n❌ Storage layout check failed: ${e?.message ?? e}`
        );
        const forceContinue = await promptContinueOrExit(
          rl,
          "Continue anyway? (y/n)"
        );
        if (!forceContinue) {
          console.log("Aborted.");
          return;
        }
      }
    }

    // Test data persistence - get a sample chain if any exist
    let testLabelhash: string | undefined;
    let testInteropAddress: string | undefined;
    
    if (chainCount > 0n) {
      testLabelhash = keccak256(toUtf8Bytes("optimism")); // Common test chain
      try {
        testInteropAddress = await resolver.interoperableAddress!(testLabelhash);
        if (testInteropAddress && testInteropAddress !== "0x") {
          console.log("\nTest data (optimism):");
          console.log("  Labelhash:", testLabelhash);
          console.log("  Interoperable address:", testInteropAddress);
        }
      } catch {}
    }

    // Menu
    console.log("\n--- Options ---");
    console.log("1. Deploy new implementation and upgrade");
    console.log("2. Upgrade to existing implementation address");
    console.log("3. Just deploy new implementation (no upgrade)");
    console.log("4. Exit");

    const choice = (await askQuestion(rl, "\nChoice (1-4): ")).trim();

    let newImplAddress: string | undefined;

    if (choice === "1" || choice === "3") {
      // Deploy new implementation
      console.log("\n--- Deploying New Implementation ---");
      
      const { contract: newImpl } = await deployContract(
        smith,
        deployerWallet,
        "ChainResolver",
        [],
        {},
        "[NewImpl]"
      );
      newImplAddress = newImpl.target as string;
      console.log("New implementation deployed at:", newImplAddress);

      // Offer to verify
      const shouldVerify = await promptContinueOrExit(
        rl,
        "Verify new implementation on block explorer? (y/n)"
      );

      if (shouldVerify) {
        try {
          await verifyContract(
            chainInfo.id,
            newImpl,
            "ChainResolver",
            [],
            {},
            smith
          );
          console.log("✓ Verification submitted");
        } catch (e: any) {
          const msg = e?.shortMessage || e?.message || String(e);
          console.warn("⚠️  Verification failed:", msg);
        }
      }

      if (choice === "3") {
        console.log("\nImplementation deployed. Use option 2 to upgrade later.");
        console.log("Implementation address:", newImplAddress);
        return;
      }
    } else if (choice === "2") {
      newImplAddress = (await askQuestion(rl, "Enter new implementation address: ")).trim();
      if (!newImplAddress) {
        console.error("Implementation address required.");
        process.exit(1);
      }

      // Verify it's a valid contract
      const code = await deployerWallet.provider.getCode(newImplAddress);
      if (!code || code === "0x") {
        console.error("No contract found at that address.");
        process.exit(1);
      }
    } else if (choice === "4") {
      console.log("Exiting.");
      return;
    } else {
      console.error("Invalid choice.");
      process.exit(1);
    }

    // Confirm upgrade
    console.log("\n--- Upgrade Details ---");
    console.log("From:", currentImpl);
    console.log("To:  ", newImplAddress);

    // --- Tenderly dry-run ---
    // Simulate upgradeToAndCall(newImpl, "0x") against latest block. The
    // simulation runs from the owner address (which is what will sign the
    // real tx) so a Tenderly "success" means the on-chain tx should also
    // succeed (modulo gas price / nonce / RPC issues).
    if (process.env.TENDERLY_API_KEY) {
      console.log("\n--- Tenderly Simulation ---");
      try {
        const iface = new Interface([
          "function upgradeToAndCall(address newImplementation, bytes data) payable",
        ]);
        const calldata = iface.encodeFunctionData("upgradeToAndCall", [
          newImplAddress!,
          "0x",
        ]);
        const sim = await simulateTransaction(
          { from: owner, to: proxyAddress, input: calldata },
          chainInfo.id
        );
        if (sim.status) {
          console.log(`  ✓ Simulation succeeded (gas used: ${sim.gasUsed ?? "?"})`);
        } else {
          console.error(`  ✗ Simulation FAILED: ${sim.errorMessage ?? "unknown"}`);
        }
        if (sim.shareUrl) {
          console.log(`  Share: ${sim.shareUrl}`);
        }
        if (!sim.status) {
          const forceProceed = await promptContinueOrExit(
            rl,
            "Simulation failed. Proceed with live tx anyway? (y/n)"
          );
          if (!forceProceed) {
            console.log("Aborted.");
            return;
          }
        }
      } catch (e: any) {
        console.warn(`  ⚠️  Tenderly simulation errored: ${e?.message ?? e}`);
        const forceProceed = await promptContinueOrExit(
          rl,
          "Continue without Tenderly dry-run? (y/n)"
        );
        if (!forceProceed) {
          console.log("Aborted.");
          return;
        }
      }
    } else {
      console.log(
        "\n(TENDERLY_API_KEY not set — skipping Tenderly simulation)"
      );
    }

    const shouldUpgrade = await promptContinueOrExit(
      rl,
      "\nProceed with upgrade? (y/n)"
    );

    if (!shouldUpgrade) {
      console.log("Upgrade cancelled.");
      return;
    }

    // Perform upgrade
    console.log("\nUpgrading...");
    try {
      const tx = await resolver.upgradeToAndCall!(newImplAddress, "0x");
      console.log("Transaction sent:", tx.hash);
      await tx.wait();
      console.log("✓ Upgrade complete!");
    } catch (e: any) {
      const msg = e?.shortMessage || e?.message || String(e);
      console.error("✗ Upgrade failed:", msg);
      process.exit(1);
    }

    // Verify upgrade
    console.log("\n--- Verification ---");
    
    const newCurrentImpl = await getImplementationAddress(deployerWallet.provider, proxyAddress);
    console.log("Implementation after upgrade:", newCurrentImpl);
    
    if (newCurrentImpl.toLowerCase() === newImplAddress!.toLowerCase()) {
      console.log("✓ Implementation updated correctly");
    } else {
      console.error("✗ Implementation mismatch!");
    }

    // Verify data persistence
    const newChainCount = await resolver.chainCount!();
    console.log("Chain count after upgrade:", newChainCount.toString());
    
    if (newChainCount === chainCount) {
      console.log("✓ Chain count preserved");
    } else {
      console.error("✗ Chain count changed!");
    }

    if (testLabelhash && testInteropAddress) {
      const newInteropAddress = await resolver.interoperableAddress!(testLabelhash);
      if (newInteropAddress === testInteropAddress) {
        console.log("✓ Test chain data preserved");
      } else {
        console.error("✗ Test chain data changed!");
        console.log("  Before:", testInteropAddress);
        console.log("  After:", newInteropAddress);
      }
    }

    const newOwner = await resolver.owner!();
    if (newOwner.toLowerCase() === owner.toLowerCase()) {
      console.log("✓ Owner preserved");
    } else {
      console.error("✗ Owner changed!");
    }

    console.log("\n=== Upgrade Test Complete ===");

  } finally {
    await shutdownSmith(rl, smith);
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});

