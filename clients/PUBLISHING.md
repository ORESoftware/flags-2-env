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

SwiftPM expects a `Package.swift` manifest in the repository root and a full
semantic-version tag such as `0.1.0`, so the root manifest points at
`clients/swift` while the Swift publish command uses an unprefixed SemVer tag.

Docker-backed verification for the newer client scaffolds lives in
`scripts/docker-check-new-clients.sh`. Run the default set for practical local
coverage, or pass `--full` in CI to include heavier Haskell, OCaml/opam, Julia,
Scala, Kotlin, Groovy, and JVM facade checks. The GitHub Actions client
packaging workflow runs the default Docker set automatically and exposes a
manual `full_docker_checks` input for the heavyweight set.

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
rules, LuaRocks modules, Nimble install files, R build ignores, and Homebrew
shell helper installation. The package-control, release matrix, and npm
package-content audits run in `.github/workflows/client-packaging.yml`
alongside the core shell integration tests whenever client, packaging, script,
source, or test files change.

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
