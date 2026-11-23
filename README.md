# abi-encoding-pitfalls

A Solidity project about `abi.encodePacked` collisions: a set of DeFi encoders, a real collision found in one of them, its fix, and the tests around it.

[![CI](https://github.com/m15flores/abi-encoding-pitfalls/actions/workflows/ci.yml/badge.svg)](https://github.com/m15flores/abi-encoding-pitfalls/actions)
![Solidity](https://img.shields.io/badge/solidity-0.8.34-363636)
![License](https://img.shields.io/badge/license-MIT-blue)

> **Status: unaudited, not deployed.** A portfolio project. One function is vulnerable on purpose. Do not use it in production.

## Why

If two different inputs give the same bytes, they give the same hash, and a signature over one is valid for the other. `abi.encodePacked` joins its arguments with no separators, so when two or more of them have a variable length, the boundary between them is lost.

This project shows it with a real case. `encodeYieldStrategyPacked` joins a `string` and two arrays, and collides. `encodeYieldStrategyEncoded` is the same function built with `abi.encode`, and does not.

## The collision and the fix

A pool plus its weight takes 20 + 32 = 52 bytes, and a `string` can hold exactly those 52 bytes, so `encodeYieldStrategyPacked` returns the same output for these two calls. Here `p` is the 20 bytes of a pool address, `w` the 32 bytes of its weight, and `TAG` the literal that closes the payload:

```text
Call A:  name = "p w"   pools = []     weights = []     ->  p w TAG
Call B:  name = ""      pools = [p]    weights = [w]    ->  p w TAG
                                                            ^ same bytes
```

It is the same idea as joining `"ab"` with `"c"` and `"a"` with `"bc"`: both give `abc`, and the result does not say where the split was.

If anyone hashes or signs that output, a signature over one strategy is also valid for the other. `encodeYieldStrategyEncoded` uses `abi.encode`, which stores the offset and the length of every dynamic value, so the split is never ambiguous. The trade-off is size: every value is padded to 32 bytes.

## Which functions are at risk

The ambiguity needs two or more variable-length parts side by side. With a single one and fixed-size fields after it, the total length fixes where it ends, so different inputs cannot give the same bytes.

| Function | Dynamic parts | Verdict |
|---|---|---|
| `encodeYieldStrategyPacked` | `string` + 2 arrays | Collision (demonstrated) |
| `encodeSwapData` | 2 arrays | Safe only because the two lengths must be equal |
| `encodeFlashLoan`, `createDeFiTransactionId`, `createUserMultiPoolHash` | 1 each | Safe: one dynamic part |
| `encodeYieldStrategyEncoded` | uses `abi.encode` | Safe (tested) |
| The other 9 encoders | none | Fixed-size layout |

Foundry's linter flags two functions: a true positive (`encodeYieldStrategyPacked`) and a false positive (`encodeSwapData`). Both are silenced inline, with the reason. The fuzz tests on the single-dynamic functions can only fail to find a collision, they do not prove there is none. The length argument above does.

## API

`DeFiEncoder` has 15 encoders, with full NatSpec in [`src/DeFiEncoder.sol`](src/DeFiEncoder.sol). They fall into four groups:

- **Ids and hashes:** `createPoolIdentifier`, `createUserMultiPoolHash`, `createDeFiTransactionId`, `encodeYieldPosition`.
- **Payload and id together:** `encodeTradingPosition`, `encodeLimitOrder`.
- **Payloads:** `encodeSwapData`, `encodeFlashLoan`, `encodeStakingPoolConfig`, `encodeCrossChainBridgeData`, `encodeStopLossOrder`, `encodeTakeProfitOrder`, `encodeTrailingStopOrder`.
- **The pair:** `encodeYieldStrategyPacked` (vulnerable by design) and `encodeYieldStrategyEncoded`.

## Tests

**41 tests, 100% coverage**

```text
╭---------------------+-----------------+-----------------+---------------+-----------------╮
| File                | % Lines         | % Statements    | % Branches    | % Funcs         |
+===========================================================================================+
| src/DeFiEncoder.sol | 100.00% (53/53) | 100.00% (54/54) | 100.00% (5/5) | 100.00% (15/15) |
|---------------------+-----------------+-----------------+---------------+-----------------|
| Total               | 100.00% (53/53) | 100.00% (54/54) | 100.00% (5/5) | 100.00% (15/15) |
╰---------------------+-----------------+-----------------+---------------+-----------------╯
```

The attack tests are the collision, the collision for any prefix, pool and weight, and the repeated `positionId` in the same block. The fuzz tests cover pool id symmetry and fee sensitivity, limit order and staking config fields, flash loan length, and the length of `encodeSwapData` for any array size.

## Security

**Unaudited.** Known limitations:

- One function is vulnerable on purpose.
- No `chainId` or contract address in the encoded data, so signed payloads could be replayed elsewhere. The fix is EIP-712.
- `createPoolIdentifier` accepts equal tokens and `address(0)`.
- `positionId` repeats for the same parameters in the same block, and `createUserMultiPoolHash` depends on the order and accepts duplicates.

## Development

Requires [Foundry](https://book.getfoundry.sh/).

```bash
git clone --recurse-submodules https://github.com/m15flores/abi-encoding-pitfalls
cd abi-encoding-pitfalls
forge build
forge test
```

## Future work

- Events on the functions that return an id. I left them out on purpose: an encoder should not emit them.
- Compute the ids in Go and compare them with fixed test vectors.
- `encodeSwapData` without its length check would collide for real. I did not test that variant.

## License

MIT