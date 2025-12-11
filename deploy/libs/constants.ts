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

// ENS Reverse Registrar addresses per chain
// See: https://docs.ens.domains/learn/deployments
export const REVERSE_REGISTRAR_ADDRESSES: Record<number, string> = {
    1: "0xa58E81fe9b61B5c3fE2AFD33CF304c454AbFc7Cb",      // Mainnet
    11155111: "0xA0a1AbcDAe1a2a4A2EF8e9113Ff0e02DD81DC0C6", // Sepolia
};

// ENS Public Resolver addresses per chain
export const PUBLIC_RESOLVER_ADDRESSES: Record<number, string> = {
    1: "0xF29100983E058B709F3D539b0c765937B804AC15",      // Mainnet
    11155111: "0xE99638b40E4Fff0129D56f03b55b6bbC4BBE49b5", // Sepolia
};