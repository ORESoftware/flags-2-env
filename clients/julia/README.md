# Flags2Env.jl

Julia bindings for the native flags2env C ABI.

```julia
using Flags2Env

env = Flags2Env.parse(["app", "--port", "8080"]; config_path=".cli-flags.toml")
```

The package expects `libflags2env.so`, `libflags2env.dylib`, or
`flags2env.dll` to be available on the platform library path, or pass
`library_path` explicitly to `parse`, `parse_process`, or `apply`.
