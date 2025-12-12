/**
 * @description Initialization function for the deployment scripts.
 * @author      Thomas Clowes (clowes.eth)
 * @date        2025-08-22
 */

import { parseArgs } from "./utils.ts";
import { setOrDie } from "../../shared/utils.ts";
import { getNetwork, type NetworkConfig } from "./constants.ts";

import 'dotenv/config'

export type InitData = {
    args: Map<string, string>
    chainInfo: NetworkConfig,
    privateKey?: string,
}

export async function init(): Promise<InitData> {
    // Get the deployment command line arguments
    const requiredArguments = ['chain'];
    const args: Map<string, string> = await parseArgs(requiredArguments)
        .catch(
            (e) => {
                console.error(e.message);
                process.exit();
            }
        );

    console.log('Arguments: ', args);

    const chainArg = args.get('chain')!;

    // Get chain info from shared network config
    const chainInfo = getNetwork(chainArg);

    if (!chainInfo) {
        throw Error(`No chain found for the identifier ${chainArg}`);
    }
    
    const privateKey = process.env[chainInfo.pkEnvVar];

    setOrDie(privateKey, 'Private Key');

    return { 
        args, 
        chainInfo,
        privateKey 
    };
}
