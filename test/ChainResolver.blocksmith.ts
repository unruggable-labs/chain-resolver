// Blocksmith local simulation for unified ChainResolver
// Usage: bun run test/ChainResolver.foundry.ts

import 'dotenv/config'
import { Foundry } from '@adraffy/blocksmith'
import { Contract, Interface, dnsEncode, keccak256, toUtf8Bytes, getBytes, hexlify, namehash } from 'ethers'

// Helper functions
const log = (...a: any[]) => console.log('[blocksmith]', ...a);
const section = (name: string) => console.log(`\n=== ${name} ===`);
const hex = (b: any) => {
  try { return hexlify(b); } catch { return String(b); }
};

// The resolver contract
const RESOLVER_FILE_NAME = 'ChainResolver.sol';

const ETHEREUM_COIN_TYPE = 60;

// Data record key constants
const INTEROPERABLE_ADDRESS_DATA_KEY = 'interoperable-address';
const CHAIN_NAME_DATA_KEY = 'chain-name';
const CHAIN_OWNER_DATA_KEY = 'chain-owner';

// Text record prefix for reverse resolving 7930 chain ID
const CHAIN_LABEL_PREFIX = 'chain-label:';

async function main() {
  const smith = await Foundry.launch({ forge: 'forge', infoLog: true });
  const wallet = smith.requireWallet('admin');

  section('Launch (local Foundry)');
  log('wallet', wallet.address);

  // 1) Deploy ChainResolver(owner)
  const deployer = wallet.address;
  section(`Deploy ${RESOLVER_FILE_NAME}`);
  log('Deployer address', deployer);
  const resolverContract = await smith.deploy({
    from: wallet,
    file: RESOLVER_FILE_NAME,
    args: [deployer],
  });
  const castedContract = resolverContract as unknown as Contract;
  log('Deployed resolver contract address', resolverContract.target);
  
  // Test data
  const label = 'optimism';
  const labelHash = keccak256(toUtf8Bytes(label));
  const chainIdAsHex = '0x00010001010a00';
  const chainIdAsBytes = getBytes(chainIdAsHex);

  section('Inputs');
  log('label', label);
  log('labelHash', labelHash);
  log('chainId (hex)', chainIdAsHex);

  // 2) Register the test chain
  section('Register test chain data');
  const tx = await resolverContract.register!([label, label, deployer, chainIdAsBytes]);
  const receipt = await tx.wait();

  // Log the events for debugging
  for (const log of receipt.logs) {
    try {
      const event = castedContract.interface.parseLog(log);
      if (event) console.log("Event", event.name, event.args);
    } catch (e) {
      // not an event from this interface
    }
  }

  log('Registration successful');

  

  // 3. Test Forward Resolution of ERC-7930 _Interoperable Address_
  const ensName = `${label}.cid.eth`;
  const nameNamehash = namehash(ensName);
  const dnsEncodedName = dnsEncode(ensName, 255);

  const ENSIP_24_INTERFACE = new Interface(['function data(bytes32,string) view returns (bytes)']);
  const dataCalldata = ENSIP_24_INTERFACE.encodeFunctionData('data(bytes32,string)', [nameNamehash, INTEROPERABLE_ADDRESS_DATA_KEY]);
  const dataResponse: string = await resolverContract.resolve!(dnsEncodedName, dataCalldata);
  const [cidBytes] = ENSIP_24_INTERFACE.decodeFunctionResult('data(bytes32,string)', dataResponse);
  if (hex(cidBytes) !== chainIdAsHex) {
    throw new Error(`Unexpected chain-id bytes: got=${hex(cidBytes)} want=${chainIdAsHex}`);
  }
  

  // Set and read an ETH address (coinType 60)
  const testAddress = '0x000000000000000000000000000000000000dEaD';
  const ADDR_INTERFACE = new Interface(['function addr(bytes32) view returns (address)']);
  const setAddr60 = castedContract.getFunction('setAddr(bytes32,uint256,bytes)');
  await (await setAddr60(labelHash, ETHEREUM_COIN_TYPE, testAddress)).wait();
  const call60 = ADDR_INTERFACE.encodeFunctionData('addr(bytes32)', [labelHash]);
  const ans60: string = await resolverContract.resolve!(dnsEncodedName, call60);
  const [got60] = ADDR_INTERFACE.decodeFunctionResult('addr(bytes32)', ans60);
  if (got60.toLowerCase() !== testAddress.toLowerCase()) {
    throw new Error(`Unexpected ETH addr: got=${got60} want=${testAddress}`);
  }
    
  const anotherTestAddress = '0x0000000000000000000000000000000000000abc';
  const ENSIP_9_INTERFACE = new Interface(['function addr(bytes32,uint256) view returns (bytes)']);
  const setAddrBytes = castedContract.getFunction('setAddr(bytes32,uint256,bytes)');
  await (await setAddrBytes(labelHash, 137n, getBytes(anotherTestAddress))).wait();
  const acall = ENSIP_9_INTERFACE.encodeFunctionData('addr(bytes32,uint256)', [labelHash, 137n]);
  const aanswer: string = await resolverContract.resolve!(dnsEncodedName, acall);
  const [rawBytes] = ENSIP_9_INTERFACE.decodeFunctionResult('addr(bytes32,uint256)', aanswer);
  if (hex(rawBytes) !== hex(getBytes(anotherTestAddress))) {
    throw new Error(`Unexpected multi-coin addr: got=${hex(rawBytes)} want=${hex(getBytes(anotherTestAddress))}`);
  }

  // Reverse via text selector using ENSIP-10 full name binding.
  // name = reverse.cid.eth; node = namehash(name); key = 'chain-label:<7930hex>'.
  const ENSIP_5_INTERFACE = new Interface(['function text(bytes32,string) view returns (string)']);
  const reverseKey = `${CHAIN_LABEL_PREFIX}${chainIdAsHex.replace(/^0x/, '')}`;
  const reverseName = 'reverse.cid.eth';
  const reverseNode = namehash(reverseName);

  console.log('reverseKey', reverseKey);
  section('Reverse Resolve (text)');
  const textCall = ENSIP_5_INTERFACE.encodeFunctionData('text(bytes32,string)', [reverseNode, reverseKey]);
  const reverseDns = dnsEncode(reverseName, 255);
  const tanswer: string = await resolverContract.resolve!(reverseDns, textCall);
  console.log('tanswer', tanswer);
  const [textName] = ENSIP_5_INTERFACE.decodeFunctionResult('text(bytes32,string)', tanswer);
  log('text resolved name', textName);
  if (textName !== label) throw new Error(`Unexpected reverse name (text): ${textName}`);

  section('Direct Reads');
  const cid = await resolverContract.interoperableAddress!(labelHash);
  log('chainId(bytes)', cid);
  if (hexlify(cid) !== chainIdAsHex) throw new Error('chainId() mismatch');

  const cname = await resolverContract.chainName!(cid);
  log('chainName(bytes)', cname.toString().length, cname);
  log('label', label.length);
  if (cname !== label) throw new Error('chainName() mismatch');

  console.log('✓ Blocksmith Foundry test passed');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
