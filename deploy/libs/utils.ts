/**
 * @description Deployment utilities
 * @author      Thomas Clowes (clowes.eth)
 * @date        2025-08-22
 */

import { Foundry, execCmd } from "@adraffy/blocksmith";
import { JsonRpcProvider, Wallet, Contract } from "ethers";
import { readFile } from "fs/promises";
import path from "path";

// Re-export shared utilities
export {
  createReadlineInterface,
  askQuestion,
  promptContinueOrExit,
  setOrDie,
} from "../../shared/utils.ts";

import { CHAIN_MAP } from "./constants.ts";

// Initializes a blocksmith instance for the specified chain
export const initSmith = async (chainName: string, privateKey: string) => {
  const chainConfig = CHAIN_MAP.get(chainName);
  if (!chainConfig?.rpc) {
    throw new Error(`RPC URL not configured for chain: ${chainName}`);
  }
  const PROVIDER_URL = chainConfig.rpc;

  console.log(`Initializing Smith for ${chainName} ...`);

  const provider = new JsonRpcProvider(PROVIDER_URL);

  // Create a wallet instance from the private key
  const deployerWallet = new Wallet(privateKey, provider);

  // Launch blocksmith
  const smith = await Foundry.launchLive({
    provider: provider,
    forge: "forge",
    infoLog: true,
    wallets: [deployerWallet],
  });

  const { createReadlineInterface } = await import("../../shared/utils.ts");
  const rl = createReadlineInterface();

  return { deployerWallet, smith, rl };
};

// Gracefully shutdown the smith instance, and our readline interface
export const shutdownSmith = async (rl: { close: () => void }, smith?: Foundry) => {
  rl.close();
  if (smith) {
    try {
      // launchLive() doesn't create a process, so shutdown() will fail
      // Check if it's an anvil instance (has a process) before calling shutdown
      // isAnvil() checks if 'anvil' property exists
      const smithAny = smith as any;
      if (smithAny.isAnvil && smithAny.isAnvil()) {
        await smith.shutdown();
      } else {
        // For live instances, just destroy the provider
        if (smith.provider && typeof smith.provider.destroy === 'function') {
          smith.provider.destroy();
        }
      }
    } catch (e: any) {
      // If shutdown fails, try to at least destroy the provider
      if (smith.provider && typeof smith.provider.destroy === 'function') {
        try {
          smith.provider.destroy();
        } catch {
          // Ignore cleanup errors
        }
      }
      // Don't throw - we're shutting down anyway
    }
  }
};

// Deploys a contract using Foundry
export const deployContract = async (
  smith: Foundry,
  deployerWallet: Wallet,
  contractName: string,
  contractArguments: unknown[],
  libs: Record<string, { contractAddress: string }> = {},
  prepend = ""
) => {
  const contract = await smith.deploy({
    from: deployerWallet,
    file: contractName,
    args: contractArguments,
    save: true,
    libs: libs,
    prepend: prepend,
  });

  if (contract.already) {
    console.log(
      `${prepend} ${contractName} is already deployed to ${contract.target}. Skipping deployment..`
    );
  } else {
    console.log(`${prepend} ${contractName} address: `, contract.target);
  }

  return {
    contract,
    contractAddress: contract.target,
    already: contract.already,
  };
};

// Verifies a contract on Etherscan
export const verifyContract = async (
  chainId: number,
  contract: Contract,
  contractName: string,
  contractArgs: unknown[],
  libs: Record<string, { contractAddress: string }>,
  smith: Foundry,
  apiKey: string = process.env.ETHERSCAN_API_KEY || ""
) => {
  if (!apiKey) {
    throw new Error("API key is required for contract verification. Set ETHERSCAN_API_KEY environment variable or pass it explicitly.");
  }

  const { target: contractAddress, links = [] } = contract as Contract & { links?: Array<{ file: string; contract: string; offsets: unknown }> };

  console.log("contractArgs", contractArgs);
  const encodedArgs = contract.interface.encodeDeploy(contractArgs);

  console.log("Contract arguments: ", contractArgs);
  console.log("Contract arguments (encoded): ", encodedArgs);
  console.log("Contract name: ", contractName);
  console.log("Verifying contract..");

  const formattedLibs = links.map(({ file, contract: contractKey }) => {
    return `${file}:${contractKey}:${libs[contractKey]?.contractAddress}`;
  });

  console.log("Formatted libs: ", formattedLibs);

  const fqNameMap: Record<string, string> = {
    ChainResolver: "src/ChainResolver.sol:ChainResolver",
    ERC1967Proxy: "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy",
    KeygenLib: "src/utils/KeyGenLib.sol:KeygenLib"
  };
  const nameOrFQN = fqNameMap[contractName] || contractName;

  const chainInfo = CHAIN_MAP.get(chainId);
  const chainFlag = chainInfo?.name ?? String(chainId);

  const commandArgs = [
    "verify-contract",
    String(contractAddress),
    nameOrFQN,
    "--watch",
    "--etherscan-api-key",
    apiKey,
    "--chain",
    chainFlag,
  ];

  if (contractArgs.length > 0) {
    commandArgs.push("--constructor-args");
    commandArgs.push(encodedArgs);
  }

  if (links.length > 0) {
    for (const lib of formattedLibs) {
      commandArgs.push("--libraries");
      commandArgs.push(lib);
    }
  }

  console.log("Command args: ", commandArgs);

  const verificationResponse = await execCmd(
    "forge",
    commandArgs,
    undefined,
    smith.procLog
  );

  console.log("Verification response: ", verificationResponse);
};

// Parse command line arguments, verifying the presence of all required arguments
export async function parseArgs(
  requiredArgs: string[]
): Promise<Map<string, string>> {
  return new Promise((resolve, reject) => {
    const args = process.argv.slice(2);
    const parsedArgs = new Map<string, string>();

    args.forEach((arg: string) => {
      const [key, value] = arg.split("=");

      if (!key) {
        reject(new Error(`Argument key is required. Format key=value`));
        return;
      }

      const argKey = key.replace(/^--/, "");

      if (!value) {
        reject(new Error(`Argument ${key} requires a value.`));
        return;
      }

      parsedArgs.set(argKey, value);
    });

    for (const requiredArg of requiredArgs) {
      if (!parsedArgs.has(requiredArg)) {
        reject(new Error(`Missing required argument: --${requiredArg}`));
        return;
      }
    }

    resolve(parsedArgs);
  });
}

// Verifies the constructor arguments that were used to deploy the contract
export const constructorCheck = (deployedArgs: unknown[], deploymentArgs: unknown[]) => {
  if (JSON.stringify(deployedArgs) !== JSON.stringify(deploymentArgs)) {
    console.log("Different constructor args", deployedArgs, deploymentArgs);
    process.exit();
  }
};

// Loads deployment data from the deployment JSON
export async function loadDeployment(chainId: number | string, contractName: string) {
  const folderPath = path.resolve(__dirname, "../../deployments/" + chainId);
  const file = `${contractName}.json`;
  const filePath = path.join(folderPath, file);

  console.log('filePath: ', filePath);
  
  const data = await readFile(filePath, "utf8");
  const jsonData = JSON.parse(data);

  return jsonData;
}
