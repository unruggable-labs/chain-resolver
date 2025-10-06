// Forward resolve records by label via ENSIP-10

import 'dotenv/config'
import { initSmith, shutdownSmith, loadDeployment, askQuestion } from "./libs/utils.ts";
import { init } from "./libs/init.ts";
import { Contract, Interface, dnsEncode, keccak256, toUtf8Bytes, isHexString, hexlify } from "ethers";

function toBytesLike(input: string): string {
  if (!input) return "0x";
  if (isHexString(input)) return input;
  return hexlify(toUtf8Bytes(input));
}

// Initialize context
const { chainId, privateKey } = await init();
const { deployerWallet, smith, rl } = await initSmith(
  typeof chainId === "number" ? chainId : Number(chainId),
  privateKey
);

try {
  // Use deployed ChainResolver only
  let resolverAddress: string | undefined;
  try {
    const res = await loadDeployment(chainId, "ChainResolver");
    const found = res.target as string;
    const code = await deployerWallet.provider.getCode(found);
    if (code && code !== '0x') {
      resolverAddress = found;
      console.log(`[Found] ChainResolver at ${resolverAddress}`);
    } else {
      console.log(`[Warn] Deployment file exists but no code at ${found} on chain ${chainId}.`);
    }
  } catch {}
  if (!resolverAddress) {
    resolverAddress = process.env.CHAIN_RESOLVER_ADDRESS || process.env.RESOLVER_ADDRESS || "";
  }
  if (!resolverAddress) {
    resolverAddress = (await askQuestion(rl, "Enter ChainResolver address: ")).trim();
  }
  if (!resolverAddress) {
    console.error("ChainResolver address is required.");
    process.exit(1);
  }

  const resolver = new Contract(
    resolverAddress!,
    ["function resolve(bytes name, bytes data) view returns (bytes)"],
    deployerWallet
  );

  // ABI for encoding/decoding queries through ENSIP-10
  const IFACE = new Interface([
    "function addr(bytes32) view returns (address)",
    "function addr(bytes32,uint256) view returns (address)",
    "function contenthash(bytes32) view returns (bytes)",
    "function text(bytes32,string) view returns (string)",
    "function data(bytes32,bytes) view returns (bytes)",
  ]);

  // Gather label and prepare DNS/namehash inputs
  const label = (await askQuestion(rl, "Label (e.g. optimism): ")).trim();
  const ensName = `${label}.cid.eth`;
  const dnsName = dnsEncode(ensName, 255);
  const labelHash = keccak256(toUtf8Bytes(label));
  console.log("Using:", { ensName, labelHash });

  // Helper to call resolve() and decode results for standard records
  async function resolveDecode(sig: string, args: any[]) {
    const call = IFACE.encodeFunctionData(sig, args);
    const answer: string = await resolver.resolve(dnsName, call);
    const [decoded] = IFACE.decodeFunctionResult(sig, answer);
    return decoded;
  }

  // Resolve chain-id (hex string, no 0x prefix)
  try {
    const hexCid = await resolveDecode("text(bytes32,string)", [labelHash, "chain-id"]);
    console.log(`Chain ID: 0x${hexCid}`);
  } catch (e) {
    console.error((e as Error).message);
    process.exit(1);
  }
} finally {
  await shutdownSmith(rl, smith);
}
