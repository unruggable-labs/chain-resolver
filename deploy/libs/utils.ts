/**
 * @description
 * @author      Thomas Clowes (clowes.eth)
 * @date        2025-08-22
 */

import { Foundry, execCmd } from "@adraffy/blocksmith";
import readline from "node:readline";
import { JsonRpcProvider, Wallet, Contract } from "ethers";
import { CHAIN_MAP } from "./constants.ts";
import { readFile } from "fs/promises";
import path from "path";

// Self explanatory ;)
export async function createReadlineInterface() {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });
  return rl;
}

// Parse command line arguments, verifying the presence of all required arguments
export async function parseArgs(
  requiredArgs: string[]
): Promise<Map<string, string>> {
  return new Promise((resolve, reject) => {
    const args = process.argv.slice(2); // Skip the first two arguments (node and script path)
    const parsedArgs = new Map<string, string>(); // Use a Map to store the parsed arguments

    args.forEach((arg: string) => {
      // Split argument into key and value
      const [key, value] = arg.split("=");

      if (!key) {
        reject(new Error(`Argument key is required. Format key=value`));
        return;
      }

      const argKey = key.replace(/^--/, ""); // Remove leading '--' from argument name

      if (!value) {
        reject(new Error(`Argument ${key} requires a value.`));
        return;
      }

      parsedArgs.set(argKey, value); // Add all key-value pairs to the Map
    });

    // Check for missing required arguments
    for (const requiredArg of requiredArgs) {
      if (!parsedArgs.has(requiredArg)) {
        reject(new Error(`Missing required argument: --${requiredArg}`));
        return;
      }
    }

    // If all required arguments are present, resolve with parsed arguments
    resolve(parsedArgs);
  });
}

// Function to ask a question and return a Promise
export const askQuestion = (rl, query: string): Promise<string> => {
  return new Promise((resolve) => {
    rl.question(query, (answer) => {
      resolve(answer);
    });
  });
};

// Function to display the continue/exit prompt
export const promptContinueOrExit = async (
  rl,
  question: string = "Do you want to continue? (y/n): "
): Promise<boolean> => {
  const answer: string = await askQuestion(rl, question);

  if (answer.toLowerCase() === "y") {
    console.log("Continuing...");
    return true; // Indicate to continue
  } else if (answer.toLowerCase() === "n") {
    console.log("Skipping the next block of code...");
    return false; // Indicate to skip the next block of code
  } else if (answer.toLowerCase() === "e") {
    console.log("Exiting...");
    process.exit(0); // Exit the process
  } else {
    console.log('Invalid input. Please enter "y" to continue or "n" to skip.');
    return await promptContinueOrExit(question); // Prompt again
  }
};

// Initializes a blocksmith instance for the specified chain
export const initSmith = async (chainName: string, privateKey) => {
  const chainConfig = CHAIN_MAP.get(chainName);
  if (!chainConfig?.rpc) {
    throw new Error(`RPC URL not configured for chain: ${chainName}`);
  }
  const PROVIDER_URL = chainConfig.rpc;
  const PRIVATE_KEY = privateKey;

  console.log(`Initializing Smith for ${chainName} ...`);

  const provider = new JsonRpcProvider(PROVIDER_URL);

  // Create a wallet instance from the private key
  const deployerWallet = new Wallet(PRIVATE_KEY, provider);

  //Launch blocksmith
  const smith = await Foundry.launchLive({
    provider: provider,
    forge: "forge",
    infoLog: true,
    wallets: [deployerWallet],
  });

  const rl = await createReadlineInterface();

  return { deployerWallet, smith, rl };
};

// Gracefully shutdown the smith instance, and our readline interface
export const shutdownSmith = async (rl, smith) => {
  rl.close();
};

// Deploys a contract using Foundry
export const deployContract = async (
  smith,
  deployerWallet: Wallet,
  contractName: string,
  contractArguments: string[],
  libs = {},
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
  contractArgs: any[],
  libs: {},
  smith,
  apiKey: string = process.env.ETHERSCAN_API_KEY || ""
) => {
  if (!apiKey) {
    throw new Error("API key is required for contract verification. Set ETHERSCAN_API_KEY environment variable or pass it explicitly.");
  }
  //console.log(apiKey);
  const { target: contractAddress, links = [] } = contract;

  console.log("contractArgs", contractArgs);
  const encodedArgs = contract.interface.encodeDeploy(contractArgs);

  console.log("Contract arguments: ", contractArgs);
  console.log("Contract arguments (encoded): ", encodedArgs);

  console.log("Contract name: ", contractName);

  console.log("Verifying contract..");

  const formattedLibs = links.map(({ file, contract, offsets }) => {
    //console.log(libs[contract]);
    return `${file}:${contract}:${libs[contract].contractAddress}`;
  });

  console.log("Formatted libs: ", formattedLibs);

  const fqNameMap: Record<string, string> = {
    ChainResolver: "src/ChainResolver.sol:ChainResolver",
    ERC1967Proxy: "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy",
    KeygenLib: "src/utils/KeyGenLib.sol:KeygenLib"
  };
  const nameOrFQN = fqNameMap[contractName] || contractName;

  const chainInfo = CHAIN_MAP.get(chainId);
  const chainFlag = chainInfo?.name ?? chainId; // prefer name like 'sepolia'

  const commandArgs = [
    "verify-contract",
    contractAddress,
    nameOrFQN,
    "--watch",
    "--etherscan-api-key",
    apiKey,
    //'--verifier-url',
    //`https://api.etherscan.io/v2/api`,
    "--chain",
    chainFlag,
  ];

  if (contractArgs.length > 0) {
    commandArgs.push("--constructor-args");
    commandArgs.push(encodedArgs);
  }

  if (links.length > 0) {
    for (let lib of formattedLibs) {
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

// Dies if the value is not set
export const setOrDie = (value, name = "Value") => {
  if (!value) {
    throw new Error(`${name} is not set`);
  }
};

// Verifies the constructor arguments that were used to deploy the contract
// Matches those we are trying to use now
// I.E. Is this a new deployment
export const constructorCheck = (deployedArgs, deploymentArgs) => {
  if (JSON.stringify(deployedArgs) != JSON.stringify(deploymentArgs)) {
    console.log("Different constructor args", deployedArgs, deploymentArgs);
    process.exit();
  }
};

// Loads deployment data from the deployment JSON
export async function loadDeployment(chainId, contractName) {

  console.log('__dirname: ', __dirname);
  const folderPath = path.resolve(__dirname, "../../deployments/" + chainId);

  const file = `${contractName}.json`;
  const filePath = path.join(folderPath, file);

  console.log('filePath: ', filePath);
  
  // Read the file content
  const data = await readFile(filePath, "utf8");

  // Parse the JSON content
  const jsonData = JSON.parse(data);

  //console.log(jsonData);
  return jsonData;
}
