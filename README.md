# Unified Chain Resolver (Registry + Resolver)

This repo contains a single contract — [`ChainResolver.sol`](src/ChainResolver.sol) — that lets clients look up ENS records and reverse names in one place. Read operations use the ENSIP‑10 extended resolver entrypoint `resolve(bytes name, bytes data)` (https://docs.ens.domains/ensip/10). Only the contract owner can make changes (ideally a multisig).

### Why this structure works
- Everything is keyed by labelhash (computed as `labelHash = keccak256(bytes(label))`, for example with `label = "optimism"`). This keeps us agnostic to the final namespace (`cid.eth`, `on.eth`, `l2.eth`, etc.), so we can change hierarchies later without migrating fields.
- One source of truth: Ownership, 7930 chain IDs ([ERC‑7930](https://eips.ethereum.org/EIPS/eip-7930)), ENS records, and reverse lookups live in one place.
- ENSIP‑10 Extended Resolver: Once registered, the chain owner (or an authorised operator) can set ENS fields like addresses, contenthash and other text/data fields. Reads go through the extended resolver entrypoint `resolve(bytes name, bytes data)` (see ENSIP‑10), so clients can call the standard ENS fields - `addr`, `contenthash`, `text`, and `data` - to pull chain metadata directly from an ENS name like `optimism.cid.eth`. For available fields and examples, see [Contract Interfaces](#contract-interfaces).
- Clear forward and reverse: Forward returns a chain’s 7930 identifier; reverse maps 7930 bytes back to the chain name.

## ChainResolver.sol

- The `chainId` bytes follow the 7930 chain identifier format; see [7930 Chain Identifier](#7930-chain-identifier-no-address).
- Forward mapping: `labelHash → chainId (bytes)`
- Reverse mapping: `chainId (bytes) → chainName (string)`
- Per‑label ENS records: `addr(coinType)`, `contenthash`, `text`, and `data`.
- Ownership and operator permissions per label owner.

### Resolution flow:

<p align="center">
  <img src="img/resolutionflow.png" alt="Resolution flow" width="70%" />
  
</p>

Forward resolution (label → 7930):
The ENS field `text(..., "chain-id")` (per [ENSIP‑5](https://docs.ens.domains/ensip/5)) returns the chain’s 7930 ID as a hex. This value is written at registration by the contract owner (e.g., a multisig) and the resolver ignores any user‑set text under that key. To resolve a chain ID:
 - DNS‑encode the ENS name (e.g., `optimism.cid.eth`).
 - Compute `labelHash = keccak256(bytes(label))` (e.g., `label = "optimism"`).
 - Call `resolve(name, abi.encodeWithSelector(text(labelHash, "chain-id")))` → returns a hex string.

Reverse resolution (7930 → name):
- Pass a key prefixed with `"chain-name:"` and suffixed with the 7930 hex via either `text(bytes32,string)` (per ENSIP‑5) or `data(bytes32,string)` (per [ENSIP‑TBD‑19](https://github.com/nxt3d/ensips/blob/ensip-ideas/ensips/ensip-TBD-19.md)); this uses the `chain-name:` service key parameter (per [ENSIP‑TBD‑17](https://github.com/nxt3d/ensips/blob/ensip-ideas/ensips/ensip-TBD-17.md)). For example:

  - serviceKey (string): `"chain-name:<7930-hex>"`
  - Calls:
    - `resolve(name, encode(text(labelHash, serviceKey)))`
    - `resolve(name, encode(data(labelHash, serviceKey)))`


## Contract Interfaces

Core reads and admin (see [src/interfaces/IChainResolver.sol](src/interfaces/IChainResolver.sol)):

```solidity
function chainId(bytes32 labelHash) external view returns (bytes memory);
function chainName(bytes calldata chainIdBytes) external view returns (string memory);
function register(string calldata chainName, address owner, bytes calldata chainId) external; // owner-only
function setLabelOwner(bytes32 labelHash, address owner) external; // label owner or operator
function setOperator(address operator, bool isOperator) external;   // per-owner operator
```

ENS fields available via `IExtendedResolver.resolve(name,data)`:
- `addr(bytes32)` and `addr(bytes32,uint256)` → EVM address per coin type (60 = ETH) — multichain address resolution per [ENSIP‑9](https://docs.ens.domains/ensip/9)
- `contenthash(bytes32)` → bytes — per [ENSIP‑7](https://docs.ens.domains/ensip/7)
- `text(bytes32,string)` → string — per ENSIP‑5 (with special handling for `"chain-id"` and `"chain-name:"`)
- `data(bytes32,string)` → bytes — per ENSIP‑TBD‑19 (with special handling for `"chain-name:"`)

## 7930 Chain Identifier

We use the chain identifier variant of ERC‑7930, which contains no address payload. The layout is:

- Version (4 bytes) | ChainType (2 bytes) | ChainRefLen (1 byte) | ChainRef (N bytes) | AddrLen (1 byte) | Addr (0 bytes)

The examples below show how to build the full 7930 identifier.

- Optimism (chain 10):
  - Fields: `00000001` (Version=1), `0001` (EVM), `01` (ChainRefLen=1), `0a` (ChainRef=10), `00` (AddrLen=0)
  - 7930 identifier: `0x000000010001010a00`

- Arbitrum (chain 102):
  - Fields: `00000001` (Version=1), `0001` (EVM), `01` (ChainRefLen=1), `66` (ChainRef=102), `00` (AddrLen=0)
  - 7930 identifier: `0x000000010001016600`

- Solana (mainnet):
  - Fields: `00000001` (Version=1), `0002` (Solana), `20` (ChainRefLen=32), `45296998a6f8e2a784db5d9f95e18fc23f70441a1039446801089879b08c7ef0` (ChainRef = 32‑byte genesis hash), `00` (AddrLen=0)
  - 7930 identifier: `0x0000000100022045296998a6f8e2a784db5d9f95e18fc23f70441a1039446801089879b08c7ef000`

### Size limits

EVM example sizes: Optimism/Arbitrum are 9 bytes total: 4 (Version) + 2 (ChainType) + 1 (ChainRefLen) + 1 (ChainRef; 1‑byte here) + 1 (AddrLen=0).

Solana example size: 40 bytes total: 4 (Version) + 2 (ChainType) + 1 (ChainRefLen) + 32 (ChainRef) + 1 (AddrLen=0).

- 7930 theoretical maximum: 263 bytes total (8 bytes overhead + up to 255‑byte ChainRef; no address payload).
- EVM practical maximum (CAIP‑2 aligned): CAIP‑2 uses `eip155:<reference>`, where `<reference>` is the EIP‑155 chain ID. We treat `<reference>` as an integer limited to 32 bytes. That makes an EVM 7930 identifier at most 8 + 32 = 40 bytes. See CAIP‑2: https://chainagnostic.org/CAIPs/caip-2
- Non‑EVM common case: Most CAIP‑2 references are ≤ 32 bytes, so ≤ 40‑byte 7930 IDs are typical; some namespaces may exceed this, and 7930 still allows up to 263 bytes.

## Development

```bash
forge install
bun install
```

### Foundry tests

```bash
forge test -vv
```

### Blocksmith test (live RPC)

```bash
# Requires INFURA_API_KEY and <CHAIN>_PK in .env (see deploy/libs/constants.ts)
bun run test/ChainResolver.blocksmith.ts -- --chain=sepolia
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
- [CAIP‑2](https://chainagnostic.org/CAIPs/caip-2) — Blockchain ID (namespace:reference) mapping (`eip155:<id>`)
- [ENSIP‑5](https://docs.ens.domains/ensip/5) — Text records
- [ENSIP‑7](https://docs.ens.domains/ensip/7) — Contenthash records
- [ENSIP‑9](https://docs.ens.domains/ensip/9) — Multi‑coin addresses
- [ENSIP‑10](https://docs.ens.domains/ensip/10) — Extended resolver
- [ENSIP‑TBD‑17](https://github.com/nxt3d/ensips/blob/ensip-ideas/ensips/ensip-TBD-17.md) — Service Key Parameters (e.g., `chain-name:`)
- [ENSIP‑TBD‑18](https://github.com/nxt3d/ensips/blob/ensip-ideas/ensips/ensip-TBD-18.md) — Global `chain-id` text record
- [ENSIP‑TBD‑19](https://github.com/nxt3d/ensips/blob/ensip-ideas/ensips/ensip-TBD-19.md) — `data()` records for chain IDs
