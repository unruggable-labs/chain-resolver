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

// Initialize deployment
const { chainId, privateKey } = await init();

// Launch blocksmith
const { deployerWallet, smith, rl } = await initSmith(
  typeof chainId === "number" ? chainId : Number(chainId),
  privateKey
);

let resolverAddress: string | undefined;

// Try to reuse existing deployment
try {
  const existingResolver = await loadDeployment(chainId, "ChainResolver");
  const found = existingResolver.target as string;
  const code = await deployerWallet.provider.getCode(found);
  if (code && code !== "0x") {
    const useExisting = await promptContinueOrExit(
      rl,
      `ChainResolver found at ${found}. Use this? (y/n)`
    );
    if (useExisting) {
      resolverAddress = found;
    }
  }
} catch {}

if (!resolverAddress) {
  const shouldDeploy = await promptContinueOrExit(rl, "Deploy ChainResolver? (y/n)");
  if (shouldDeploy) {
    const defaultOwner = deployerWallet.address;
    const ownerIn = (await askQuestion(rl, `Owner address [default ${defaultOwner}]: `)).trim();
    // Treat empty, 'y', or 'yes' as accept default; otherwise validate address
    let owner = defaultOwner;
    if (ownerIn && !/^y(es)?$/i.test(ownerIn)) {
      owner = isAddress(ownerIn) ? ownerIn : defaultOwner;
      if (owner === defaultOwner) {
        console.log(`[Warn] Invalid owner input '${ownerIn}'. Using default ${defaultOwner}`);
      }
    }

    const args: any[] = [owner];
    const libs = {};
    const { contract, already } = await deployContract(
      smith,
      deployerWallet,
      "ChainResolver",
      args,
      libs,
      "[Resolver]"
    );
    if (already) constructorCheck(contract.constructorArgs, args);
    resolverAddress = contract.target as string;

    const shouldVerify = await promptContinueOrExit(rl, "Verify ChainResolver? (y/n)");
    if (shouldVerify) {
      await verifyContract(
        chainId,
        contract,
        "ChainResolver",
        contract.constructorArgs,
        libs,
        smith
      );
    }
  }
}

console.log("\n=== Deployment Summary ===");
console.log(`Resolver:        ${resolverAddress ?? "(none)"}`);

await shutdownSmith(rl, smith);
