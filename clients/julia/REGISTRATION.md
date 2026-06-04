# Julia Registration

This Julia package lives in a repository subdirectory. After tagging the
release commit, trigger Registrator from GitHub with:

```text
@JuliaRegistrator register subdir=clients/julia
```

The package registration root is `clients/julia`, which contains
`Project.toml`, `LICENSE`, `README.md`, `src/`, and `test/`.
