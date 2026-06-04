#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
status=0

require_path() {
  path="$1"
  if [ ! -e "$ROOT_DIR/$path" ]; then
    printf 'missing: %s\n' "$path" >&2
    status=1
  fi
}

require_contains() {
  path="$1"
  pattern="$2"
  require_path "$path"
  if [ -e "$ROOT_DIR/$path" ] && ! grep -Eq "$pattern" "$ROOT_DIR/$path"; then
    printf 'missing pattern in %s: %s\n' "$path" "$pattern" >&2
    status=1
  fi
}

forbid_contains() {
  path="$1"
  pattern="$2"
  require_path "$path"
  if [ -e "$ROOT_DIR/$path" ] && grep -Eq "$pattern" "$ROOT_DIR/$path"; then
    printf 'forbidden pattern in %s: %s\n' "$path" "$pattern" >&2
    status=1
  fi
}

require_same_file() {
  left="$1"
  right="$2"
  require_path "$left"
  require_path "$right"
  if [ -e "$ROOT_DIR/$left" ] && [ -e "$ROOT_DIR/$right" ] &&
     ! cmp -s "$ROOT_DIR/$left" "$ROOT_DIR/$right"; then
    printf 'file copies differ: %s %s\n' "$left" "$right" >&2
    status=1
  fi
}

native_library_name() {
  case "$(uname -s)" in
    Darwin)
      printf 'libflags2env.dylib'
      ;;
    MINGW*|MSYS*|CYGWIN*)
      printf 'libflags2env.dll'
      ;;
    *)
      printf 'libflags2env.so'
      ;;
  esac
}

audit_rendered_js_client() {
  runtime="$1"
  tmp_dir="${TMPDIR:-/tmp}/flags2env-render-audit-$runtime-$$"
  rm -rf "$tmp_dir"
  if ! node "$ROOT_DIR/scripts/render-client.mjs" "$runtime" "$tmp_dir" >/dev/null 2>&1; then
    printf 'render failed for JS client: %s\n' "$runtime" >&2
    status=1
    return
  fi

  for path in "$@"; do
    if [ "$path" = "$runtime" ]; then
      continue
    fi
    if [ ! -e "$tmp_dir/$path" ]; then
      printf 'rendered %s package is missing: %s\n' "$runtime" "$path" >&2
      status=1
    fi
  done

  if [ "$runtime" = "nodejs" ] &&
     grep -Eq '\.\./\.\./src' "$tmp_dir/binding.gyp"; then
    printf 'rendered nodejs binding.gyp points outside the package\n' >&2
    status=1
  fi
  rm -rf "$tmp_dir"
}

audit_npm_pack_client() {
  client="$1"
  required="$2"
  forbidden="$3"
  tmp_cache="${TMPDIR:-/tmp}/flags2env-npm-audit-$client-$$"
  output="$(
    cd "$ROOT_DIR/clients/$client" &&
      npm_config_cache="$tmp_cache" npm pack --dry-run --json 2>/dev/null
  )" || {
    printf 'npm pack dry-run failed for client: %s\n' "$client" >&2
    status=1
    rm -rf "$tmp_cache"
    return
  }

  for path in $required; do
    if ! printf '%s\n' "$output" | grep -Fq "\"path\": \"$path\""; then
      printf 'npm package for %s is missing: %s\n' "$client" "$path" >&2
      status=1
    fi
  done
  for path in $forbidden; do
    if printf '%s\n' "$output" | grep -Fq "\"path\": \"$path\""; then
      printf 'npm package for %s includes forbidden file: %s\n' "$client" "$path" >&2
      status=1
    fi
  done
  rm -rf "$tmp_cache"
}

require_client() {
  client="$1"
  require_path "clients/$client"
  require_path "clients/$client/publish.sh"
  if [ -L "$ROOT_DIR/clients/$client/publish.sh" ]; then
    target="$(readlink "$ROOT_DIR/clients/$client/publish.sh" || true)"
    if [ "$target" != "../../scripts/publish-client.sh" ]; then
      printf 'unexpected publish wrapper target for clients/%s/publish.sh: %s\n' "$client" "$target" >&2
      status=1
    fi
  elif [ -e "$ROOT_DIR/clients/$client/publish.sh" ] &&
       ! grep -Eq 'publish-client\.sh' "$ROOT_DIR/clients/$client/publish.sh"; then
    printf 'publish wrapper does not delegate for client: %s\n' "$client" >&2
    status=1
  fi
  if ! grep -Eq "^  $client\\)|\\|$client\\)|$client\\|" "$ROOT_DIR/scripts/publish-client.sh"; then
    printf 'missing publish dispatcher case for client: %s\n' "$client" >&2
    status=1
  fi
  if [ -e "$ROOT_DIR/clients/$client/publish.sh" ] &&
     ! "$ROOT_DIR/clients/$client/publish.sh" --dry-run >/dev/null 2>&1; then
    printf 'publish dry-run failed for client: %s\n' "$client" >&2
    status=1
  fi
}

