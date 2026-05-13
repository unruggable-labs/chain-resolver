/**
 * Storage layout verification for UUPS upgrades.
 *
 * Compares the storage layout of the locally-compiled new implementation
 * against the storage layout of the currently-deployed implementation,
 * fetched fresh from Etherscan + recompiled with the exact compiler version.
 */

import axios from "axios";
import { keccak256 } from "ethers";
import { readFile } from "fs/promises";
import path from "path";
import { fileURLToPath } from "url";

// ERC1967 implementation slot
export const ERC1967_IMPL_SLOT =
  "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const REPO_ROOT = path.resolve(__dirname, "../..");

export interface StorageVar {
  astId: number;
  contract: string;
  label: string;
  offset: number;
  slot: string;
  type: string;
}

export interface StorageType {
  encoding: string;
  label: string;
  numberOfBytes: string;
}

export interface StorageLayout {
  storage: StorageVar[];
  types: Record<string, StorageType>;
}

export interface LayoutComparison {
  compatible: boolean;
  issues: string[];
  appended: StorageVar[];
}

/**
 * Resolve an ENS name to its resolver address (the proxy, in our case).
 * Uses the provider's built-in ENS lookup (provider.getResolver) so we don't
 * need to hard-code the ENS registry address per chain.
 */
export async function getResolverAddress(
  provider: any,
  ensName: string
): Promise<string> {
  const resolver = await provider.getResolver(ensName);
  if (!resolver?.address) {
    throw new Error(`No resolver set for ENS name ${ensName}`);
  }
  return resolver.address as string;
}

/**
 * Read the ERC1967 implementation slot of a UUPS proxy.
 */
export async function getImplementationAddress(
  provider: any,
  proxyAddress: string
): Promise<string> {
  const slot = await provider.getStorage(proxyAddress, ERC1967_IMPL_SLOT);
  return "0x" + slot.slice(-40);
}

/**
 * Read the storage layout for the freshly-built local ChainResolver from the
 * forge artifact (out/ChainResolver.sol/ChainResolver.json).
 *
 * Before returning, verifies the artifact is not stale by checking that the
 * keccak256 of each src/ source file on disk matches the hash baked into
 * the artifact's metadata.sources. If anything differs the caller is told
 * to run `forge build` and retry, so we never compare a deployed layout
 * against an out-of-date local artifact.
 */
export async function getLocalLayout(): Promise<StorageLayout> {
  const artifactPath = path.join(
    REPO_ROOT,
    "out/ChainResolver.sol/ChainResolver.json"
  );
  const raw = await readFile(artifactPath, "utf8");
  const artifact = JSON.parse(raw);
  if (!artifact.storageLayout) {
    throw new Error(
      `ChainResolver artifact at ${artifactPath} has no storageLayout. Run \`forge build\` first.`
    );
  }
  await assertArtifactMatchesSources(artifact);
  return artifact.storageLayout as StorageLayout;
}

/**
 * Throw if any local source file's keccak256 differs from the hash recorded
 * in the artifact metadata — i.e. the artifact was built from older code.
 */
async function assertArtifactMatchesSources(artifact: any): Promise<void> {
  const metadata =
    typeof artifact.metadata === "string"
      ? JSON.parse(artifact.metadata)
      : artifact.metadata;
  const sources = metadata?.sources;
  if (!sources || typeof sources !== "object") {
    // No metadata to verify against — fall through (best effort).
    return;
  }

  const stale: Array<{ path: string; expected: string; actual: string }> = [];
  const missing: string[] = [];

  for (const [srcPath, info] of Object.entries<any>(sources)) {
    const expected: string | undefined = info?.keccak256;
    if (!expected) continue;

    // Only verify files inside the repo. Library sources (lib/, node_modules/)
    // are technically also covered by the artifact, but enforcing them creates
    // false positives from line-ending normalisation in vendor code. The
    // editable code that matters for a stale build is in src/.
    if (!srcPath.startsWith("src/")) continue;

    const fullPath = path.join(REPO_ROOT, srcPath);
    try {
      const content = await readFile(fullPath);
      const actual = keccak256(content);
      if (actual.toLowerCase() !== expected.toLowerCase()) {
        stale.push({ path: srcPath, expected, actual });
      }
    } catch {
      missing.push(srcPath);
    }
  }

  if (stale.length > 0 || missing.length > 0) {
    const lines = [
      "Local artifact is stale — source files have changed since the last `forge build`:",
    ];
    for (const s of stale) {
      lines.push(`  • ${s.path}: artifact ${s.expected.slice(0, 18)}…, on disk ${s.actual.slice(0, 18)}…`);
    }
    for (const m of missing) {
      lines.push(`  • ${m}: file not found on disk`);
    }
    lines.push("Run `forge build` and retry.");
    throw new Error(lines.join("\n"));
  }
}

