# flags2env Solidity

Solidity cannot execute the native `flags2env` parser on-chain: contracts cannot
read `.cli-flags.toml`, inspect process argv, or load a C shared library.

This package is an adapter for contracts that consume off-chain `flags2env`
results. Run `flags2env` off-chain, ABI-encode the resulting key/value pairs,
and use `Flags2Env.hash` or `Flags2Env.requireHash` to verify the committed
configuration inside a contract.
