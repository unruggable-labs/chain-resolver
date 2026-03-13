#!/usr/bin/env bun
/**
 * Validates chain JSON files in data/chains/
 *
 * Usage:
 *   bun run scripts/validate-chains.ts              # Report validation status (no exit code)
 *   bun run scripts/validate-chains.ts --strict     # Exit 1 if any errors (for CI)
 *   bun run scripts/validate-chains.ts --changed    # Only validate changed files
 *   bun run scripts/validate-chains.ts --changed --strict  # CI mode for PRs
 *   bun run scripts/validate-chains.ts --check-registry    # Also check on-chain registration
 */

import "dotenv/config";
import { readdirSync, readFileSync, existsSync } from "fs";
import { join, basename } from "path";
import { execSync } from "child_process";
import { decodeAddress } from "@wonderland/interop-addresses";
import { Contract, JsonRpcProvider } from "ethers";
import { RESOLVER_ABI } from "../shared/abis.ts";

const CHAINS_DIR = "data/chains";

interface ChainData {
  label: string;
  chainName: string;
  interoperableAddressHex: string;
  aliases?: string[];
  textRecords?: Record<string, string>;
}

interface ValidationResult {
  file: string;
  errors: string[];
}

// CAIP-2 chain ID pattern: namespace:reference
const CAIP2_PATTERN = /^[-a-z0-9]{3,8}:[-_a-zA-Z0-9]{1,32}$/;

// Label pattern: lowercase, alphanumeric, hyphens
const LABEL_PATTERN = /^[a-z0-9]+(-[a-z0-9]+)*$/;

// Hex pattern for interoperable address (must have at least some hex digits)
const HEX_PATTERN = /^0x[0-9a-fA-F]+$/;

// IPFS URL pattern
const IPFS_PATTERN = /^ipfs:\/\/[a-zA-Z0-9]+$/;

// URL pattern (loose)
const URL_PATTERN = /^https?:\/\/.+/;

function validateChain(
  filePath: string,
  content: string,
  labelCounts: Map<string, number>,
  allLabels: Set<string>,
  allAliases: Map<string, string>
): string[] {
  const errors: string[] = [];
  const fileName = basename(filePath, ".json");

  // Skip template files
  if (fileName.startsWith("_")) {
    return [];
  }

  // Parse JSON
  let chain: ChainData;
  try {
    chain = JSON.parse(content);
  } catch (e) {
    errors.push(`Invalid JSON: ${(e as Error).message}`);
    return errors;
  }

  // Required fields
  if (!chain.label) {
    errors.push("Missing required field: label");
  } else {
    // Label format
    if (!LABEL_PATTERN.test(chain.label)) {
      errors.push(`Invalid label format: "${chain.label}" (must be lowercase, alphanumeric, hyphens only)`);
    }
    // Label matches filename
    if (chain.label !== fileName) {
      errors.push(`Label "${chain.label}" does not match filename "${fileName}.json"`);
    }
    // Duplicate label check (count > 1 means duplicate)
    const count = labelCounts.get(chain.label) || 0;
    if (count > 1) {
      errors.push(`Duplicate label: "${chain.label}" exists in multiple files`);
    }
  }

  if (!chain.chainName) {
    errors.push("Missing required field: chainName");
  }

  // interoperableAddressHex is required and must be non-empty
  if (chain.interoperableAddressHex === undefined || chain.interoperableAddressHex === null) {
    errors.push("Missing required field: interoperableAddressHex");
  } else if (chain.interoperableAddressHex === "") {
    errors.push("interoperableAddressHex cannot be empty");
  } else if (!HEX_PATTERN.test(chain.interoperableAddressHex)) {
    errors.push(`Invalid interoperableAddressHex: must be hex string starting with 0x`);
  } else {
    // Try to decode and cross-check against chainId
    // Note: isValidBinaryAddress may fail for newer chain types not yet in the library
    try {
      const decoded = decodeAddress(chain.interoperableAddressHex);
      const expectedChainId = `${decoded.chainType}:${decoded.chainReference}`;

      if (chain.textRecords?.chainId && chain.textRecords.chainId !== expectedChainId) {
        errors.push(
          `interoperableAddressHex mismatch: encodes "${expectedChainId}" but textRecords.chainId is "${chain.textRecords.chainId}"`
        );
      }
    } catch (e) {
      const errMsg = (e as Error).message;
      // Allow unsupported chain types (library may not support all types yet)
      // But fail on actual decode errors
      if (!errMsg.includes("Unsupported chain type")) {
        errors.push(`Failed to decode interoperableAddressHex: ${errMsg}`);
      }
    }
  }

  // Text records validation
  if (chain.textRecords) {
    // chainId is required in textRecords
    if (!chain.textRecords.chainId) {
      errors.push("Missing required field: textRecords.chainId");
    } else if (!CAIP2_PATTERN.test(chain.textRecords.chainId)) {
      errors.push(`Invalid chainId format: "${chain.textRecords.chainId}" (must be CAIP-2, e.g., "eip155:1")`);
    }

    // Check all text records - if a key is defined, it must have a value
    for (const [key, value] of Object.entries(chain.textRecords)) {
      if (value === "") {
        errors.push(`Empty value for textRecords.${key} (remove the field or provide a value)`);
      }
    }

    // Validate image URLs use IPFS (if present and non-empty)
    for (const key of ["avatar", "header"]) {
      const value = chain.textRecords[key];
      if (value && value !== "") {
        if (URL_PATTERN.test(value)) {
          errors.push(`${key} should use ipfs:// URL, not HTTP: "${value}"`);
        } else if (!IPFS_PATTERN.test(value)) {
          errors.push(`${key} has invalid format: "${value}" (expected ipfs:// URL)`);
        }
      }
    }

    // Validate other URLs (if present and non-empty)
    const urlFields = ["url", "brand", "com.x", "com.discord", "com.github", "com.youtube", "com.linkedin", "org.telegram"];
    for (const key of urlFields) {
      const value = chain.textRecords[key];
      if (value && value !== "" && !URL_PATTERN.test(value)) {
        errors.push(`Invalid URL for ${key}: "${value}"`);
      }
    }
  } else {
    errors.push("Missing required field: textRecords");
  }

  // Aliases validation
  if (chain.aliases && Array.isArray(chain.aliases)) {
    for (const alias of chain.aliases) {
      if (!LABEL_PATTERN.test(alias)) {
        errors.push(`Invalid alias format: "${alias}" (must be lowercase, alphanumeric, hyphens only)`);
      }
      // Check for alias conflicts
      if (allLabels.has(alias)) {
        errors.push(`Alias "${alias}" conflicts with existing chain label`);
      }
      const existingOwner = allAliases.get(alias);
      if (existingOwner && existingOwner !== chain.label) {
        errors.push(`Alias "${alias}" already used by chain "${existingOwner}"`);
      }
    }
  }

  return errors;
}

