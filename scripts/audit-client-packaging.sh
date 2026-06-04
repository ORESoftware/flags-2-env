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

require_client() {
  client="$1"
  require_path "clients/$client"
  require_path "clients/$client/publish.sh"
}

for client in \
  nodejs bun deno python java kotlin scala groovy clojure rust golang c cpp \
  csharp fsharp php ruby dart swift elixir erlang gleam haskell ocaml \
  reasonml perl lua nim r matlab julia fortran zig crystal solidity
do
  require_client "$client"
done

for path in \
  .npmignore \
  package.json \
  clients/python/MANIFEST.in \
  clients/python/pyproject.toml \
  clients/rust/Cargo.toml \
  clients/ruby/flags2env.gemspec \
  clients/php/composer.json \
  clients/java/pom.xml \
  clients/kotlin/build.gradle.kts \
  clients/groovy/build.gradle \
  clients/scala/build.sbt \
  clients/scala/project/plugins.sbt \
  clients/csharp/Flags2Env.nuspec \
  clients/fsharp/Flags2Env.FSharp.nuspec \
  clients/dart/.pubignore \
  clients/swift/Package.swift \
  clients/elixir/mix.exs \
  clients/erlang/rebar.config \
  clients/gleam/gleam.toml \
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
  .github/workflows/cli-flags-audit.yml
do
  require_path "$path"
done

require_contains .npmignore '^!clients/nodejs/'
require_contains package.json '"files"'
require_contains clients/python/MANIFEST.in '^include lib\.py$'
require_contains clients/rust/Cargo.toml '^include = \['
require_contains clients/ruby/flags2env.gemspec 'spec\.files'
require_contains clients/php/composer.json '"archive"'
require_contains clients/java/pom.xml 'central-publishing-maven-plugin'
require_contains clients/java/pom.xml '<publishingServerId>'
forbid_contains clients/java/pom.xml 'nexus-staging-maven-plugin'
require_contains clients/kotlin/build.gradle.kts 'maven-publish'
require_contains clients/kotlin/build.gradle.kts 'java-library'
require_contains clients/groovy/build.gradle "maven-publish"
require_contains clients/groovy/build.gradle "java-library"
require_contains clients/scala/build.sbt 'sonatype'
require_contains clients/clojure/build.clj 'sign-and-deploy-file'
require_contains clients/clojure/build.clj 'SONATYPE_RELEASE_URL'
require_contains clients/csharp/Flags2Env.nuspec '<files>'
require_contains clients/fsharp/Flags2Env.FSharp.nuspec '<files>'
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
require_contains scripts/publish-client.sh 'cp src/parser\.c src/parser\.h dist/r/src/'
require_contains scripts/publish-client.sh 'npm publish --access public'
require_contains scripts/publish-client.sh 'twine upload'
require_contains scripts/publish-client.sh 'mvn -P release deploy'
require_contains scripts/publish-client.sh 'sbt publishSigned sonatypeBundleRelease'
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
require_contains .github/workflows/cli-flags-audit.yml 'scripts/audit-changed-cli-flags\.sh'
require_contains .github/workflows/cli-flags-audit.yml '\*\*/\.cli-flags\.toml'

for path in \
  clients/cpp/test.cpp \
  clients/csharp/Flags2EnvTest.cs \
  clients/fsharp/Flags2EnvTest.fs \
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

if [ "$status" -eq 0 ]; then
  printf 'client packaging audit passed\n'
fi
exit "$status"
