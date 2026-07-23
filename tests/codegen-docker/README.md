# Generated-code Docker matrix

This suite generates every supported interface from
`tests/codegen/.cli-flags.toml`, compiles it in the target language's official
container image, and runs a small program against the resulting type.

The Node.js target additionally installs the packed `@oresoftware/f2e` package
and runs the full `parseFromArgs()` plus schema-backed `coerce()` flow.

Run the complete matrix:

```sh
tests/codegen-docker/run.sh
```

Run one or more targets:

```sh
tests/codegen-docker/run.sh nodejs rust dart
```

The tests are repository-only development assets. Homebrew installs an explicit
allowlist of the CLI, native headers/libraries, and shell helpers; it does not
install this directory.
