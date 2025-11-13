# ERC-7828: Interoperable Addresses using ENS

This repository contains a single contract, [`ChainResolver.sol`](src/ChainResolver.sol).
This contract serves as the on-chain single source of truth for chain data discovery. 
It is the implementation of the specifications outlined in [ERC-7828], allowing for the resolution of an [ERC-7930] _Interoperable Address_ from an _Interoperable Name_ of the form `example.eth@optimism#1234`.

It is fully compliant with ENS standards and best practices. [ENSIP-10]: Wildcard Resolution is utilised as the entry point for resolution of data.

## Ownership Model

The contract implements the `Ownable` ownership model. Only the owner of the contract can register chain data.
It is anticipated that the resolver will be owned by a multisig.

The [ERC-7930] chain identifier is set for each chain by this owner. It is immutable once set.

During initialization, administrative control of **additional** data stored under the chain specific namespace is handed off to the chain operator. This allows for chain operators to set standard ENS data - addresses, a content hash, and text records.

## Architectural points of note

- Under the hood, data is associated with the labelhash - the `keccak256` hash of the chain label. The resolver is namespace agnostic.

- There is an in-built discovery mechanism. `chainCount()` exposes the number of chains in the registry, while `getChainAtIndex(uint256)` allows clients to iterate through them. This is provided as a utility - usage of this registry **requires no external dependencies**.

- Forward Resolution requires the resolution of the `chain-id` data record ([ENSIP-24]) for the chain in question e.g. `base.<namespace>.eth`. The data returned is the [ERC-7930] _Interoperable Address_.

- Reverse Resolution requires the resolution of a text record ([ENSIP-5]) on the `reverse.<namespace>.eth` node. The key to use is the [ERC-7930] _Interoperable Address_ you want to reverse, prefixed with `chain-name:`. For example, `"chain-name:00010001010a00"`. The data returned is the human readable chain label. 

## Resolution flow:

<p align="center">
  <img src="img/resolutionflow.png" alt="Resolution flow" width="70%" />
</p>

## Security Considerations

The storage architecture within this contract has:

- **all** data records stored under one property, `dataRecords`
- **all** text records stored under one property, `textRecords`

For contract simplicity, the immutability of the `interoperable-address` data key is handled in the publicly exposed setter, `setData`. This function **does not** allow the setting of this key. This function has the `isChainOwner` modifier. The **internal** function `_setData` is called from the `_register` function to set this immutable key on registration. It **does not** have the `isChainOwner` modifier.  

Similarly, the immutability of the `chain-name:` prefixed text keys are set on the reverse node (`reverse.<namespace>.eth`) as part of the registration flow. Ownership of the reverse node **can not be set**. 

## Development

Checkout this repository, and install dependencies.

```bash
forge install
bun install
```

## Deployment

```bash
bun run deploy/DeployChainResolver.ts --chain=sepolia
```

## Testing

### Foundry

```bash
forge test -vv
```

### Blocksmith

```bash
bun run test/ChainResolver.blocksmith.ts
```

[ERC‑7828](https://eips.ethereum.org/EIPS/eip-7828)
[ERC‑7930](https://eips.ethereum.org/EIPS/eip-7930)
[CAIP‑2](https://chainagnostic.org/CAIPs/caip-2)
[ENSIP‑5](https://docs.ens.domains/ensip/5)
[ENSIP‑7](https://docs.ens.domains/ensip/7)
[ENSIP‑9](https://docs.ens.domains/ensip/9)
[ENSIP‑10](https://docs.ens.domains/ensip/10)
[ENSIP‑11](https://docs.ens.domains/ensip/11)
[ENSIP‑24](https://raw.githubusercontent.com/unruggable-labs/ensips/3f181f3be82b140ebc30d4d7caa6242520246dd6/ensips/24.md)
