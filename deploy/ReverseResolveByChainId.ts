// Reverse-resolve a chainId to a chain name

import 'dotenv/config'
import { init } from "./libs/init.ts";
import { initSmith, shutdownSmith, loadDeployment, askQuestion } from "./libs/utils.ts";
import { Contract, Interface, AbiCoder, dnsEncode, getBytes, hexlify, isHexString, namehash } from "ethers";

const { chainId, privateKey } = await init();
const { deployerWallet, smith, rl } = await initSmith(
  typeof chainId === "number" ? chainId : Number(chainId),
  privateKey
);

try {
  // Locate ChainResolver
  let resolverAddress: string | undefined;
  try {
    const res = await loadDeployment(chainId, "ChainResolver");
    const found = res.target as string;
    const code = await deployerWallet.provider.getCode(found);
    if (code && code !== '0x') {
      resolverAddress = found;
    }
  } catch {}
  if (!resolverAddress) resolverAddress = process.env.CHAIN_RESOLVER_ADDRESS || process.env.RESOLVER_ADDRESS || "";
  if (!resolverAddress) resolverAddress = (await askQuestion(rl, "ChainResolver address: ")).trim();
  if (!resolverAddress) {
    console.error("ChainResolver address is required.");
    process.exit(1);
  }

  const resolver = new Contract(
    resolverAddress!,
    [
      "function resolve(bytes name, bytes data) view returns (bytes)",
      "function chainName(bytes) view returns (string)",
    ],
    deployerWallet
  );

  // Input chainId
  let cidIn = (await askQuestion(rl, "Chain ID (0x.. hex or decimal): ")).trim();
  if (!isHexString(cidIn)) {
    const n = BigInt(cidIn);
    // minimal bytes; hexlify will include 0x prefix
    cidIn = hexlify(n);
  }
  const chainIdBytes = getBytes(cidIn);

  // Build key for ChainResolver reverse path: 'chain-name:' + <7930 hex suffix>
  const IFACE = new Interface([
    // Reverse resolution: use text(bytes32,string) only
    "function text(bytes32,string) view returns (string)",
  ]);
  const key = 'chain-name:' + Buffer.from(chainIdBytes).toString('hex');
  // Reverse chain-name lookups are served only when:
  // - name = '<namespace>.eth' and
  // - node = namehash('reverse.<namespace>.eth')
  const dnsName = dnsEncode("cid.eth", 255);
  const reverseNode = namehash("reverse.cid.eth");
  

  try {
    let textName = '';
    try {
      const textCalldata = IFACE.encodeFunctionData("text(bytes32,string)", [reverseNode, key]);
      const textAnswer: string = await resolver.resolve(dnsName, textCalldata);
      [textName] = IFACE.decodeFunctionResult("text(bytes32,string)", textAnswer) as [string];
    } catch {}

    console.log('Chain name (text):', textName);

    // 3) Also show the direct read path
    try {
      const direct = await resolver.chainName(chainIdBytes);
      console.log('Direct read (chainName):', direct);
    } catch {}
  } catch (e) {
    console.error((e as Error).message);
    process.exit(1);
  }
} finally {
  await shutdownSmith(rl, smith);
}
