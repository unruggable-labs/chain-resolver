// Register a chain and optionally set records
import 'dotenv/config'

import { init } from "./libs/init.ts";
import {
  initSmith,
  shutdownSmith,
  askQuestion,
  promptContinueOrExit,
  loadDeployment,
} from "./libs/utils.ts";
import {
  Contract,
  Interface,
  dnsEncode,
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
  // Resolve ChainResolver address (deployments JSON > env > prompt)
  let resolverAddress: string | undefined;
  try {
    const dep = await loadDeployment(chainId, "ChainResolver");
    const found = dep.target as string;
    const code = await deployerWallet.provider.getCode(found);
    if (code && code !== "0x") resolverAddress = found;
  } catch {}
  try {
    if (!resolverAddress) {
      const envRes = (process.env.CHAIN_RESOLVER_ADDRESS || process.env.RESOLVER_ADDRESS || "").trim();
      if (envRes) {
        const code = await deployerWallet.provider.getCode(envRes);
        if (code && code !== "0x") resolverAddress = envRes;
      }
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
      "function owner() view returns (address)",
      "function resolve(bytes,bytes) view returns (bytes)",
      "function chainId(bytes32) view returns (bytes)",
      "function chainName(bytes) view returns (string)",
      "function getOwner(bytes32) view returns (address)",
      "function setAddr(bytes32,address) external",
      "function setAddr(bytes32,uint256,bytes) external",
      "function setContenthash(bytes32,bytes) external",
      "function setText(bytes32,string,string) external",
        "function setData(bytes32,string,bytes) external",
        "function register((string,string,address,bytes)) external",
      ],
      deployerWallet
    );

  // Inputs
  console.log("Using ChainResolver:", resolverAddress);
  try { console.log("Contract owner:", await resolver.owner()); } catch {}
  console.log("Caller:", deployerWallet.address);
  const label = (await askQuestion(rl, "Chain label (e.g. optimism): ")).trim();
  const labelhash = keccak256(toUtf8Bytes(label));
  const chainNameIn = (await askQuestion(rl, "Chain name (e.g. Optimism / OP Mainnet): ")).trim();
  const chainName = chainNameIn || label;
  let cidIn = (await askQuestion(rl, "Chain ID (hex 0x.. or decimal): ")).trim();
  if (!isHexString(cidIn)) cidIn = toBeHex(BigInt(cidIn));
  const ownerIn = (await askQuestion(rl, `Owner [default ${deployerWallet.address}]: `)).trim();
  const owner = ownerIn || deployerWallet.address;

  // Register in unified resolver (owner-only)
  console.log("Registering in ChainResolver (label + chain name)...");
  let ok = await promptContinueOrExit(rl, "Proceed? (y/n): ");
  if (ok) {
    try {
      const tx = await resolver.register([label, chainName, owner, cidIn]);
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
    const cid = await resolver.chainId(labelhash);
    const name = await resolver.chainName(cid);
    console.log("chainId:", cid, "chainName:", name);
    try { console.log("label owner:", await resolver.getOwner(labelhash)); } catch {}
  } catch {}

  // Optional records
  console.log("\nOptional records: The following prompts are optional.");
  console.log("You can answer 'n' to skip any of them.\n");
  if (await promptContinueOrExit(rl, "Set addr(60)? (y/n): ")) {
    const a60 = (await askQuestion(rl, "ETH address: ")).trim();
    try {
      const setAddr60 = resolver.getFunction("setAddr(bytes32,address)");
      const tx = await setAddr60(labelhash, a60);
      await tx.wait();
      console.log("✓ setAddr(60)");
    } catch (e: any) {
      // Fallback: some RPCs fail gas estimation or return opaque errors.
      // Decode common custom error if present, then try manual send.
      try {
        const errIface = new Interface(["error NotAuthorized(address,bytes32)"]);
        const data: string | undefined = e?.data || e?.error?.data || e?.info?.error?.data;
        if (data && typeof data === 'string') {
          const parsed = errIface.parseError(data);
          if (parsed?.name === 'NotAuthorized') {
            const [who, lh] = parsed.args as any[];
            console.error(`✗ NotAuthorized: caller=${who} labelhash=${lh}`);
          }
        }
      } catch {}
      try {
        const data = new Interface(["function setAddr(bytes32,address)"]).encodeFunctionData(
          "setAddr(bytes32,address)",
          [labelhash, a60]
        );
        const sent = await deployerWallet.sendTransaction({ to: resolverAddress, data, gasLimit: 200000n });
        await sent.wait();
        console.log("✓ setAddr(60) (fallback)");
      } catch (e2: any) {
        const msg = e2?.shortMessage || e2?.message || String(e2);
        console.error("✗ setAddr(60) failed:", msg);
      }
    }
  }

  if (await promptContinueOrExit(rl, "Set another addr with custom coinType? (y/n): ")) {
    const ctStr = (await askQuestion(rl, "coinType (uint): ")).trim();
    const ct = BigInt(ctStr);
    const addr = (await askQuestion(rl, "address (bytes: 0x.. or utf8): ")).trim();
    const val = toBytesLike(addr);
    try {
      const setAddrBytes = resolver.getFunction("setAddr(bytes32,uint256,bytes)");
      const tx = await setAddrBytes(labelhash, ct, val);
      await tx.wait();
      console.log(`✓ setAddr(${ct})`);
    } catch (e: any) {
      // Fallback with manual gas and error decode
      try {
        const errIface = new Interface(["error NotAuthorized(address,bytes32)"]);
        const data: string | undefined = e?.data || e?.error?.data || e?.info?.error?.data;
        if (data && typeof data === 'string') {
          const parsed = errIface.parseError(data);
          if (parsed?.name === 'NotAuthorized') {
            const [who, lh] = parsed.args as any[];
            console.error(`✗ NotAuthorized: caller=${who} labelhash=${lh}`);
          }
        }
      } catch {}
      try {
        const data = new Interface(["function setAddr(bytes32,uint256,bytes)"]).encodeFunctionData(
          "setAddr(bytes32,uint256,bytes)",
          [labelhash, ct, val]
        );
        const sent = await deployerWallet.sendTransaction({ to: resolverAddress, data, gasLimit: 250000n });
        await sent.wait();
        console.log(`✓ setAddr(${ct}) (fallback)`);
      } catch (e2: any) {
        const msg = e2?.shortMessage || e2?.message || String(e2);
        console.error(`✗ setAddr(${ct}) failed:`, msg);
      }
    }
  }

  if (await promptContinueOrExit(rl, "Set contenthash? (y/n): ")) {
    const chIn = (await askQuestion(rl, "contenthash (ipfs://, ipns://, bzz:// or 0x..): ")).trim();
    const ch = await encodeContenthash(chIn);
    const tx = await resolver.setContenthash(labelhash, ch);
    await tx.wait();
    console.log("✓ setContenthash");
  }

  // Show chain-id resolution examples
  if (await promptContinueOrExit(rl, "Resolve chain-id now? (y/n): ")) {
    const ensName = `${label}.cid.eth`;
    const dnsName = dnsEncode(ensName, 255);
    const IFACE = new Interface([
      'function text(bytes32,string) view returns (string)',
      'function data(bytes32,string) view returns (bytes)'
    ]);
    try {
      // Resolve chain-id via text(bytes32,string)
      const textCalldata = IFACE.encodeFunctionData('text(bytes32,string)', [labelhash, 'chain-id']);
      const textAnswer: string = await resolver.resolve(dnsName, textCalldata);
      const [hexCid] = IFACE.decodeFunctionResult('text(bytes32,string)', textAnswer);
      console.log('chain-id (text):', '0x' + hexCid);
    } catch (e: any) {
      console.warn('text(chain-id) resolve failed:', e?.shortMessage || e?.message || String(e));
    }
    try {
      // Resolve chain-id via data(bytes32,string)
      const dataCalldata = IFACE.encodeFunctionData('data(bytes32,string)', [labelhash, 'chain-id']);
      const dataAnswer: string = await resolver.resolve(dnsName, dataCalldata);
      const [cidBytes] = IFACE.decodeFunctionResult('data(bytes32,string)', dataAnswer);
      console.log('chain-id (data bytes):', cidBytes);
    } catch (e: any) {
      console.warn('data(chain-id) resolve failed:', e?.shortMessage || e?.message || String(e));
    }
  }

  if (await promptContinueOrExit(rl, "Set text(key,value)? (y/n): ")) {
    const key = (await askQuestion(rl, "text key: ")).trim();
    const val = (await askQuestion(rl, "text value: ")).trim();
    const tx = await resolver.setText(labelhash, key, val);
    await tx.wait();
    console.log(`✓ setText(${key})`);
  }

  if (await promptContinueOrExit(rl, "Set data(key,value)? (y/n): ")) {
    const k = (await askQuestion(rl, "data key (string): ")).trim();
    const v = (await askQuestion(rl, "data value (utf8 or 0x..): ")).trim();
    const valBytes = toBytesLike(v);
    const tx = await resolver.setData(labelhash, k, valBytes);
    await tx.wait();
    console.log("✓ setData");
  }

  console.log("Done.");
} finally {
  await shutdownSmith(rl, smith);
}
