# Chain Registry-Resolver [An on-chain single source of truth for blockchain metadata.]

## Overview

The Chain Registry-Resolver is a smart contract that acts as a **canonical, on-chain registry** for blockchain metadata. It serves as the resolver for the `on.eth` namespace and enables applications and users to retrieve metadata for *any* blockchain using a single human-readable identifier, such as `base` or `solana`.

Historically, blockchain metadata has been stored in centralized, fragmented repositories maintained by third parties. The Chain Registry-Resolver brings this metadata on-chain into a single, extensible registry, where control and update authority are delegated to the relevant chain operators.
  
Full documentation can be found within the Ethereum Name Service (ENS) documentation: [Chain Registry-Resolver](https://docs.ens.domains/resolvers/chain-registry-resolver).

## Adding a chain

To have a chain added to the onchain registry, please create a Pull Request subject to our [Contribution Guidelines](./CONTRIBUTING.md). Once submitted data has been merged into this repo, it will be registered on-chain.

## Taking ownership of a chain label

To take ownership of a chain label within the on-chain registry resolver please email `chain-registry [AT] unruggable [DOT] com` outlining the label that you would like to take control of, who you are, who you represent, and any corroborating evidence. We are currently working on defining process surrounding this.

## Development

Checkout this repository, and install dependencies.

```bash
forge install foundry-rs/forge-std@v1.10.0 
forge install OpenZeppelin/openzeppelin-contracts@v5.4.0 
forge install OpenZeppelin/openzeppelin-contracts-upgradeable@v5.5.0 
forge install ensdomains/ens-contracts@v1.6.2 
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