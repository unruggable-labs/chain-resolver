/**
 * @description Initialization function for the deployment scripts.
 * @author      Thomas Clowes (clowes.eth)
 * @date        2025-08-22
 */

import { parseArgs, setOrDie } from "./utils.ts";
import { CHAIN_MAP, type ChainInfo } from "./constants.ts";

import 'dotenv/config'

export type InitData = {
    args: Map<string, string>
    chainInfo: ChainInfo,
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

    // Loop over all known chains and see if we have a PK env variable set
    const chainInfo = CHAIN_MAP.get(chainArg);

    if (!chainInfo) {
        throw Error(`No chain found for the identifier ${chainArg}`);
    }
    
    const pkKey = `${chainInfo.name.toUpperCase().replace('-', '_')}_PK`;
    const privateKey = process.env[pkKey];

    setOrDie(privateKey, 'Private Key');

    return { 
        args, 
        chainInfo,
        privateKey 
    };
}
