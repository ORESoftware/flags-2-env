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
| Bash/Zsh | Homebrew-installed shell helpers or git tags | shell source files installed with the native CLI |
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

The Go client is a module rooted at `clients/golang`, so its release tags use
the Go module subdirectory prefix, for example `clients/golang/v0.1.0`, so
`pkg.go.dev` and the Go command resolve the module version correctly. The Go
module carries package-local copies of `src/parser.c` and `src/parser.h` so
consumers can build it from a module cache without a prebuilt native library;
the packaging audit verifies those copies match the root C parser sources.

The Java Maven package carries package-local copies of the native parser under
`clients/java/native`, and the JNI source includes the local `parser.h` instead
of reaching back to the repository root.

The Erlang Hex package carries `parser.c` and `parser.h` beside the NIF source,
and the Gleam Docker smoke uses the same package-local Erlang native sources.
The Elixir facade publishes as `flags2env_elixir`, includes its own package-local
copy of the Erlang NIF source and parser sources, and avoids reaching into the
Erlang client tree during package smoke checks.

The C# and F# NuGet packages carry package-local `native/parser.c` and
`native/parser.h` copies, so the native source files in each `.nupkg` do not
depend on repository-relative `../../src` paths.

The C++ package is rooted at `clients/cpp` and carries package-local parser
sources under `clients/cpp/native`, so its CMake target can be consumed without
repository-relative `../../src` paths.

SwiftPM expects a `Package.swift` manifest in the repository root and a full
semantic-version tag such as `0.1.0`, so the root manifest points at
`clients/swift` while the Swift publish command uses an unprefixed SemVer tag.

The Julia package is rooted at `clients/julia`, not the repository root. Its
publish preflight runs `Pkg.test()` in that project and then prints the
Registrator trigger comment:

```text
@JuliaRegistrator register subdir=clients/julia
```

The Zig package is rooted at `clients/zig` and carries package-local copies of
`src/parser.c` and `src/parser.h` under `clients/zig/native`. The packaging
audit verifies those copies match the root parser sources so consumers can build
the Zig package without relying on repository-relative `../../src` paths.

Docker-backed verification for the newer client scaffolds lives in
`scripts/docker-check-new-clients.sh`. Run the default set for practical local
coverage, or pass `--full` in CI to include heavier Haskell, OCaml/opam, Julia,
Scala, Kotlin, Groovy, and JVM facade checks. The Haskell full check runs the
Cabal smoke test suite against the freshly built native library. The GitHub
Actions client packaging workflow runs the default Docker set automatically and
exposes a manual `full_docker_checks` input for the heavyweight set.

The registry/package-control audit is available without language toolchains:

```sh
scripts/audit-client-packaging.sh
npm run pack:audit
npm run release:audit
```

The release matrix audit verifies that every required language row has the
expected registry destination, client folder, publish wrapper, package-control
metadata, source files, tests where practical, and the expected dry-run publish
command. It also checks ecosystem-specific manifest controls such as npm
allowlists, `MANIFEST.in`, Cargo `include`, `.gemspec` file lists, Composer
archive excludes, Maven/Gradle resource excludes, NuGet file excludes,
`.pubignore`, SwiftPM excludes, Hex file lists, Cabal/opam metadata, CPAN skip
rules, LuaRocks modules, Nimble install files, R build ignores, Julia subdir
registration metadata, and Homebrew shell helper installation. The
package-control, release matrix, and npm
package-content audits run in `.github/workflows/client-packaging.yml`
alongside the core shell integration tests whenever client, packaging, script,
source, or test files change.

The Rust crate includes `clients/rust/native/parser.c` and
`clients/rust/native/parser.h` in its Cargo allowlist. Its packaged smoke test
compiles those local sources into a temporary shared library, so `cargo test`
does not depend on the monorepo `build/` directory or shared test fixtures.

The C# and F# smoke programs use the package-local `native/parser.c` fallback
when `FLAGS2ENV_NATIVE_LIB` is not set and write their own temporary TOML
fixture when `FLAGS2ENV_FIXTURE` is absent. The F# smoke program registers a
`DllImportResolver` before the first native call so `DllImport("flags2env")`
loads that temporary library.

The MATLAB source archive includes `+flags2env`, `native/parser.h`, and
`native/parser.c`. The loader defaults to that package-local header for
`loadlibrary`, while callers can still pass an explicit shared library or
header path when embedding flags2env elsewhere.

The native C CLI has a Homebrew formula at
`packaging/homebrew/Formula/flags2env.rb`. It builds the CLI and C library,
installs bash/zsh helper files under `pkgshare`, and includes a formula test for
the `shell-env` output used by shell functions. `scripts/publish-homebrew.sh`
prints or runs the local `brew install --build-from-source`, `brew test`, and
`brew audit --strict --new --online` checks.

JVM clients share the Java JNI bridge. Kotlin, Scala, Groovy, and Clojure expose
idiomatic wrappers over `com.oresoftware.flags2env.Flags2Env` and are packaged
for Maven-compatible registries. Java uses Sonatype's Central Publishing Maven
plugin. Gradle and Clojure facades default to Sonatype's Central Portal OSSRH
Staging API compatibility endpoint and then call
`scripts/publish-central-ossrh-compat.sh` to hand the deployment to Central
Portal. Set `CENTRAL_NAMESPACE` plus `CENTRAL_BEARER_TOKEN`, or
`CENTRAL_TOKEN_USERNAME` and `CENTRAL_TOKEN_PASSWORD`, for those release paths.
Scala uses `sbt-sonatype` with `sonatypeCentralHost`. The setup follows
Sonatype's Central Portal Maven plugin docs and OSSRH Staging API compatibility
docs; Sonatype's Gradle docs currently note that there is no official Gradle
plugin for the Central Publishing Portal.