function getChangedFiles(): string[] {
  try {
    // Get files changed compared to main/master branch
    const baseBranch = execSync("git rev-parse --abbrev-ref origin/HEAD 2>/dev/null || echo origin/main", { encoding: "utf8" }).trim();
    const output = execSync(`git diff --name-only ${baseBranch}...HEAD -- "${CHAINS_DIR}/*.json"`, { encoding: "utf8" });
    return output.split("\n").filter(f => f.trim() !== "");
  } catch {
    // Fallback: get all staged/modified files
    try {
      const output = execSync(`git diff --name-only HEAD -- "${CHAINS_DIR}/*.json"`, { encoding: "utf8" });
      return output.split("\n").filter(f => f.trim() !== "");
    } catch {
      return [];
    }
  }
}

async function checkRegistryStatus(labels: string[]): Promise<Map<string, boolean>> {
  const registryStatus = new Map<string, boolean>();

  const rpcUrl = process.env.MAINNET_RPC_URL;
  let proxyAddress = process.env.MAINNET_PROXY_ADDRESS;

  // Fallback: try to read from deployment file
  if (!proxyAddress) {
    try {
      const deploymentPath = join("deployments", "1", "[Proxy]ERC1967Proxy.json");
      if (existsSync(deploymentPath)) {
        const deployment = JSON.parse(readFileSync(deploymentPath, "utf8"));
        proxyAddress = deployment.target;
      }
    } catch {}
  }

  if (!rpcUrl) {
    console.log("⚠️  Registry check skipped: MAINNET_RPC_URL not set\n");
    return registryStatus;
  }

  if (!proxyAddress) {
    console.log("⚠️  Registry check skipped: MAINNET_PROXY_ADDRESS not set and no deployment found\n");
    return registryStatus;
  }

  try {
    const provider = new JsonRpcProvider(rpcUrl);
    const resolver = new Contract(proxyAddress, RESOLVER_ABI, provider);

    console.log(`Checking registry status for ${labels.length} chains...`);

    for (const label of labels) {
      try {
        const admin = await resolver.getChainAdmin!(label);
        const isRegistered = admin && admin !== "0x0000000000000000000000000000000000000000";
        registryStatus.set(label, isRegistered);
      } catch {
        registryStatus.set(label, false);
      }
    }

    console.log("Registry check complete.\n");
  } catch (e) {
    console.log(`⚠️  Registry check failed: ${(e as Error).message}\n`);
  }

  return registryStatus;
}

