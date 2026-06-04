# flags2env Elixir

Elixir facade for the flags2env native parser.

```elixir
env = Flags2Env.parse(["app", "--port", "8080"], ".cli-flags.toml")
```

The Hex package is published as `flags2env_elixir` and carries the Erlang NIF
source plus package-local parser sources under `native/`.
