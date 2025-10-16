// Blocksmith local simulation for unified ChainResolver
// Usage: bun run test/ChainResolver.foundry.ts

import 'dotenv/config'
import { Foundry } from '@adraffy/blocksmith'
import { Contract, Interface, dnsEncode, keccak256, toUtf8Bytes, getBytes, hexlify, AbiCoder, namehash } from 'ethers'

async function main() {
  const smith = await Foundry.launch({ forge: 'forge', infoLog: true });
  const provider = smith.provider;
  const wallet = smith.requireWallet('admin');

  const log = (...a: any[]) => console.log('[blocksmith]', ...a);
  const section = (name: string) => console.log(`\n=== ${name} ===`);
  const hex = (b: any) => {
    try { return hexlify(b); } catch { return String(b); }
  };

  section('Launch (local Foundry)');
  log('wallet', wallet.address);
  try {
    // 1) Deploy ChainResolver(owner)
    const owner = wallet.address;
    section('Deploy');
    log('owner', owner);
    const { target: resolverAddr } = await smith.deploy({
      from: wallet,
      file: 'ChainResolver.sol',
      args: [owner],
      save: false,
    });
    log('resolver', resolverAddr);

    const resolver = new Contract(
      resolverAddr,
      [
        'function chainId(bytes32) view returns (bytes)',
        'function chainName(bytes) view returns (string)',
        'function resolve(bytes,bytes) view returns (bytes)',
        'function setAddr(bytes32,address) external',
        'function setAddr(bytes32,uint256,bytes) external',
        'function register(string,address,bytes) external',
      ],
      wallet
    );

    // Test data
    const label = 'optimism';
    const LABEL_HASH = keccak256(toUtf8Bytes(label));
    const CHAIN_ID_HEX = '0x000000010001010a00';
    const CHAIN_ID = getBytes(CHAIN_ID_HEX);
    section('Inputs');
    log('label', label);
    log('labelHash', LABEL_HASH);
    log('chainId (hex)', CHAIN_ID_HEX);
    // 2) Register name -> chainId (owner-only)
  section('Register');
  const tx = await resolver.register(label, owner, CHAIN_ID);
  await tx.wait();

    // Prepare names and interfaces
    const ensName = `${label}.cid.eth`;
    const dnsName = dnsEncode(ensName, 255);
    const IFACE = new Interface(['function text(bytes32,string) view returns (string)']);
    const call = IFACE.encodeFunctionData('text(bytes32,string)', [LABEL_HASH, 'chain-id']);
    section('Forward Resolve');
    log('ensName', ensName);
    const answer: string = await resolver.resolve(dnsName, call);
    const [chainIdHex] = IFACE.decodeFunctionResult('text(bytes32,string)', answer);
    log('resolved chain-id (hex, no 0x)', chainIdHex);
    if (chainIdHex !== CHAIN_ID_HEX.replace(/^0x/, '')) {
      throw new Error(`Unexpected chain-id hex: ${chainIdHex}`);
    }

    // Also resolve via data(bytes32,string) -> bytes
    {
      const DFACE = new Interface(['function data(bytes32,string) view returns (bytes)']);
      const dcall = DFACE.encodeFunctionData('data(bytes32,string)', [LABEL_HASH, 'chain-id']);
      const danswer: string = await resolver.resolve(dnsName, dcall);
      const [cidBytes] = DFACE.decodeFunctionResult('data(bytes32,string)', danswer);
      if (hex(cidBytes) !== CHAIN_ID_HEX) {
        throw new Error(`Unexpected chain-id bytes: got=${hex(cidBytes)} want=${CHAIN_ID_HEX}`);
      }
    }

    // Set and read an ETH address (coinType 60) via the 2-arg overload
    {
      const addr60 = '0x000000000000000000000000000000000000dEaD';
      const IFACE60 = new Interface(['function addr(bytes32) view returns (address)']);
      const setAddr60 = resolver.getFunction('setAddr(bytes32,address)');
      await (await setAddr60(LABEL_HASH, addr60)).wait();
      const call60 = IFACE60.encodeFunctionData('addr(bytes32)', [LABEL_HASH]);
      const ans60: string = await resolver.resolve(dnsName, call60);
      const [got60] = IFACE60.decodeFunctionResult('addr(bytes32)', ans60);
      if (got60.toLowerCase() !== addr60.toLowerCase()) {
        throw new Error(`Unexpected ETH addr: got=${got60} want=${addr60}`);
      }
    }

    // Set and read a multi-coin (137) address locally via the 3-arg overload
    {
      const other = '0x0000000000000000000000000000000000000abc';
      const AIFACE = new Interface(['function addr(bytes32,uint256) view returns (bytes)']);
      const setAddrBytes = resolver.getFunction('setAddr(bytes32,uint256,bytes)');
      await (await setAddrBytes(LABEL_HASH, 137n, getBytes(other))).wait();
      const acall = AIFACE.encodeFunctionData('addr(bytes32,uint256)', [LABEL_HASH, 137n]);
      const aanswer: string = await resolver.resolve(dnsName, acall);
      const [rawBytes] = AIFACE.decodeFunctionResult('addr(bytes32,uint256)', aanswer);
      if (hex(rawBytes) !== hex(getBytes(other))) {
        throw new Error(`Unexpected multi-coin addr: got=${hex(rawBytes)} want=${hex(getBytes(other))}`);
      }
    }

    // Reverse via text selector using node-bound reverse context.
    // name = cid.eth; node = namehash('reverse.cid.eth'); key = 'chain-name:<7930hex>'.
    const TIFACE = new Interface(['function text(bytes32,string) view returns (string)']);
    const reverseKey = 'chain-name:' + CHAIN_ID_HEX.replace(/^0x/, '');
    const reverseNode = namehash('reverse.cid.eth');

    section('Reverse Resolve (text)');
    const textCall = TIFACE.encodeFunctionData('text(bytes32,string)', [reverseNode, reverseKey]);
    const reverseDns = dnsEncode('cid.eth', 255);
    const tanswer: string = await resolver.resolve(reverseDns, textCall);
    const [textName] = TIFACE.decodeFunctionResult('text(bytes32,string)', tanswer);
    log('text resolved name', textName);
    if (textName !== label) throw new Error(`Unexpected reverse name (text): ${textName}`);

    section('Direct Reads');
    const cid = await resolver.chainId(LABEL_HASH);
    log('chainId(bytes)', hex(cid));
    const cname = await resolver.chainName(cid);
    log('chainName(bytes)', cname);
    if (hexlify(cid) !== CHAIN_ID_HEX) throw new Error('chainId() mismatch');
    if (cname !== label) throw new Error('chainName() mismatch');

    console.log('✓ Blocksmith Foundry test passed');
  } catch (e) {
    console.error(e);
    throw e;
  } finally {
    try { await smith.shutdown(); } catch {}
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