interface EtherscanSource {
  SourceCode: string;
  ContractName: string;
  CompilerVersion: string;
  OptimizationUsed: string;
  Runs: string;
  EVMVersion: string;
}

/**
 * Fetch verified source for a contract via the Etherscan v2 API.
 */
async function fetchEtherscanSource(
  address: string,
  chainId: number,
  apiKey: string
): Promise<EtherscanSource> {
  const url = "https://api.etherscan.io/v2/api";
  const r = await axios.get(url, {
    params: {
      chainid: chainId,
      module: "contract",
      action: "getsourcecode",
      address,
      apikey: apiKey,
    },
  });
  if (r.data.status !== "1") {
    throw new Error(
      `Etherscan getsourcecode failed: ${r.data.message ?? r.data.result}`
    );
  }
  const result = r.data.result?.[0];
  if (!result || !result.SourceCode) {
    throw new Error(`Etherscan returned no source for ${address}`);
  }
  return result as EtherscanSource;
}

/**
 * Parse Etherscan's SourceCode field into a Standard JSON Input object.
 *
 * Etherscan wraps standard-JSON inputs in extra braces (`{{ ... }}`). Single-
 * file flat verifications are returned as a plain string, in which case we
 * build a minimal Standard JSON Input around them.
 */
function buildStandardJsonInput(src: EtherscanSource): any {
  const sc = src.SourceCode.trim();

  // Standard JSON Input wrapped in {{...}}.
  if (sc.startsWith("{{") && sc.endsWith("}}")) {
    return JSON.parse(sc.slice(1, -1));
  }

  // Already a plain JSON object (rare path).
  if (sc.startsWith("{") && sc.endsWith("}")) {
    try {
      const parsed = JSON.parse(sc);
      if (parsed.sources) return parsed;
    } catch {
      // fall through to flat-source handling
    }
  }

  // Flat single-file source.
  return {
    language: "Solidity",
    sources: {
      [`${src.ContractName}.sol`]: { content: sc },
    },
    settings: {
      optimizer: {
        enabled: src.OptimizationUsed === "1",
        runs: Number(src.Runs) || 200,
      },
      ...(src.EVMVersion && src.EVMVersion !== "Default"
        ? { evmVersion: src.EVMVersion.toLowerCase() }
        : {}),
    },
  };
}

/**
 * Load a remote solc version by fetching the soljson directly and wrapping
 * it ourselves. solc-js's built-in loadRemoteVersion uses Node's Module._compile
 * which is not supported by Bun, so we do the equivalent with new Function so
 * the same code works under both runtimes.
 */
async function loadSolc(version: string): Promise<any> {
  const url = `https://binaries.soliditylang.org/bin/soljson-${version}.js`;
  const response = await axios.get(url, { responseType: "text" });
  const soljsonSource: string = response.data;

  // Soljson is an Emscripten-compiled UMD bundle. It references Node-style
  // globals like __dirname / __filename / require during init, so we feed
  // them in explicitly to keep the evaluation environment isolated.
  const moduleObj: { exports: any } = { exports: {} };
  const evaluator = new Function(
    "module",
    "exports",
    "require",
    "__dirname",
    "__filename",
    soljsonSource
  );
  const fakeRequire = (id: string) => {
    throw new Error(`soljson tried to require '${id}' at runtime`);
  };
  evaluator(moduleObj, moduleObj.exports, fakeRequire, "/", "/soljson.js");

  const soljson = moduleObj.exports?.default ?? moduleObj.exports;

  const wrapperMod = await import("solc/wrapper");
  const wrapper = (wrapperMod as any).default ?? wrapperMod;
  return wrapper(soljson);
}

/**
 * Compile Etherscan-verified source with the exact compiler version Etherscan
 * reports, asking for storage layout output. Returns the deployed contract's
 * storage layout.
 */
