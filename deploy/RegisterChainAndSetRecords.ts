// Register a chain and set records in the unified ChainResolver
import 'dotenv/config'

import { init } from "./libs/init.ts";
import {
  initSmith,
  shutdownSmith,
  askQuestion,
  promptContinueOrExit,
} from "./libs/utils.ts";
import {
  Contract,
  Interface,
  keccak256,
  toUtf8Bytes,
  toBeHex,
  isHexString,
  hexlify,
} from "ethers";
import * as contentHash from 'content-hash';
import { CID } from 'multiformats/cid';

async function encodeContenthash(input: string): Promise<string> {
  // Trim optional wrapping quotes
  input = input.trim();
  if ((input.startsWith("'") && input.endsWith("'")) || (input.startsWith('"') && input.endsWith('"'))) {
    input = input.slice(1, -1);
  }
  // Hex path
  if (isHexString(input)) return input;
  // IPFS/IPNS convenience
  const lower = input.toLowerCase();
  if (lower.startsWith('ipfs://') || lower.startsWith('ipns://')) {
    try {
      const mod: any = await import('content-hash');
      const ch = mod.default ?? mod;
      const ns = lower.startsWith('ipfs://') ? 'ipfs-ns' : 'ipns-ns';
      const cid = input.replace(/^ipfs:\/\//i, '').replace(/^ipns:\/\//i, '');
      const encoded = ch.encode(ns, cid);
      return '0x' + encoded;
    } catch (e) {
      throw new Error("content-hash package not available. Provide hex 0x.. bytes or `bun add content-hash`.");
    }
  }
  throw new Error("Unsupported contenthash format. Use 0x.. hex or ipfs:// / ipns://");
}

function toBytesLike(input: string): string {
  if (!input) return "0x";
  if (isHexString(input)) return input;
  return hexlify(toUtf8Bytes(input));
}

async function encodeContenthash(input: string): Promise<string> {
  input = input.trim();

  // Strip optional wrapping quotes
  if ((input.startsWith("'") && input.endsWith("'")) || (input.startsWith('"') && input.endsWith('"'))) {
    input = input.slice(1, -1);
  }

  // Hex contenthash (with or without 0x)
  if (isHexString(input)) {
    const hex = input.startsWith('0x') ? input.slice(2) : input;
    try {
      (contentHash as any).decode(hex);
      return '0x' + hex;
    } catch {
      throw new Error('Invalid contenthash hex encoding');
    }
  }

  const lower = input.toLowerCase();

  // IPFS / IPNS
  if (lower.startsWith('ipfs://') || lower.startsWith('ipns://')) {
    const isIpfs = lower.startsWith('ipfs://');
    const ns = isIpfs ? 'ipfs-ns' : 'ipns-ns';
    let value = input.replace(/^ipfs:\/\//i, '').replace(/^ipns:\/\//i, '');
    if (isIpfs) {
      try {
        value = CID.parse(value).toString();
      } catch (err) {
        throw new Error('Invalid CID in ipfs URL: ' + String(err));
      }
    } else {
      try { value = CID.parse(value).toString(); } catch {}
    }
    const encoded = (contentHash as any).encode(ns, value);
    return '0x' + encoded;
  }

  // Swarm / BZZ
  if (lower.startsWith('bzz://') || lower.startsWith('swarm://')) {
    const valuePart = input.slice(input.indexOf('://') + 3);
    if (!isHexString(valuePart)) {
      throw new Error('Swarm content must be hex hash');
    }
    const clean = valuePart.startsWith('0x') ? valuePart.slice(2) : valuePart;
    const encoded = (contentHash as any).encode('swarm-ns', clean);
    return '0x' + encoded;
  }

  // Optional generic URI
  if (lower.startsWith('data:') || lower.startsWith('uri:') || lower.startsWith('http://') || lower.startsWith('https://')) {
    try {
      const encoded = (contentHash as any).encode('uri', input);
      return '0x' + encoded;
    } catch {
      throw new Error('URI / data protocol not supported by content-hash codec');
    }
  }

  throw new Error('Unsupported contenthash format. Use 0x… hex, ipfs://, ipns://, bzz://');
}

const { chainId, privateKey } = await init();
const { deployerWallet, smith, rl } = await initSmith(
  typeof chainId === "number" ? chainId : Number(chainId),
  privateKey
);

try {
  // Resolve ChainResolver address (env > prompt)
  let resolverAddress: string | undefined;
  try {
    const envRes = (process.env.CHAIN_RESOLVER_ADDRESS || process.env.RESOLVER_ADDRESS || "").trim();
    if (envRes) {
      const code = await deployerWallet.provider.getCode(envRes);
      if (code && code !== "0x") resolverAddress = envRes;
    }
  } catch {}
  if (!resolverAddress) resolverAddress = (await askQuestion(rl, "ChainResolver address: ")).trim();
  if (!resolverAddress) {
    console.error("ChainResolver address is required.");
    process.exit(1);
  }

  const resolver = new Contract(
    resolverAddress,
    [
      "function register(string,address,bytes) external",
      "function chainId(bytes32) view returns (bytes)",
      "function chainName(bytes) view returns (string)",
      "function setAddr(bytes32,uint256,address) external",
      "function setContenthash(bytes32,bytes) external",
      "function setText(bytes32,string,string) external",
      "function setData(bytes32,bytes,bytes) external",
    ],
    deployerWallet
  );

  // Inputs
  const label = (await askQuestion(rl, "Chain label (e.g. optimism): ")).trim();
  const labelHash = keccak256(toUtf8Bytes(label));
  let cidIn = (await askQuestion(rl, "Chain ID (hex 0x.. or decimal): ")).trim();
  if (!isHexString(cidIn)) cidIn = toBeHex(BigInt(cidIn));
  const ownerIn = (await askQuestion(rl, `Owner [default ${deployerWallet.address}]: `)).trim();
  const owner = ownerIn || deployerWallet.address;

  // Register in unified resolver (owner-only)
  console.log("Registering in ChainResolver...");
  let ok = await promptContinueOrExit(rl, "Proceed? (y/n): ");
  if (ok) {
    try {
      const tx = await resolver.register(label, owner, cidIn);
      await tx.wait();
      console.log("✓ resolver.register");
    } catch (e: any) {
      const errIface = new Interface([
        "error LabelAlreadyRegistered(bytes32)",
        "error NotAuthorized(address,bytes32)",
      ]);
      const data: string | undefined = e?.data || e?.error?.data || e?.info?.error?.data;
      let decoded = undefined as any;
      try { if (data && typeof data === 'string') decoded = errIface.parseError(data); } catch {}
      const short = e?.shortMessage || e?.message || "";
      if (decoded?.name === 'LabelAlreadyRegistered' || /LabelAlreadyRegistered/.test(short)) {
        console.log("✗ Label already registered (skipping)");
      } else if (/Ownable: caller is not the owner|NotAuthorized/.test(short)) {
        console.log("✗ Not authorized to register this label (owner-only)");
      } else {
        console.error("✗ register failed:", short);
      }
    }
  }

  // Quick sanity
  try {
    const cid = await resolver.chainId(labelHash);
    const name = await resolver.chainName(cid);
    console.log("chainId:", cid, "chainName:", name);
  } catch {}

  // Optional records
  console.log("\nOptional records: The following prompts are optional.");
  console.log("You can answer 'n' to skip any of them.\n");
  if (await promptContinueOrExit(rl, "Set addr(60)? (y/n): ")) {
    const a60 = (await askQuestion(rl, "ETH address: ")).trim();
    const tx = await resolver.setAddr(labelHash, 60, a60);
    await tx.wait();
    console.log("✓ setAddr(60)");
  }

  if (await promptContinueOrExit(rl, "Set another addr with custom coinType? (y/n): ")) {
    const ctStr = (await askQuestion(rl, "coinType (uint): ")).trim();
    const ct = BigInt(ctStr);
    const addr = (await askQuestion(rl, "address: ")).trim();
    const tx = await resolver.setAddr(labelHash, ct, addr);
    await tx.wait();
    console.log(`✓ setAddr(${ct})`);
  }

  if (await promptContinueOrExit(rl, "Set contenthash? (y/n): ")) {
    const chIn = (await askQuestion(rl, "contenthash (ipfs://, ipns://, bzz:// or 0x..): ")).trim();
    const ch = await encodeContenthash(chIn);
    const tx = await resolver.setContenthash(labelHash, ch);
    await tx.wait();
    console.log("✓ setContenthash");
  }

  if (await promptContinueOrExit(rl, "Set text('avatar')? (y/n): ")) {
    const url = (await askQuestion(rl, "avatar URL: ")).trim();
    const tx = await resolver.setText(labelHash, "avatar", url);
    await tx.wait();
    console.log("✓ setText(avatar)");
  }

  if (await promptContinueOrExit(rl, "Set arbitrary text(key,value)? (y/n): ")) {
    const key = (await askQuestion(rl, "text key: ")).trim();
    const val = (await askQuestion(rl, "text value: ")).trim();
    const tx = await resolver.setText(labelHash, key, val);
    await tx.wait();
    console.log(`✓ setText(${key})`);
  }

  if (await promptContinueOrExit(rl, "Set data(keyBytes,valueBytes)? (y/n): ")) {
    const k = (await askQuestion(rl, "data key (utf8 or 0x..): ")).trim();
    const v = (await askQuestion(rl, "data value (utf8 or 0x..): ")).trim();
    const keyBytes = toBytesLike(k);
    const valBytes = toBytesLike(v);
    const tx = await resolver.setData(labelHash, keyBytes, valBytes);
    await tx.wait();
    console.log("✓ setData");
  }

  console.log("Done.");
} finally {
  await shutdownSmith(rl, smith);
}
