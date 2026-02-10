// Shared ABIs for ChainResolver
// Human-readable format works with both ethers and viem (via parseAbi)

// Core ChainResolver ABI - comprehensive list of all functions
export const RESOLVER_ABI = [
  // View functions
  "function owner() view returns (address)",
  "function chainCount() view returns (uint256)",
  "function getChainAdmin(string) view returns (address)",
  "function interoperableAddress(string) view returns (bytes)",
  "function chainLabel(bytes) view returns (string)",
  "function chainName(string) view returns (string)",
  "function getCanonicalLabel(string) view returns ((string label,bytes32 labelhash))",
  "function getText(string,string) view returns (string)",
  "function getData(string,string) view returns (bytes)",
  "function getAddr(string,uint256) view returns (bytes)",
  "function getContenthash(string) view returns (bytes)",
  "function resolve(bytes,bytes) view returns (bytes)",
  "function supportedTextKeys(bytes32) view returns (string[])",
  "function supportedDataKeys(bytes32) view returns (string[])",
  "function parentNamehash() view returns (bytes32)",
  "function defaultContenthash() view returns (bytes)",
  // Write functions
  "function register((string,string,address,bytes)) external",
  "function batchRegister((string,string,address,bytes)[]) external",
  "function registerAlias(string,bytes32) external",
  "function batchRegisterAlias(string[],bytes32[]) external",
  "function removeAlias(string) external",
  "function setText(bytes32,string,string) external",
  "function batchSetText(bytes32,string[],string[]) external",
  "function setData(bytes32,string,bytes) external",
  "function batchSetData(bytes32,string[],bytes[]) external",
  "function setAddr(bytes32,uint256,bytes) external",
  "function setContenthash(bytes32,bytes) external",
  "function setChainAdmin(bytes32,address) external",
  "function setDefaultContenthash(bytes) external",
  "function upgradeToAndCall(address,bytes) external",
] as const;

// ENSIP-5 text() interface
export const TEXT_ABI = [
  "function text(bytes32,string) view returns (string)",
] as const;

// ENSIP-24 data() interface
export const DATA_ABI = [
  "function data(bytes32,string) view returns (bytes)",
] as const;

// ENSIP-9 addr() interface
export const ADDR_ABI = [
  "function addr(bytes32) view returns (address)",
  "function addr(bytes32,uint256) view returns (bytes)",
] as const;

