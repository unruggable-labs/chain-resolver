/**
 * @description Misc constants, types etc - re-exports from shared
 * @author      Thomas Clowes (clowes.eth)
 * @date        2025-08-22
 */

// Re-export everything from shared modules
export {
  REVERSE_REGISTRAR_ADDRESSES,
  PUBLIC_RESOLVER_ADDRESSES,
} from "../../shared/constants.ts";

export {
  NETWORKS,
  CHAIN_MAP,
  getNetwork,
  getNetworkById,
  type NetworkConfig,
} from "../../shared/networks.ts";

// Legacy type alias for backwards compatibility
export type ChainInfo = import("../../shared/networks.ts").NetworkConfig;