async function main() {
  const args = process.argv.slice(2);
  const changedOnly = args.includes("--changed");
  const strictMode = args.includes("--strict");
  const checkRegistry = args.includes("--check-registry");

  console.log("Validating chain files...\n");

  // Get all chain files for duplicate checking
  const allFiles = readdirSync(CHAINS_DIR)
    .filter(f => f.endsWith(".json") && !f.startsWith("_"))
    .map(f => join(CHAINS_DIR, f));

  // Build counts of labels and map of aliases (for duplicate detection)
  const labelCounts = new Map<string, number>();
  const allAliases = new Map<string, string>();
  const allLabels = new Set<string>();

  // First pass: collect all labels and aliases
  for (const filePath of allFiles) {
    try {
      const content = readFileSync(filePath, "utf8");
      const chain = JSON.parse(content) as ChainData;
      if (chain.label) {
        labelCounts.set(chain.label, (labelCounts.get(chain.label) || 0) + 1);
        allLabels.add(chain.label);
      }
      if (chain.aliases) {
        for (const alias of chain.aliases) {
          allAliases.set(alias, chain.label);
        }
      }
    } catch {
      // Will be caught in validation pass
    }
  }

  // Determine which files to validate
  let filesToValidate: string[];
  if (changedOnly) {
    const changedFiles = getChangedFiles();
    filesToValidate = changedFiles.filter(f => existsSync(f));
    if (filesToValidate.length === 0) {
      console.log("No changed chain files to validate.");
      process.exit(0);
    }
    console.log(`Validating ${filesToValidate.length} changed file(s):\n`);
  } else {
    filesToValidate = allFiles;
    console.log(`Validating ${filesToValidate.length} chain file(s):\n`);
  }

  // Check registry status if requested
  let registryStatus = new Map<string, boolean>();
  if (checkRegistry) {
    const labels = filesToValidate
      .filter(f => !basename(f).startsWith("_"))
      .map(f => {
        try {
          const content = readFileSync(f, "utf8");
          return JSON.parse(content).label as string;
        } catch {
          return null;
        }
      })
      .filter((l): l is string => l !== null);

    registryStatus = await checkRegistryStatus(labels);
  }

  // Validate files and group results
  interface ChainResult {
    file: string;
    label: string;
    errors: string[];
    isRegistered: boolean;
  }

  const results: ChainResult[] = [];

  for (const filePath of filesToValidate) {
    const fileName = basename(filePath);

    // Skip template
    if (fileName.startsWith("_")) {
      continue;
    }

    const content = readFileSync(filePath, "utf8");
    let label = fileName.replace(".json", "");
    try {
      label = JSON.parse(content).label || label;
    } catch {}

    const errors = validateChain(filePath, content, labelCounts, allLabels, allAliases);
    const isRegistered = registryStatus.get(label) ?? false;

    results.push({ file: fileName, label, errors, isRegistered });
  }

  // Group and display results
  if (checkRegistry) {
    const registered = results.filter(r => r.isRegistered);
    const unregistered = results.filter(r => !r.isRegistered);

    console.log("═".repeat(50));
    console.log("REGISTERED CHAINS");
    console.log("═".repeat(50));

    if (registered.length === 0) {
      console.log("(none)\n");
    } else {
      for (const r of registered) {
        if (r.errors.length > 0) {
          console.log(`❌ ${r.file}`);
          for (const error of r.errors) {
            console.log(`   - ${error}`);
          }
        } else {
          console.log(`✓ ${r.file}`);
        }
      }
      const regValid = registered.filter(r => r.errors.length === 0).length;
      const regErrors = registered.filter(r => r.errors.length > 0).length;
      console.log(`\nRegistered: ${regValid} valid, ${regErrors} with errors\n`);
    }

    console.log("═".repeat(50));
    console.log("UNREGISTERED CHAINS");
    console.log("═".repeat(50));

    if (unregistered.length === 0) {
      console.log("(none)\n");
    } else {
      for (const r of unregistered) {
        if (r.errors.length > 0) {
          console.log(`❌ ${r.file}`);
          for (const error of r.errors) {
            console.log(`   - ${error}`);
          }
        } else {
          console.log(`✓ ${r.file}`);
        }
      }
      const unregValid = unregistered.filter(r => r.errors.length === 0).length;
      const unregErrors = unregistered.filter(r => r.errors.length > 0).length;
      console.log(`\nUnregistered: ${unregValid} valid, ${unregErrors} with errors\n`);
    }
  } else {
    // Standard output (no grouping)
    for (const r of results) {
      if (r.errors.length > 0) {
        console.log(`❌ ${r.file}`);
        for (const error of r.errors) {
          console.log(`   - ${error}`);
        }
      } else {
        console.log(`✓ ${r.file}`);
      }
    }
  }

  // Summary
  const validCount = results.filter(r => r.errors.length === 0).length;
  const errorCount = results.filter(r => r.errors.length > 0).length;

  console.log("─".repeat(50));
  console.log(`Total: ${validCount} valid, ${errorCount} with errors`);

  if (errorCount > 0 && strictMode) {
    process.exit(1);
  }
}

main().catch(e => {
  console.error(e);
  process.exit(1);
});
