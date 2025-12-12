// Shared constants for ChainResolver

// Data record key constants
export const INTEROPERABLE_ADDRESS_DATA_KEY = "interoperable-address";

// Text record prefix for reverse resolution (ERC-7828)
export const CHAIN_LABEL_PREFIX = "chain-label:";

// Cointype constants
export const ETHEREUM_COIN_TYPE = 60;

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

