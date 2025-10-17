# Unified Chain Resolver (Registry + Resolver)

This repo contains a single contract — [`ChainResolver.sol`](src/ChainResolver.sol) — that lets clients look up chain IDs and ENS records in one place. Read operations use the ENSIP‑10 extended resolver entrypoint `resolve(bytes name, bytes data)` (https://docs.ens.domains/ensip/10). Only the contract owner (ideally a multisig) can make changes to the label–chain ID pairs.

### Why this structure works
- Everything is keyed by labelhash (computed as `labelhash = keccak256(bytes(label))`, for example with `label = "optimism"`). This keeps the contract agnostic to the final namespace (`cid.eth`, `on.eth`, `l2.eth`, etc.), so we can change hierarchies later without migrating fields.
- One source of truth: Ownership, 7930 chain IDs ([ERC‑7930](https://eips.ethereum.org/EIPS/eip-7930)), ENS records, and reverse lookups live in one place.
- ENSIP‑10 Extended Resolver: Once registered, the chain owner (or an authorised operator) can set ENS fields like addresses, contenthash and other text/data fields. Reads go through the extended resolver entrypoint `resolve(bytes name, bytes data)` (see ENSIP‑10), so clients can call the standard ENS fields - `addr`, `contenthash`, and `text` - to pull chain metadata directly from an ENS name like `optimism.cid.eth`. For available fields and examples, see [Contract Interfaces](#contract-interfaces).
- Clear forward and reverse: Forward returns a chain’s 7930 identifier; reverse maps 7930 bytes back to the chain name.

## ChainResolver.sol

- The `chainId` bytes follow the 7930 chain identifier format; see [7930 Chain Identifier](#7930-chain-identifier-no-address).
- Forward mapping: `labelhash → chainId (bytes)`
- Reverse mapping: `chainId (bytes) → chainName (string)`
- Per‑label ENS records: `addr(coinType)`, `contenthash`, `text`, and `data`.
- Ownership and operator permissions per label owner.

### Resolution flow:

<p align="center">
  <img src="img/resolutionflow.png" alt="Resolution flow" width="70%" />
  
</p>

Forward resolution (label → 7930):
The ENS field `text(..., "chain-id")` (per [ENSIP‑5](https://docs.ens.domains/ensip/5)) returns the chain’s 7930 ID as a hex string. The field `data(..., "chain-id")` returns the raw 7930 bytes (per ENSIP‑TBD‑19). This value is written at registration by the contract owner (e.g., a multisig) and the resolver ignores any user‑set text under that key. To resolve a chain ID:
 - DNS‑encode the ENS name (e.g., `optimism.cid.eth`).
 - Compute the node of the ENS name (e.g., using `ethers`: `namehash(name)`)
 - Calls:
    -  `resolve(name, abi.encodeWithSelector(text(node, "chain-id")))` → returns a hex string.
    - `resolve(name, abi.encodeWithSelector(data(node, "chain-id")))` → returns raw bytes.

Chain name (forward):
- `resolve(name, abi.encodeWithSelector(text(node, "chain-name")))` → returns the canonical chain name (e.g., "Optimism").

Reverse resolution (7930 → name):
- Reverse lookups are performed via the ENS text interface and are namespace‑agnostic. They are served when:
  - `name` is the DNS‑encoded namespace root `<namespace>.eth` (for example, `cid.eth`), and
  - the `node` argument equals `namehash("reverse." + <namespace>.eth)` (for example, `namehash("reverse.cid.eth")`).

Pass a key prefixed with `"chain-name:"` and suffixed with the 7930 hex using `text(bytes32 node,string key)` (per ENSIP‑5). This follows the `chain-name:` text key parameter standard (per [ENSIP‑TBD‑17](https://github.com/nxt3d/ensips/blob/ensip-ideas/ensips/ensip-TBD-17.md)). For example:

  - Text key parameter (string): `"chain-name:<7930-hex>"`
  - Call (using `name = dnsEncode("cid.eth")`, `node = namehash("reverse.cid.eth")`):
    - `resolve(name, encode(text(node, serviceKey)))`


## Contract Interfaces

Core reads and admin (see [src/interfaces/IChainResolver.sol](src/interfaces/IChainResolver.sol)):

```solidity
function chainId(bytes32 labelhash) external view returns (bytes memory);
function chainName(bytes calldata chainIdBytes) external view returns (string memory);
function register(string calldata label, string calldata chainName, address owner, bytes calldata chainId) external; // owner-only
function batchRegister(string[] calldata labels, string[] calldata chainNames, address[] calldata owners, bytes[] calldata chainIds) external; // owner-only
function setLabelOwner(bytes32 labelhash, address owner) external; // label owner or operator
function setOperator(address operator, bool isOperator) external;   // per-owner operator
```

ENS fields available via `IExtendedResolver.resolve(name,data)`:
- `addr(bytes32 node)` → address (ETH, coin type 60) — per [ENSIP‑1](https://docs.ens.domains/ensip/1)
- `addr(bytes32 node,uint256 coinType)` → bytes (raw multi‑coin value) — per [ENSIP‑9](https://docs.ens.domains/ensip/9)
- `contenthash(bytes32 node)` → bytes — per [ENSIP‑7](https://docs.ens.domains/ensip/7)
- `text(bytes32 node,string key)` → string — per ENSIP‑5 (with special handling for `"chain-id"`, `"chain-name"` and `"chain-name:"`)
- `data(bytes32 node,string key)` → bytes — per ENSIP‑TBD‑19 (with special handling for `"chain-id"`)

## 7930 Chain Identifier

We use the chain identifier variant of ERC‑7930. Examples:

- Optimism (chain 10): `0x000000010001010a00`
- Arbitrum (chain 102): `0x000000010001016600`

See [ERC‑7930: Universal Chain Identifier](https://eips.ethereum.org/EIPS/eip-7930) for the full specification.


## Development

```bash
forge install
bun install
```

### Foundry tests

```bash
forge test -vv
```

### Blocksmith test

```bash
bun run test/ChainResolver.blocksmith.ts
```

## Deploy & Resolve Workflow

1) Deploy unified resolver

```bash
bun run deploy/DeployChainResolver.ts -- --chain=sepolia
```

2) Capture deployed address in `.env`:

```
# Unified ChainResolver deployed address
CHAIN_RESOLVER_ADDRESS=0x...
```

3) Register a chain and set records

```bash
bun run deploy/RegisterChainAndSetRecords.ts -- --chain=sepolia
```

4) Set records for an existing label

```bash
bun run deploy/SetRecords.ts -- --chain=sepolia
```

5) Resolve records (addr, contenthash, text, data)

```bash
bun run deploy/ResolveRecords.ts -- --chain=sepolia
```

6) Resolve chain-id by label

```bash
bun run deploy/ResolveByLabel.ts -- --chain=sepolia
```

7) Reverse resolve by chain‑id

```bash
bun run deploy/ReverseResolveByChainId.ts -- --chain=sepolia
```

## References
- [ERC‑7930](https://eips.ethereum.org/EIPS/eip-7930) — Chain‑aware addresses (used here for chain identifiers)
- [CAIP‑2](https://chainagnostic.org/CAIPs/caip-2) — Chain IDs (namespace:reference) mapping (`eip155:<id>`)
- [ENSIP‑5](https://docs.ens.domains/ensip/5) — Text records
- [ENSIP‑7](https://docs.ens.domains/ensip/7) — Contenthash records
- [ENSIP‑9](https://docs.ens.domains/ensip/9) — Multi‑coin addresses
- [ENSIP‑10](https://docs.ens.domains/ensip/10) — Extended resolver
- [ENSIP‑11](https://docs.ens.domains/ensip/11) — Coin types (SLIP‑44 mapping)
- [ENSIP‑TBD‑17](https://github.com/nxt3d/ensips/blob/ensip-ideas/ensips/ensip-TBD-17.md) — Service Key Parameters (e.g., `chain-name:`)
- [ENSIP‑TBD‑18](https://github.com/nxt3d/ensips/blob/ensip-ideas/ensips/ensip-TBD-18.md) — Global `chain-id` text record
- [ENSIP‑TBD‑19](https://github.com/nxt3d/ensips/blob/ensip-ideas/ensips/ensip-TBD-19.md) — `data()` records for chain IDs