export async function fetchDeployedLayout(
  implAddress: string,
  chainId: number,
  etherscanApiKey: string
): Promise<StorageLayout> {
  console.log(`  Fetching verified source for ${implAddress} from Etherscan...`);
  const src = await fetchEtherscanSource(implAddress, chainId, etherscanApiKey);
  console.log(`  Compiler: ${src.CompilerVersion}`);
  console.log(`  Contract: ${src.ContractName}`);

  const input = buildStandardJsonInput(src);

  // Ensure storageLayout is in outputSelection (overrides Etherscan's settings).
  input.settings = input.settings ?? {};
  input.settings.outputSelection = {
    "*": {
      "*": ["storageLayout"],
    },
  };

  // solc.loadRemoteVersion expects the version string WITH the leading "v":
  // "v0.8.27+commit.40a35a09" (matches the soljson-<v>.js filename).
  const version = src.CompilerVersion.startsWith("v")
    ? src.CompilerVersion
    : "v" + src.CompilerVersion;

  console.log(`  Loading solc ${version} (remote download, first run only)...`);
  const compiler = await loadSolc(version);

  console.log(`  Compiling...`);
  const output = JSON.parse(compiler.compile(JSON.stringify(input)));

  const errors = (output.errors ?? []).filter(
    (e: any) => e.severity === "error"
  );
  if (errors.length > 0) {
    const msg = errors.map((e: any) => e.formattedMessage ?? e.message).join("\n");
    throw new Error(`solc compile errors:\n${msg}`);
  }

  // Find the ChainResolver contract in the compiled output.
  for (const file of Object.keys(output.contracts ?? {})) {
    const contracts = output.contracts[file];
    if (contracts.ChainResolver?.storageLayout) {
      return contracts.ChainResolver.storageLayout as StorageLayout;
    }
  }

  throw new Error(
    "ChainResolver not found in compiled output from Etherscan source"
  );
}

/**
 * Compare a deployed storage layout to the new one. Returns issues if any
 * deployed slot has been removed, reordered, renamed, or had its type changed.
 * Appended variables are allowed (and reported separately for visibility).
 */
export function compareLayouts(
  deployed: StorageLayout,
  fresh: StorageLayout
): LayoutComparison {
  const issues: string[] = [];

  const freshByKey = new Map<string, StorageVar>();
  for (const v of fresh.storage) {
    freshByKey.set(`${v.slot}:${v.offset}`, v);
  }

  const deployedKeys = new Set<string>();
  for (const dep of deployed.storage) {
    const key = `${dep.slot}:${dep.offset}`;
    deployedKeys.add(key);
    const nw = freshByKey.get(key);

    if (!nw) {
      issues.push(
        `Slot ${dep.slot}.${dep.offset}: deployed had "${dep.label}", new layout has nothing at this position`
      );
      continue;
    }

    if (dep.label !== nw.label) {
      issues.push(
        `Slot ${dep.slot}.${dep.offset}: variable renamed "${dep.label}" → "${nw.label}"`
      );
    }

    const depType = deployed.types[dep.type]?.label ?? dep.type;
    const nwType = fresh.types[nw.type]?.label ?? nw.type;
    if (depType !== nwType) {
      issues.push(
        `Slot ${dep.slot}.${dep.offset} ("${dep.label}"): type changed "${depType}" → "${nwType}"`
      );
    }

    const depSize = deployed.types[dep.type]?.numberOfBytes;
    const nwSize = fresh.types[nw.type]?.numberOfBytes;
    if (depSize && nwSize && depSize !== nwSize) {
      issues.push(
        `Slot ${dep.slot}.${dep.offset} ("${dep.label}"): size changed ${depSize} → ${nwSize} bytes`
      );
    }
  }

  const appended = fresh.storage.filter(
    (v) => !deployedKeys.has(`${v.slot}:${v.offset}`)
  );

  return { compatible: issues.length === 0, issues, appended };
}

/**
 * Pretty-print a layout side-by-side row.
 */
export function printLayoutTable(layout: StorageLayout, title: string): void {
  console.log(`\n${title}`);
  console.log(`${"slot".padEnd(6)} ${"label".padEnd(36)} type`);
  console.log("-".repeat(80));
  for (const v of layout.storage) {
    const t = layout.types[v.type]?.label ?? v.type;
    console.log(`${v.slot.padEnd(6)} ${v.label.padEnd(36)} ${t}`);
  }
}