for client in \
  nodejs bun deno python java kotlin scala groovy clojure rust golang c cpp \
  bash zsh \
  csharp fsharp php ruby dart swift elixir erlang gleam haskell ocaml \
  reasonml perl lua nim r matlab julia fortran zig crystal solidity
do
  require_client "$client"
done

for path in \
  .npmignore \
  Package.swift \
  package.json \
  packaging/homebrew/README.md \
  packaging/homebrew/Formula/flags2env.rb \
  scripts/audit-npm-package.mjs \
  scripts/audit-release-matrix.mjs \
  scripts/docker-check-new-clients.sh \
  scripts/publish-central-ossrh-compat.sh \
  scripts/publish-homebrew.sh \
  clients/bash/flags2env.bash \
  clients/bash/test.bash \
  clients/zsh/flags2env.zsh \
  clients/zsh/test.zsh \
  clients/python/MANIFEST.in \
  clients/python/pyproject.toml \
  clients/golang/parser.c \
  clients/golang/parser.h \
  clients/rust/Cargo.toml \
  clients/ruby/flags2env.gemspec \
  clients/php/composer.json \
  clients/java/pom.xml \
  clients/kotlin/build.gradle.kts \
  clients/groovy/build.gradle \
  clients/scala/build.sbt \
  clients/scala/project/plugins.sbt \
  clients/csharp/Flags2Env.nuspec \
  clients/csharp/Flags2Env.csproj \
  clients/fsharp/Flags2Env.FSharp.nuspec \
  clients/fsharp/Flags2Env.FSharp.fsproj \
  clients/dart/CHANGELOG.md \
  clients/dart/LICENSE \
  clients/dart/README.md \
  clients/dart/pubspec.yaml \
  clients/dart/.pubignore \
  clients/swift/Package.swift \
  clients/elixir/mix.exs \
  clients/erlang/rebar.config \
  clients/gleam/gleam.toml \
  clients/gleam/src/flags2env.gleam \
  clients/gleam/src/flags2env_native.erl \
  clients/haskell/flags2env.cabal \
  clients/ocaml/flags2env.opam \
  clients/reasonml/flags2env.opam \
  clients/perl/MANIFEST.SKIP \
  clients/lua/flags2env-dev-1.rockspec \
  clients/nim/flags2env.nimble \
  clients/r/.Rbuildignore \
  clients/r/DESCRIPTION \
  clients/julia/Project.toml \
  clients/solidity/package.json \
  .github/workflows/client-packaging.yml \
  .github/workflows/cli-flags-audit.yml
do
  require_path "$path"
done

