// Deploy ChainResolver via UUPS Proxy

import {
  initSmith,
  promptContinueOrExit,
  deployContract,
  verifyContract,
  shutdownSmith,
  askQuestion,
} from "./libs/utils.ts";

import { init } from "./libs/init.ts";
import { isAddress, namehash, Interface } from "ethers";

// The contracts we are deploying
const IMPLEMENTATION_NAME = "ChainResolver";
const PROXY_NAME = "ERC1967Proxy";

// Initialize deployment
const { chainInfo, privateKey } = await init();

console.log('ChainInfo: ', chainInfo);

// Launch blocksmith
const { deployerWallet, smith, rl } = await initSmith(
  chainInfo.name,
  privateKey
);

if (!deployerWallet || !deployerWallet.provider) {
  throw Error("No valid deployment wallet");
}

let proxyAddress: string | undefined;
let implementationAddress: string | undefined;

console.log("\n=== ChainResolver UUPS Proxy Deployment ===\n");

// Step 1: Get owner address
const defaultOwner = deployerWallet.address;
let owner = defaultOwner;

const useDefaultOwner = (await askQuestion(
  rl,
  `Owner will be: ${defaultOwner}. Use this address? (y/n) `
)).trim();

if (!/^y(es)?$/i.test(useDefaultOwner)) {
  const ownerInput = (await askQuestion(
    rl,
    `Enter the owner address: `
  )).trim();

  if (!isAddress(ownerInput)) {
    throw Error("Invalid owner address");
  }
  owner = ownerInput;
}

// Step 2: Get parent namespace
const defaultParent = "on.eth";
let parentNamespace = defaultParent;

const useDefaultParent = (await askQuestion(
  rl,
  `Parent namespace will be: ${defaultParent}. Use this? (y/n) `
)).trim();

if (!/^y(es)?$/i.test(useDefaultParent)) {
  parentNamespace = (await askQuestion(
    rl,
    `Enter the parent namespace (e.g., "cid.eth", "on.eth"): `
  )).trim();
}

const parentNamehash = namehash(parentNamespace);
console.log(`\nParent namespace: ${parentNamespace}`);
console.log(`Parent namehash: ${parentNamehash}`);

// Step 3: Deploy implementation
const shouldDeployImpl = await promptContinueOrExit(
  rl,
  `\nDeploy ${IMPLEMENTATION_NAME} implementation? (y/n)`
);

if (shouldDeployImpl) {
  const { contract: implContract } = await deployContract(
    smith,
    deployerWallet,
    IMPLEMENTATION_NAME,
    [], // No constructor args for upgradeable
    {},
    "[Implementation]"
  );
  implementationAddress = implContract.target as string;

  const shouldVerifyImpl = await promptContinueOrExit(
    rl,
    `Verify ${IMPLEMENTATION_NAME} implementation? (y/n)`
  );

  if (shouldVerifyImpl) {
    await verifyContract(
      chainInfo.id,
      implContract,
      IMPLEMENTATION_NAME,
      [],
      {},
      smith
    );
  }
}

if (!implementationAddress) {
  const implInput = (await askQuestion(
    rl,
    `Enter existing implementation address: `
  )).trim();

  if (!isAddress(implInput)) {
    throw Error("Invalid implementation address");
  }
  implementationAddress = implInput;
}

// Step 4: Deploy proxy
const shouldDeployProxy = await promptContinueOrExit(
  rl,
  `\nDeploy ${PROXY_NAME} pointing to ${implementationAddress}? (y/n)`
);

if (shouldDeployProxy) {
  // Encode the initialize call
  const initInterface = new Interface([
    "function initialize(address _owner, bytes32 _parentNamehash)"
  ]);
  const initData = initInterface.encodeFunctionData("initialize", [
    owner,
    parentNamehash
  ]);

  console.log(`\nInitialize calldata:`);
  console.log(`  Owner: ${owner}`);
  console.log(`  Parent namehash: ${parentNamehash}`);

  const { contract: proxyContract } = await deployContract(smith, deployerWallet, PROXY_NAME, [implementationAddress, initData], {}, "[Proxy]");

  proxyAddress = proxyContract.target as string;
  console.log(`[Proxy] ${PROXY_NAME} address: ${proxyAddress}`);

  // Verify the owner was set correctly
  const resolverInterface = new Interface([
    "function owner() view returns (address)"
  ]);
  const ownerCall = await deployerWallet.provider!.call({
    to: proxyAddress,
    data: resolverInterface.encodeFunctionData("owner")
  });
  const [actualOwner] = resolverInterface.decodeFunctionResult("owner", ownerCall);
  console.log(`\nVerification: proxy.owner() = ${actualOwner}`);

  if (actualOwner.toLowerCase() !== owner.toLowerCase()) {
    console.error("WARNING: Owner mismatch!");
  }

  // Verify proxy contract
  const shouldVerifyProxy = await promptContinueOrExit(
    rl,
    `Verify ${PROXY_NAME}? (y/n)`
  );

  if (shouldVerifyProxy) {
    await verifyContract(
      chainInfo.id,
      proxyContract,
      PROXY_NAME,
      [implementationAddress, initData],
      {},
      smith
    );
  }
}

// Step 5: Optional ownership transfer
if (proxyAddress && owner === deployerWallet.address) {
  const shouldTransfer = await promptContinueOrExit(
    rl,
    `\nTransfer ownership to a different address (e.g., multisig)? (y/n)`
  );

  if (shouldTransfer) {
    const newOwner = (await askQuestion(
      rl,
      `Enter the new owner address: `
    )).trim();

    if (!isAddress(newOwner)) {
      throw Error("Invalid new owner address");
    }

    const transferInterface = new Interface([
      "function transferOwnership(address newOwner)"
    ]);
    const transferData = transferInterface.encodeFunctionData("transferOwnership", [newOwner]);

    console.log(`\nTransferring ownership to ${newOwner}...`);
    const tx = await deployerWallet.sendTransaction({
      to: proxyAddress,
      data: transferData
    });
    await tx.wait();
    console.log(`Ownership transferred. TX: ${tx.hash}`);
  }
}

console.log("\n=== Deployment Summary ===");
console.log(`Implementation: ${implementationAddress ?? "(none)"}`);
console.log(`Proxy: ${proxyAddress ?? "(none)"}`);
console.log(`Owner: ${owner}`);
console.log(`Parent namespace: ${parentNamespace}`);

if (proxyAddress) {
  console.log(`\nTo interact with ChainResolver, use the PROXY address: ${proxyAddress}`);
}

await shutdownSmith(rl, smith);
