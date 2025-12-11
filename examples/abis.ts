// Shared ABIs for ChainResolver demos
// Human-readable format works with both ethers and viem (via parseAbi)

// ChainResolver ABI
export const RESOLVER_ABI = [
  "function resolve(bytes,bytes) view returns (bytes)",
  "function interoperableAddress(bytes32) view returns (bytes)",
  "function chainLabel(bytes) view returns (string)",
  "function chainName(bytes) view returns (string)",
  "function chainCount() view returns (uint256)",
] as const;

// ENSIP-5 text() interface
export const TEXT_ABI = [
  "function text(bytes32,string) view returns (string)",
] as const;

// ENSIP-24 data() interface
export const DATA_ABI = [
  "function data(bytes32,string) view returns (bytes)",
] as const;