require_contains .npmignore '^!clients/nodejs/'
require_contains Package.swift 'path: "clients/swift"'
require_contains Package.swift 'exclude: \["Dockerfile", "Package\.swift", "test\.swift", "publish\.sh"\]'
require_contains Makefile '@rpath/lib\$\(LIB_NAME\)\.dylib'
require_contains package.json '"files"'
require_contains package.json '"pack:audit"'
require_contains package.json '"release:audit"'
require_contains scripts/audit-npm-package.mjs 'non-JS clients'
require_contains scripts/audit-release-matrix.mjs 'release matrix audit passed'
require_contains scripts/audit-release-matrix.mjs 'requiredClients'
require_contains scripts/audit-release-matrix.mjs 'expectedRepositories'
require_contains scripts/audit-release-matrix.mjs 'packageControls'
require_contains scripts/audit-release-matrix.mjs 'missing package-control assertions'
require_contains scripts/publish-central-ossrh-compat.sh 'manual/upload/defaultRepository'
require_contains scripts/publish-central-ossrh-compat.sh 'CENTRAL_NAMESPACE'
require_contains scripts/publish-central-ossrh-compat.sh 'ossrh-staging-api\.central\.sonatype\.com'
require_contains scripts/docker-check-new-clients.sh 'clojure:temurin-21-tools-deps'
require_contains scripts/docker-check-new-clients.sh 'sbtscala/scala-sbt'
require_contains scripts/docker-check-new-clients.sh 'zig build test'
require_contains scripts/docker-check-new-clients.sh 'npm test && npm pack'
require_contains packaging/homebrew/Formula/flags2env.rb 'class Flags2env < Formula'
require_contains packaging/homebrew/Formula/flags2env.rb 'shell-env'
require_contains packaging/homebrew/README.md 'scripts/publish-homebrew\.sh --release'
require_contains scripts/publish-homebrew.sh 'brew audit --strict --new --online'
require_contains scripts/publish-homebrew.sh 'FLAGS2ENV_HOMEBREW_AUDIT_TARGET'
require_contains scripts/publish-homebrew.sh 'rev-parse "v\$VERSION'
require_contains src/main.c 'shell-env'
require_contains clients/bash/flags2env.bash 'flags2env_apply'
require_contains clients/zsh/flags2env.zsh 'flags2env_apply'
require_contains clients/python/MANIFEST.in '^include lib\.py$'
require_contains clients/rust/Cargo.toml '^include = \['
require_contains clients/golang/lib.go '#cgo CFLAGS: -I\.'
require_contains clients/golang/lib.go '#include "parser\.h"'
forbid_contains clients/golang/lib.go '\.\./\.\./src|\.\./\.\./build|LDFLAGS'
require_same_file src/parser.c clients/golang/parser.c
require_same_file src/parser.h clients/golang/parser.h
require_contains clients/ruby/flags2env.gemspec 'spec\.files'
forbid_contains clients/ruby/flags2env.gemspec '"test\.rb"'
require_contains clients/php/composer.json '"archive"'
require_contains clients/java/pom.xml 'central-publishing-maven-plugin'
require_contains clients/java/pom.xml '<publishingServerId>'
require_contains clients/java/pom.xml '<excludes>'
require_contains clients/java/pom.xml '<include>parser\.c</include>'
require_contains clients/java/pom.xml '<include>parser\.h</include>'
forbid_contains clients/java/pom.xml 'nexus-staging-maven-plugin'
require_contains clients/kotlin/build.gradle.kts 'maven-publish'
require_contains clients/kotlin/build.gradle.kts 'java-library'
require_contains clients/kotlin/build.gradle.kts 'artifactId = "flags2env-kotlin"'
require_contains clients/kotlin/build.gradle.kts 'exclude\("publish\.sh"\)'
require_contains clients/kotlin/build.gradle.kts 'ossrh-staging-api\.central\.sonatype\.com'
require_contains clients/groovy/build.gradle "maven-publish"
require_contains clients/groovy/build.gradle "java-library"
require_contains clients/groovy/build.gradle "artifactId = 'flags2env-groovy'"
require_contains clients/groovy/build.gradle "exclude 'publish\\.sh'"
require_contains clients/groovy/build.gradle 'ossrh-staging-api\.central\.sonatype\.com'
require_contains clients/scala/build.sbt 'sonatype'
require_contains clients/scala/build.sbt 'sonatypeCentralHost'
require_contains clients/scala/build.sbt 'flags2env-scala'
require_contains clients/clojure/build.clj 'sign-and-deploy-file'
require_contains clients/clojure/build.clj 'CENTRAL_OSSRH_DEPLOY_URL'
require_contains clients/clojure/build.clj 'flags2env-clojure'
require_contains clients/csharp/Flags2Env.nuspec '<files>'
require_contains clients/csharp/Flags2Env.nuspec 'exclude='
require_contains clients/csharp/Flags2Env.csproj 'Pack="true"'
require_contains clients/csharp/Flags2Env.csproj 'PackagePath="native/src/"'
require_contains clients/csharp/Flags2Env.csproj 'PackagePath="native/include/"'
require_contains clients/fsharp/Flags2Env.FSharp.nuspec '<files>'
require_contains clients/fsharp/Flags2Env.FSharp.nuspec 'exclude='
require_contains clients/fsharp/Flags2Env.FSharp.fsproj 'Pack="true"'
require_contains clients/fsharp/Flags2Env.FSharp.fsproj 'PackagePath="native/src/"'
require_contains clients/fsharp/Flags2Env.FSharp.fsproj 'PackagePath="native/include/"'
require_contains clients/dart/pubspec.yaml '^description:'
require_contains clients/dart/pubspec.yaml '^repository:'
require_contains clients/dart/.pubignore '^Dockerfile$'
require_contains clients/swift/Package.swift 'exclude:'
require_contains clients/elixir/mix.exs 'files:'
require_contains clients/erlang/rebar.config '\{files,'
require_contains clients/haskell/flags2env.cabal '^extra-source-files:'
require_contains clients/ocaml/flags2env.opam '^build:'
require_contains clients/reasonml/flags2env.opam '^build:'
require_contains clients/perl/MANIFEST.SKIP '^\^blib/'
require_contains clients/lua/flags2env-dev-1.rockspec '^build ='
require_contains clients/nim/flags2env.nimble '^installFiles'
require_contains clients/r/.Rbuildignore '\^Dockerfile\$'
require_contains clients/julia/Project.toml '^name = "Flags2Env"'
require_contains clients/solidity/package.json '"files"'
require_contains clients/solidity/package.json '"test"'
require_contains clients/solidity/package.json '"solc"'
require_contains clients/deno/deno.json '"native"'
require_contains scripts/render-client.mjs 'src/parser\.c'
require_contains scripts/render-client.mjs 'native'
require_contains scripts/publish-client.sh 'cp src/parser\.c src/parser\.h dist/r/src/'
require_contains scripts/publish-client.sh 'npm publish --access public'
require_contains scripts/publish-client.sh 'node scripts/render-client\.mjs deno dist/deno'
require_contains scripts/publish-client.sh 'twine upload'
require_contains scripts/publish-client.sh 'clients/golang/v\$'
require_contains scripts/publish-client.sh 'git tag "\$\{PACKAGE_VERSION:\?set PACKAGE_VERSION\}"'
require_contains scripts/publish-client.sh 'mvn -P release deploy'
require_contains scripts/publish-client.sh 'sbt publishSigned sonatypeBundleRelease'
require_contains scripts/publish-client.sh 'publish-central-ossrh-compat\.sh'
require_contains scripts/publish-client.sh 'dotnet nuget push'
require_contains scripts/publish-client.sh 'gem push'
require_contains scripts/publish-client.sh 'dart pub publish'
require_contains scripts/publish-client.sh 'mix hex.publish'
require_contains scripts/publish-client.sh 'rebar3 hex publish'
require_contains scripts/publish-client.sh 'cabal upload'
require_contains scripts/publish-client.sh 'opam publish submit'
require_contains scripts/publish-client.sh 'cpan-upload'
require_contains scripts/publish-client.sh 'luarocks upload'
require_contains scripts/publish-client.sh 'nimble publish'
require_contains scripts/publish-client.sh 'submit_cran'
require_contains scripts/publish-client.sh 'Registrator'
require_contains scripts/docker-check-new-clients.sh 'dotnet run'
require_contains scripts/docker-check-new-clients.sh 'FLAGS2ENV_FIXTURE'
require_contains README.md 'undefined dynamic_lookup'
require_contains .github/workflows/client-packaging.yml 'scripts/audit-client-packaging\.sh'
require_contains .github/workflows/client-packaging.yml 'npm run release:audit'
require_contains .github/workflows/client-packaging.yml 'scripts/docker-check-new-clients\.sh'
require_contains .github/workflows/client-packaging.yml 'full_docker_checks'
require_contains .github/workflows/client-packaging.yml 'tests/run\.sh'
require_contains .github/workflows/cli-flags-audit.yml 'scripts/audit-changed-cli-flags\.sh'
require_contains .github/workflows/cli-flags-audit.yml '\*\*/\.cli-flags\.toml'
require_contains .github/workflows/cli-flags-audit.yml '\*\*/\.env'
require_contains scripts/audit-changed-cli-flags.sh 'audit env'

