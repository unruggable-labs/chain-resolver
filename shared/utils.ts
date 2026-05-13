// Shared utility functions
import readline from "node:readline";
import fs from "node:fs";
import path from "node:path";
import * as dotenv from "dotenv";

/**
 * Walk up from `startDir` looking for a `.env` file and load it if found.
 * Stops at the filesystem root, or one level past the first ancestor that
 * contains a `.git` entry (so we don't escape the repo into an unrelated
 * parent project).
 *
 * This makes deploy scripts work identically whether invoked from the main
 * checkout or from a git worktree (worktrees don't carry gitignored files
 * like `.env`).
 *
 * Idempotent — calling more than once is a no-op. Returns the path that
 * was loaded, or null if none was found.
 */
let _envLoadedFrom: string | null | undefined = undefined;

export function loadEnvFromAncestors(
  startDir: string = process.cwd()
): string | null {
  if (_envLoadedFrom !== undefined) return _envLoadedFrom;

  let dir = path.resolve(startDir);
  let crossedGitBoundary = false;

  while (true) {
    const candidate = path.join(dir, ".env");
    if (fs.existsSync(candidate)) {
      dotenv.config({ path: candidate, override: false, quiet: true });
      _envLoadedFrom = candidate;
      return candidate;
    }

    if (fs.existsSync(path.join(dir, ".git"))) {
      if (crossedGitBoundary) {
        _envLoadedFrom = null;
        return null;
      }
      crossedGitBoundary = true;
    }

    const parent = path.dirname(dir);
    if (parent === dir) {
      _envLoadedFrom = null;
      return null;
    }
    dir = parent;
  }
}

/**
 * Create a readline interface for interactive prompts
 */
export function createReadlineInterface(): readline.Interface {
  return readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });
}

/**
 * Ask a question and return the answer
 * @param rl Readline interface
 * @param query The question to ask
 * @param options Options for processing the answer
 */
export function askQuestion(
  rl: readline.Interface,
  query: string,
  options: { trim?: boolean; lowercase?: boolean } = {}
): Promise<string> {
  const { trim = true, lowercase = false } = options;
  return new Promise((resolve) => {
    rl.question(query, (answer) => {
      let result = answer;
      if (trim) result = result.trim();
      if (lowercase) result = result.toLowerCase();
      resolve(result);
    });
  });
}

/**
 * Prompt user to continue, skip, or exit
 * @returns true to continue, false to skip
 */
export async function promptContinueOrExit(
  rl: readline.Interface,
  question: string = "Do you want to continue? (y/n): "
): Promise<boolean> {
  const answer = await askQuestion(rl, question, { lowercase: true });

  if (answer === "y" || answer === "yes") {
    console.log("Continuing...");
    return true;
  } else if (answer === "n" || answer === "no") {
    console.log("Skipping...");
    return false;
  } else if (answer === "e" || answer === "exit") {
    console.log("Exiting...");
    process.exit(0);
  } else {
    console.log('Invalid input. Please enter "y" to continue, "n" to skip, or "e" to exit.');
    return promptContinueOrExit(rl, question);
  }
}

/**
 * Die with an error if value is not set
 */
export function setOrDie(value: unknown, name: string = "Value"): void {
  if (!value) {
    throw new Error(`${name} is not set`);
  }
}

/**
 * DNS encode a name (for viem which doesn't have built-in dnsEncode)
 */
export function dnsEncode(name: string): `0x${string}` {
  const labels = name.split(".");
  let result = "";
  for (const label of labels) {
    const length = label.length;
    result += length.toString(16).padStart(2, "0");
    for (let i = 0; i < label.length; i++) {
      result += label.charCodeAt(i).toString(16).padStart(2, "0");
    }
  }
  result += "00"; // null terminator
  return `0x${result}`;
}

/**
 * Print a section header
 */
export function section(name: string): void {
  console.log(`\n${"=".repeat(50)}\n${name}\n${"=".repeat(50)}`);
}

/**
 * Log with indentation
 */
export function log(...args: unknown[]): void {
  console.log("  →", ...args);
}

