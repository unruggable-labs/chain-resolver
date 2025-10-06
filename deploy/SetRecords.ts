// Set records for a label via ENSIP-10-compatible setters
import 'dotenv/config'

import { init } from './libs/init.ts';
import {
  initSmith,
  shutdownSmith,
  loadDeployment,
  askQuestion,
  promptContinueOrExit,
} from './libs/utils.ts';

import {
  Contract,
  keccak256,
  toUtf8Bytes,
  isHexString,
  hexlify,
} from 'ethers';
import * as contentHash from 'content-hash';
import { CID } from 'multiformats/cid';

function toBytesLike(input: string): string {
  if (!input) return '0x';
  if (isHexString(input)) return input;
  return hexlify(toUtf8Bytes(input));
}

async function encodeContenthash(input: string): Promise<string> {
  input = input.trim();

  if ((input.startsWith("'") && input.endsWith("'")) || (input.startsWith('"') && input.endsWith('"'))) {
    input = input.slice(1, -1);
  }

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
  if (lower.startsWith('ipfs://') || lower.startsWith('ipns://')) {
    const isIpfs = lower.startsWith('ipfs://');
    const ns = isIpfs ? 'ipfs-ns' : 'ipns-ns';
    let value = input.replace(/^ipfs:\/\//i, '').replace(/^ipns:\/\//i, '');
    if (isIpfs) {
      try { value = CID.parse(value).toString(); } catch (err) { throw new Error('Invalid CID in ipfs URL: ' + String(err)); }
    } else {
      try { value = CID.parse(value).toString(); } catch {}
    }
    const encoded = (contentHash as any).encode(ns, value);
    return '0x' + encoded;
  }

  if (lower.startsWith('bzz://') || lower.startsWith('swarm://')) {
    const valuePart = input.slice(input.indexOf('://') + 3);
    if (!isHexString(valuePart)) throw new Error('Swarm content must be hex hash');
    const clean = valuePart.startsWith('0x') ? valuePart.slice(2) : valuePart;
    const encoded = (contentHash as any).encode('swarm-ns', clean);
    return '0x' + encoded;
  }

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
    [
      'function setAddr(bytes32,uint256,address) external',
      'function setContenthash(bytes32,bytes) external',
      'function setText(bytes32,string,string) external',
      'function setData(bytes32,bytes,bytes) external',
    ],
    deployerWallet,
  );

  // Input label
  const label = (await askQuestion(rl, 'Label (e.g. base): ')).trim();
  if (!label) {
    console.error('Label is required.');
    process.exit(1);
  }
  const labelHash = keccak256(toUtf8Bytes(label));
  console.log('Using:', { label, labelHash });

  // Set addr(60)
  if (await promptContinueOrExit(rl, 'Set addr(60)? (y/n): ')) {
    const a60 = (await askQuestion(rl, 'ETH address: ')).trim();
    const tx = await resolver.setAddr(labelHash, 60, a60);
    await tx.wait();
    console.log('✓ setAddr(60)');
  }

  // Set addr with custom coinType
  if (await promptContinueOrExit(rl, 'Set addr(label, coinType)? (y/n): ')) {
    const coinTypeStr = (await askQuestion(rl, 'coinType (uint): ')).trim();
    const coinType = BigInt(coinTypeStr);
    const addr = (await askQuestion(rl, 'address: ')).trim();
    const tx = await resolver.setAddr(labelHash, coinType, addr);
    await tx.wait();
    console.log(`✓ setAddr(${coinType})`);
  }

  // Set contenthash
  if (await promptContinueOrExit(rl, 'Set contenthash? (y/n): ')) {
    const chIn = (await askQuestion(rl, 'contenthash (ipfs://, ipns://, bzz:// or 0x..): ')).trim();
    const ch = await encodeContenthash(chIn);
    const tx = await resolver.setContenthash(labelHash, ch);
    await tx.wait();
    console.log('✓ setContenthash');
  }

  // Set text(key,value)
  if (await promptContinueOrExit(rl, 'Set text(key,value)? (y/n): ')) {
    const key = (await askQuestion(rl, 'text key: ')).trim();
    const val = (await askQuestion(rl, 'text value: ')).trim();
    const tx = await resolver.setText(labelHash, key, val);
    await tx.wait();
    console.log(`✓ setText(${key})`);
  }

  // Set data(keyBytes,valueBytes)
  if (await promptContinueOrExit(rl, 'Set data(keyBytes,valueBytes)? (y/n): ')) {
    const k = (await askQuestion(rl, 'data key (utf8 or 0x..): ')).trim();
    const v = (await askQuestion(rl, 'data value (utf8 or 0x..): ')).trim();
    const keyBytes = toBytesLike(k);
    const valBytes = toBytesLike(v);
    const tx = await resolver.setData(labelHash, keyBytes, valBytes);
    await tx.wait();
    console.log('✓ setData');
  }

  console.log('Done.');
} finally {
  await shutdownSmith(rl, smith);
}