for path in \
  clients/cpp/test.cpp \
  clients/scala/src/main/scala/com/oresoftware/flags2env/Flags2Env.scala \
  clients/groovy/src/main/groovy/com/oresoftware/flags2env/Flags2Env.groovy \
  clients/kotlin/src/main/kotlin/com/oresoftware/flags2env/Flags2Env.kt \
  clients/clojure/src/com/oresoftware/flags2env.clj \
  clients/csharp/Flags2EnvTest.cs \
  clients/fsharp/Flags2EnvTest.fs \
  clients/r/R/flags2env.R \
  clients/fortran/src/flags2env.f90 \
  clients/fortran/test.f90 \
  clients/zig/src/flags2env.zig \
  clients/zig/test.zig \
  clients/crystal/src/flags2env.cr \
  clients/solidity/contracts/Flags2Env.sol \
  clients/perl/test.pl \
  clients/lua/test.lua \
  clients/nim/test.nim \
  clients/crystal/test.cr \
  clients/julia/test/runtests.jl \
  clients/haskell/test.hs \
  clients/ocaml/test.ml \
  clients/reasonml/src/Test.re
do
  require_path "$path"
done

native_lib="$(native_library_name)"
audit_rendered_js_client nodejs package.json binding.gyp addon.c src/parser.c src/parser.h lib.mjs lib.cjs lib.ts cli.mjs
audit_rendered_js_client bun package.json "native/$native_lib" lib.mjs lib.cjs lib.ts
audit_rendered_js_client deno deno.json "native/$native_lib" mod.ts lib.ts
audit_npm_pack_client solidity "contracts/Flags2Env.sol package.json" "test.js test.ts Dockerfile"

if [ "$status" -eq 0 ]; then
  printf 'client packaging audit passed\n'
fi
exit "$status"
