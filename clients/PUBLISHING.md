# Publishing Clients

Each client folder has a local `publish.sh` entrypoint. It delegates to
`../../scripts/publish-client.sh`, which defaults to dry-run output:

```sh
clients/nodejs/publish.sh
clients/rust/publish.sh --dry-run
clients/python/publish.sh --release
```

Release mode intentionally expects the native package credentials and ecosystem
tools to already be configured by CI.

| Client | Registry or release channel | Package filtering |
| --- | --- | --- |
| Node/Bun/Deno/Solidity | npm-compatible package registries | root `files`, `.npmignore`, package-local `files` |
| Python | PyPI | `MANIFEST.in` and `pyproject.toml` |
| Java/Kotlin/Scala/Groovy/Clojure | Maven Central/Sonatype-compatible repositories | Maven Central plugin, Gradle/sbt/tools.build publication metadata |
| Rust | crates.io | `include` in `Cargo.toml` |
| Go/Swift/C/C++/Fortran/Zig/Crystal/MATLAB | git tags or source archives | language package manifests where available |
| C#/F# | NuGet Gallery | `.nuspec` files plus project item rules |
| PHP | Packagist | Composer `archive.exclude` |
| Ruby | RubyGems.org | `spec.files` in the `.gemspec` |
| Dart | pub.dev | `.pubignore` |
| Elixir/Erlang/Gleam | Hex.pm | package file lists in Mix/rebar/Gleam manifests |
| Haskell | Hackage | Cabal manifest controls |
| OCaml/ReasonML | opam Repository | opam metadata and Dune package files |
| Perl | CPAN | `MANIFEST.SKIP` |
| Lua | LuaRocks | rockspec |
| Nim | Nimble Package Index | `.nimble` install file list |
| R | CRAN or R-universe | `.Rbuildignore` and staged native source |
| Julia | Julia General Registry | `Project.toml` and Registrator |

The goal is that a package for one runtime never bundles every other
`clients/*` directory. The registry/package-control audit checks both the
manifest files and the publish dispatcher commands.

Docker-backed verification for the newer client scaffolds lives in
`scripts/docker-check-new-clients.sh`. Run the default set for practical local
coverage, or pass `--full` in CI to include heavier Haskell, OCaml/opam, Julia,
and JVM facade checks.

The registry/package-control audit is available without language toolchains:

```sh
scripts/audit-client-packaging.sh
```

JVM clients share the Java JNI bridge. Kotlin, Scala, Groovy, and Clojure expose
idiomatic wrappers over `com.oresoftware.flags2env.Flags2Env` and are packaged
for Maven-compatible registries. Java uses Sonatype's Central Publishing Maven
plugin; Gradle-based facades keep their repository URL configurable because
Sonatype does not provide an official Central Portal Gradle plugin.
