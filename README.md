# ERC-7828: Interoperable Addresses using ENS

This repository contains a single contract, [`ChainResolver.sol`](src/ChainResolver.sol).

This contract serves as the on-chain single source of truth for chain data discovery. 
It is the implementation of the specifications outlined in [ERC-7828], allowing for the resolution of an [ERC-7930] _Interoperable Address_ from an _Interoperable Name_ of the form `example.eth@optimism#1234`.

It is fully compliant with ENS standards and best practices. [ENSIP-10]: Wildcard Resolution is utilised as the entry point for resolution of data.

## Ownership Model

The contract implements the `Ownable` ownership model by proxy of Open Zeppelin's `OwnableUpgradeable` module. 

Only the owner of the contract can register chain data. The resolver will be owned by a multisig with the following signers:

  - Josh Rudolf (EF)
  - Thomas Clowes (Unruggable)
  - OxOrca (Wonderland)

The [ERC-7930] chain identifier is set for each chain by this owner. It is immutable once set.

During initialization, administrative control of **additional** data stored under the chain specific namespace is handed off to the chain operator. This allows for chain operators to set standard ENS data - addresses, a content hash, and text records.

## Architectural points of note

- The `ChainResolver` is to be deployed behind an [ERC-1967] proxy to allow for it to be upgraded if neccesary. This path is secured by the multisig, with ultimate control falling to the ENS DAO who will be the underlying owner of the `on.eth` name. 

- Under the hood, data is associated with the labelhash - the `keccak256` hash of the chain label. The resolver is tied to a namespace defined on initialization. The namespace for [ERC-7828] is `on.eth`.

- There is an alias system to allow for commonly understood aliases to point to the same chain data. e.g, `arb1.on.eth` will point to the same underlying data as `arbitrum.on.eth`.

- There is an in-built discovery mechanism. `chainCount()` exposes the number of chains in the registry, while `getChainAtIndex(uint256)` allows clients to iterate through them. This is provided as a utility - usage of this registry **requires no external dependencies**.

- Forward Resolution requires the resolution of the `interoperable-address` data record ([ENSIP-24]) for the chain in question e.g. `base.<namespace>.eth`. The data returned is the [ERC-7930] _Interoperable Address_.

- Reverse Resolution requires the resolution of a text record ([ENSIP-5]) on the `reverse.<namespace>.eth` node. The key to use is the [ERC-7930] _Interoperable Address_ you want to reverse, prefixed with `chain-name:`. For example, `"chain-name:00010001010a00"`. The data returned is the human readable chain label. 

## Security Considerations

The storage architecture within this contract has:

- **all** data records stored under one property, `dataRecords`
- **all** text records stored under one property, `textRecords`

For contract simplicity, the immutability of the `interoperable-address` data key is handled in the publicly exposed setter, `setData`. This function **does not** allow the setting of this key.This function has the `onlyChainOwner` modifier. 
The **internal** function `_setData` is called from the `_register` function to set this immutable key on registration. It has the `onlyOwner` modifier - only the multisig can register chains. 

Similarly, the immutability of the `chain-name:` prefixed text keys are set on the reverse node (`reverse.<namespace>.eth`) as part of the registration flow. Ownership of the reverse node **can not be set**. 

## Development

Checkout this repository, and install dependencies.

```bash
forge install foundry-rs/forge-std@v1.10.0 
forge install OpenZeppelin/openzeppelin-contracts@v5.4.0 
forge install OpenZeppelin/openzeppelin-contracts-upgradeable@v5.5.0 
forge install ensdomains/ens-contracts@v1.6.0 
git submodule add -b v4.9.3 https://github.com/OpenZeppelin/openzeppelin-contracts lib/openzeppelin-contracts-v4

bun install
```

## Deployment

The following **interactive** scripts are provided to allow for the deployment, initialization, and upgrading of the `ChainResolver`.

```bash
bun run deploy/DeployChainResolver.ts --chain=sepolia
```

This command deploys the `ChainResolver` behind an `ERC1967Proxy`.

The script deploys the contract as an EOA, and transfers ownership to a predefined address (the multisig).

```bash
bun run deploy/RegisterChains.ts --chain=sepolia
```

This command registers chains.

```bash
bun run deploy/DoUpgrade.ts --chain=sepolia
```

This command deploys a new `ChainResolver` and upgrades the proxy referenced implementation.
This is for demonstration purposes. In practice, once ownership of the proxy has been transferred to the multsig all upgrades will need to be executed through it.


## Testing

### Foundry

```bash
forge test -vv
```

### Blocksmith

```bash
bun run test/ChainResolver.blocksmith.ts
```

[ERC-7828]: https://eips.ethereum.org/EIPS/eip-7828
[ERC-7930]:https://eips.ethereum.org/EIPS/eip-7930
[CAIP-2]: https://chainagnostic.org/CAIPs/caip-2
[ENSIP-5]: https://docs.ens.domains/ensip/5
[ENSIP-10]: https://docs.ens.domains/ensip/10
[ENSIP-24]: https://docs.ens.domains/ensip/24


