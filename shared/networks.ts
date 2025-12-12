// Shared network configuration
import "dotenv/config";

export interface NetworkConfig {
  id: number;
  name: string;
  displayName: string;
  rpc: string | undefined;
  proxyAddress: string | undefined;
  domain: string;
  // Environment variable names for documentation/validation
  rpcEnvVar: string;
  proxyEnvVar: string;
  pkEnvVar: string;
}

export const NETWORKS: Record<string, NetworkConfig> = {
  mainnet: {
    id: 1,
    name: "mainnet",
    displayName: "Ethereum Mainnet",
    rpc: process.env.MAINNET_RPC_URL,
    proxyAddress: process.env.MAINNET_PROXY_ADDRESS,
    domain: "on.eth",
    rpcEnvVar: "MAINNET_RPC_URL",
    proxyEnvVar: "MAINNET_PROXY_ADDRESS",
    pkEnvVar: "MAINNET_PK",
  },
  sepolia: {
    id: 11155111,
    name: "sepolia",
    displayName: "Sepolia",
    rpc: process.env.SEPOLIA_RPC_URL,
    proxyAddress: process.env.SEPOLIA_PROXY_ADDRESS,
    domain: "cid.eth",
    rpcEnvVar: "SEPOLIA_RPC_URL",
    proxyEnvVar: "SEPOLIA_PROXY_ADDRESS",
    pkEnvVar: "SEPOLIA_PK",
  },
};

// Get network by name
export function getNetwork(name: string): NetworkConfig | undefined {
  return NETWORKS[name.toLowerCase()];
}

// Get network by chain ID
export function getNetworkById(id: number): NetworkConfig | undefined {
  return Object.values(NETWORKS).find((n) => n.id === id);
}

// Build a Map for legacy compatibility with deploy scripts
export const CHAIN_MAP = new Map<string | number, NetworkConfig>(
  Object.values(NETWORKS)
    .sort((a, b) => a.name.localeCompare(b.name))
    .flatMap((x) => [
      [x.name, x],
      [x.id, x],
    ])
);

