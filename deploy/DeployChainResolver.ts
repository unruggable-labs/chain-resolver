// Deploy unified ChainResolver

import {
  initSmith,
  promptContinueOrExit,
  deployContract,
  verifyContract,
  shutdownSmith,
  constructorCheck,
  loadDeployment,
  askQuestion,
} from "./libs/utils.ts";

import { init } from "./libs/init.ts";
import { isAddress } from "ethers";

// The contract we are deploying
const CONTRACT_NAME = "ChainResolver";

// Initialize deployment
const { chainInfo, privateKey } = await init();

// Launch blocksmith
const { deployerWallet, smith, rl } = await initSmith(
  chainInfo.id,
  privateKey
);

if (!deployerWallet || !deployerWallet.provider) {
  throw Error("No valid deployment wallet");
}

let resolverAddress: string | undefined;

// Try to reuse existing deployment
try {
  const existingResolver = await loadDeployment(chainInfo.id, CONTRACT_NAME);
  const deployedAddress = existingResolver.target as string;

  const code = await deployerWallet.provider.getCode(deployedAddress);
  if (code && code !== "0x") {
    const useExisting = await promptContinueOrExit(
      rl,
      `${CONTRACT_NAME} found at ${deployedAddress}. Use this? (y/n)`
    );
    if (useExisting) {
      resolverAddress = deployedAddress;
    }
  }
} catch {}

if (!resolverAddress) {

  const shouldDeploy = await promptContinueOrExit(
    rl, 
    `Deploy ${CONTRACT_NAME} ? (y/n)`
  );

  if (shouldDeploy) {

    const defaultOwner = deployerWallet.address;
    let owner = defaultOwner;

    const useDefaultInput = (await askQuestion(
      rl, 
      `The owner of the deployed contract will be: ${defaultOwner}. Is this correct?`
    )).trim();

    if (/^y(es)?$/i.test(useDefaultInput)) {

      // do nothing

    } else {

      const ownerAddressInput = (await askQuestion(
        rl, 
        `Enter the address that should own this contract: `
      )).trim();

      if (!isAddress(ownerAddressInput)) {
        throw Error("Invalid address input")
      }

      owner = ownerAddressInput;
    }

    const args: any[] = [owner];
    const libs = {};
    const deploymentPrefix = "[Resolver]";

    const { contract, already } = await deployContract(
      smith,
      deployerWallet,
      CONTRACT_NAME,
      args,
      libs,
      deploymentPrefix
    );

    // If the contract has already been deployed, blow up if different constructor args were used
    if (already) constructorCheck(contract.constructorArgs, args);
    resolverAddress = contract.target as string;

    const shouldVerify = await promptContinueOrExit(
      rl, 
      `Verify ${CONTRACT_NAME}? (y/n)`
    );

    if (shouldVerify) {
      await verifyContract(
        chainInfo.id,
        contract,
        CONTRACT_NAME,
        contract.constructorArgs,
        libs,
        smith
      );
    }
  }
}

console.log("\n=== Deployment Summary ===");
console.log(`${CONTRACT_NAME}: ${resolverAddress ?? "(none)"}`);

await shutdownSmith(rl, smith);
