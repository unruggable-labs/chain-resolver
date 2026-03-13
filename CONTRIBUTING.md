# Contributing a Chain

This guide explains how to add your chain to the `on.eth` [chain registry-resolver](https://docs.ens.domains/resolvers/chain-registry-resolver).

## Submission Process

1. Fork this repository
2. Create a new file `data/chains/{your-label}.json`
3. Fill in the required fields (see schema below)
4. Submit a pull request

## File Naming

Your file must be named `{label}.json` where `label`:
- Is lowercase
- Uses hyphens for multi-word names (e.g., `arbitrum-nova`)
- Matches the `label` field inside the JSON
- Is unique across all chains

## Schema

### Required Fields

| Field | Type | Description |
|-------|------|-------------|
| `label` | string | Canonical identifier (e.g., `"optimism"`) |
| `chainName` | string | Display name (e.g., `"OP Mainnet"`) |
| `interoperableAddressHex` | string | ERC-7930 interoperable address (hex) |
| `textRecords.chainId` | string | [CAIP-2](https://standards.chainagnostic.org/CAIPs/caip-2) chain ID (e.g., `"eip155:10"`) |
| `textRecords.avatar` | string | Chain logo as `ipfs://` URL |
| `textRecords.header` | string | Header/banner image as `ipfs://` URL |

Alongside defining the `ipfs://` URLs for the avatar and header, you should include the raw image files in the respective `avatars`/`headers` folder.

### Optional Fields

| Field | Type | Description |
|-------|------|-------------|
| `aliases` | string[] | Alternative names that resolve to this chain |

You can defined any [text records](https://docs.ens.domains/ensip/5/) that will be set on the name under the top level `textRecords` key.

| Field | Type | Description |
|-------|------|-------------|
| `textRecords.url` | string | Official website |
| `textRecords.shortName` | string | Short identifier |
| `textRecords.avatar` | string | Chain logo (IPFS URL recommended) |
| `textRecords.header` | string | Header/banner image (IPFS URL) |
| `textRecords.brand` | string | Link to brand kit |
| `textRecords.com.x` | string | X/Twitter URL |
| `textRecords.com.discord` | string | Discord invite URL |
| `textRecords.com.github` | string | GitHub organization URL |
| `textRecords.org.telegram` | string | Telegram URL |

You can defined any [data records](https://docs.ens.domains/ensip/24/) that will be set on the name under the top level `dataRecords` key.

| Field | Type | Description |
|-------|------|-------------|
| `dataRecords.myBlob` | bytes | An arbitrary blob of data |

## Example

```json
{
  "label": "mychain",
  "chainName": "My Chain",
  "interoperableAddressHex": "0x0001000001a4b100",
  "aliases": ["mc"],
  "textRecords": {
    "chainId": "eip155:12345",
    "shortName": "mychain",
    "url": "https://mychain.io/",
    "com.x": "https://x.com/mychain",
    "com.discord": "https://discord.gg/mychain",
    "com.github": "https://github.com/mychain",
    "avatar": "ipfs://bafkreixxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
    "header": "ipfs://bafkreixxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
    "brand": "https://mychain.io/brand-kit"
  },
  "dataRecords": {
    "myBlob": "0x1234"
  }
}
```

## Images

For `avatar` and `header` images:
- Upload them to IPFS (using a provider like [Pinata](https://pinata.cloud))
- Use `ipfs://` URLs for the text record values 
- Avatar: square, recommended 256x256 or larger
- Header: recommended 1920x600 or similar banner ratio

## Interoperable Address

The `interoperableAddressHex` field contains your chain's [ERC-7930](https://eips.ethereum.org/EIPS/eip-7930) encoded identifier.

Take a look at [https://interopaddress.com/](https://interopaddress.com/) from the team at [Wonderland](https://wonderland.xyz/), and their [SDK](https://interopaddress.com/#sdk).

## Review Process

Pull requests are reviewed for:
- Valid JSON syntax
- Required fields present
- No conflicts with existing labels/aliases
- Reasonable metadata (working URLs, etc.)

## Questions

Open an issue if you have questions about the submission process.
