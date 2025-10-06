// Resolve records for a label via ENSIP-10 `resolve(name,data)`
import 'dotenv/config'

import { init } from './libs/init.ts';
import { initSmith, shutdownSmith, loadDeployment, askQuestion } from './libs/utils.ts';
import {
  Contract,
  Interface,
  dnsEncode,
  keccak256,
  toUtf8Bytes,
  isHexString,
  hexlify,
} from 'ethers';
import * as contentHash from 'content-hash';

function toBytesLike(input: string): string {
  if (!input) return '0x';
  if (isHexString(input)) return input;
  return hexlify(toUtf8Bytes(input));
}

// Initialize context
const { chainId, privateKey } = await init();
const { deployerWallet, smith, rl } = await initSmith(
  typeof chainId === 'number' ? chainId : Number(chainId),
  privateKey,
);

try {
  // Locate ChainResolver
  let resolverAddress: string | undefined;
  try {
    const res = await loadDeployment(chainId, 'ChainResolver');
    const found = res.target as string;
    const code = await deployerWallet.provider.getCode(found);
    if (code && code !== '0x') resolverAddress = found;
  } catch {}
  if (!resolverAddress) {
    const envRes = (process.env.CHAIN_RESOLVER_ADDRESS || process.env.RESOLVER_ADDRESS || '').trim();
    if (envRes) resolverAddress = envRes;
  }
  if (!resolverAddress) resolverAddress = (await askQuestion(rl, 'ChainResolver address: ')).trim();
  if (!resolverAddress) {
    console.error('ChainResolver address is required.');
    process.exit(1);
  }

  // Contracts & ABIs
  const resolver = new Contract(
    resolverAddress!,
    ['function resolve(bytes name, bytes data) view returns (bytes)'],
    deployerWallet,
  );

  const IFACE = new Interface([
    'function addr(bytes32) view returns (address)',
    'function addr(bytes32,uint256) view returns (address)',
    'function contenthash(bytes32) view returns (bytes)',
    'function text(bytes32,string) view returns (string)',
    'function data(bytes32,bytes) view returns (bytes)',
  ]);

  // Input label
  const label = (await askQuestion(rl, 'Label (e.g. base): ')).trim();
  if (!label) {
    console.error('Label is required.');
    process.exit(1);
  }
  const labelHash = keccak256(toUtf8Bytes(label));
  const ensName = `${label}.cid.eth`;
  const dnsName = dnsEncode(ensName, 255);
  console.log('Using:', { ensName, labelHash });

  async function resolveDecode<T = any>(sig: string, args: any[]): Promise<T> {
    const call = IFACE.encodeFunctionData(sig, args);
    const answer: string = await resolver.resolve(dnsName, call);
    const [decoded] = IFACE.decodeFunctionResult(sig, answer);
    return decoded as T;
  }

  // chain-id
  const printChainId = await askQuestion(rl, "Resolve chain-id? (y/n): ");
  if (/^y(es)?$/i.test(printChainId.trim())) {
    const hexCid = await resolveDecode<string>('text(bytes32,string)', [labelHash, 'chain-id']);
    console.log('chain-id:', '0x' + hexCid);
  }

  // addr(60)
  const wantAddr60 = await askQuestion(rl, 'Resolve addr(60)? (y/n): ');
  if (/^y(es)?$/i.test(wantAddr60.trim())) {
    const addr = await resolveDecode<string>('addr(bytes32)', [labelHash]);
    console.log('addr(60):', addr);
  }

  // addr custom coinType
  const wantAddrCT = await askQuestion(rl, 'Resolve addr(label, coinType)? (y/n): ');
  if (/^y(es)?$/i.test(wantAddrCT.trim())) {
    const coinTypeStr = (await askQuestion(rl, 'coinType (uint): ')).trim();
    let coinType: bigint | undefined;
    try {
      coinType = BigInt(coinTypeStr);
    } catch {
      console.warn('Invalid coinType; skipping custom addr.');
    }
    if (coinType !== undefined) {
      const addr = await resolveDecode<string>('addr(bytes32,uint256)', [labelHash, coinType]);
      console.log(`addr(${coinType}):`, addr);
    }
  }

  // contenthash
  const wantCH = await askQuestion(rl, 'Resolve contenthash? (y/n): ');
  if (/^y(es)?$/i.test(wantCH.trim())) {
    const chHex = await resolveDecode<string>('contenthash(bytes32)', [labelHash]);
    if (!chHex || chHex === '0x') {
      console.log('contenthash: (empty)');
    } else {
      const hex = chHex.startsWith('0x') ? chHex.slice(2) : chHex;
      try {
        const codec = (contentHash as any).getCodec(hex);
        const value = (contentHash as any).decode(hex);
        let pretty = value;
        if (codec === 'ipfs-ns') pretty = 'ipfs://' + value;
        else if (codec === 'ipns-ns') pretty = 'ipns://' + value;
        else if (codec === 'swarm-ns') pretty = 'bzz://' + value;
        console.log('contenthash:', pretty, `(codec=${codec})`);
      } catch {
        console.log('contenthash (raw hex):', chHex);
      }
    }
  }

  // text(key)
  const wantText = await askQuestion(rl, 'Resolve text(key)? (y/n): ');
  if (/^y(es)?$/i.test(wantText.trim())) {
    const key = (await askQuestion(rl, 'text key: ')).trim();
    const val = await resolveDecode<string>('text(bytes32,string)', [labelHash, key]);
    console.log(`text(${key}):`, val);
  }

  // data(keyBytes)
  const wantData = await askQuestion(rl, 'Resolve data(keyBytes)? (y/n): ');
  if (/^y(es)?$/i.test(wantData.trim())) {
    const k = (await askQuestion(rl, 'data key (utf8 or 0x..): ')).trim();
    const keyBytes = toBytesLike(k);
    const bytesVal = await resolveDecode<string>('data(bytes32,bytes)', [labelHash, keyBytes]);
    console.log('data:', bytesVal);
  }

  console.log('Done.');
} finally {
  await shutdownSmith(rl, smith);
}
