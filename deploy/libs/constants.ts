/**
 * @description Misc constants, types etc
 * @author      Thomas Clowes (clowes.eth)
 * @date        2025-08-22
 */

import 'dotenv/config'

// Type for a specific chain
export type ChainInfo = {
    readonly id: number;
    readonly name: string;
    readonly rpc: string;
    privateKey?: string;
};

export const CHAIN_MAP = new Map<string, ChainInfo>(
    [
        {
            id: 1,
            name: 'mainnet',
            rpc: process.env.MAINNET_RPC_URL!,
        },
        {
            id: 11155111,
            name: 'sepolia',
            rpc: process.env.SEPOLIA_RPC_URL!,
        },
    ]
    .sort((a, b) => a.name.localeCompare(b.name))
    .map((x) => [x.name, x])
);