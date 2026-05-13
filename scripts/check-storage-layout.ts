/**
 * Read-only smoke test for the upgrade preflight pipeline.
 *
 * Usage:
 *   bun run scripts/check-storage-layout.ts mainnet
 *   bun run scripts/check-storage-layout.ts sepolia
 *
 * Resolves the parent ENS name → proxy → ERC1967 impl, then fetches the
 * verified source from Etherscan, recompiles with solc-js, and compares
 * the storage layout against the locally-built artifact.
 */

import { loadEnvFromAncestors } from "../shared/utils.ts";
loadEnvFromAncestors();

import { JsonRpcProvider } from "ethers";
import {
  getResolverAddress,
  getImplementationAddress,
  getLocalLayout,
  fetchDeployedLayout,
  compareLayouts,
} from "../deploy/libs/storageLayout.ts";

const NETWORKS = {
  mainnet: {
    id: 1,
    rpc: process.env.MAINNET_RPC_URL,
    domain: "on.eth",
  },
  sepolia: {
    id: 11155111,
    rpc: process.env.SEPOLIA_RPC_URL,
    domain: "cid.eth",
  },
} as const;

async function main() {
  const networkArg = process.argv[2];
  if (!networkArg || !(networkArg in NETWORKS)) {
    console.error("Usage: bun run scripts/check-storage-layout.ts <mainnet|sepolia>");
    process.exit(1);
  }

  const net = NETWORKS[networkArg as keyof typeof NETWORKS];
  if (!net.rpc) {
    console.error(`RPC URL not set for ${networkArg}`);
    process.exit(1);
  }
  const etherscanKey = process.env.ETHERSCAN_API_KEY;
  if (!etherscanKey) {
    console.error("ETHERSCAN_API_KEY not set");
    process.exit(1);
  }

  const provider = new JsonRpcProvider(net.rpc);

  console.log(`Network: ${networkArg} (${net.id})`);
  console.log(`Resolving ${net.domain} via ENS...`);
  const proxy = await getResolverAddress(provider, net.domain);
  console.log(`  ${net.domain} resolver → ${proxy}`);

  const impl = await getImplementationAddress(provider, proxy);
  console.log(`  ERC1967 impl slot → ${impl}`);

  console.log(`\nFetching + recompiling deployed implementation...`);
  const deployed = await fetchDeployedLayout(impl, net.id, etherscanKey);

  console.log(`\nReading local artifact...`);
  const local = await getLocalLayout();

  console.log(`\nDeployed storage variables: ${deployed.storage.length}`);
  console.log(`Local storage variables:    ${local.storage.length}`);

  const cmp = compareLayouts(deployed, local);

  console.log("\nSlot-by-slot comparison (label / type / bytes):");
  console.log(
    `${"slot".padEnd(5)} ${"offset".padEnd(7)} ${"deployed label".padEnd(30)} ${"local label".padEnd(30)} type match  bytes match`
  );
  console.log("-".repeat(115));
  for (const dep of deployed.storage) {
    const nw = local.storage.find(
      (v) => v.slot === dep.slot && v.offset === dep.offset
    );
    const depType = deployed.types[dep.type]?.label ?? dep.type;
    const nwType = nw ? local.types[nw.type]?.label ?? nw.type : "—";
    const depSize = deployed.types[dep.type]?.numberOfBytes ?? "?";
    const nwSize = nw ? local.types[nw.type]?.numberOfBytes ?? "?" : "—";
    const typeOk = nw && depType === nwType ? "✓" : "✗";
    const sizeOk = nw && depSize === nwSize ? "✓" : "✗";
    console.log(
      `${dep.slot.padEnd(5)} ${String(dep.offset).padEnd(7)} ${dep.label.padEnd(30)} ${(nw?.label ?? "—").padEnd(30)} ${typeOk} ${depType.padEnd(8)} ${sizeOk} ${depSize}/${nwSize}`
    );
  }

  if (cmp.appended.length > 0) {
    console.log(`\nAppended (safe — new vars added at end):`);
    for (const v of cmp.appended) {
      const t = local.types[v.type]?.label ?? v.type;
      console.log(`  + slot ${v.slot} offset ${v.offset}: ${v.label} (${t})`);
    }
  }

  if (cmp.compatible) {
    console.log(
      `\n✓ All ${deployed.storage.length} deployed variables match local: label, type, and byte-size.`
    );
  } else {
    console.error("\n❌ INCOMPATIBLE:");
    for (const issue of cmp.issues) console.error("   " + issue);
    process.exit(1);
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
