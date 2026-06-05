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

require_absent() {
  path="$1"
  if [ -e "$ROOT_DIR/$path" ]; then
    printf 'unexpected file: %s\n' "$path" >&2
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

audit_perl_manifest() {
  tmp_dir="${TMPDIR:-/tmp}/flags2env-perl-manifest-audit-$$"
  rm -rf "$tmp_dir"
  mkdir -p "$tmp_dir"
  cp -R "$ROOT_DIR/clients/perl/." "$tmp_dir/"
  if ! (
    cd "$tmp_dir" &&
      perl Makefile.PL >/dev/null 2>&1 &&
      make manifest >/dev/null 2>&1
  ); then
    printf 'Perl CPAN manifest generation failed\n' >&2
    status=1
    rm -rf "$tmp_dir"
    return
  fi
  for path in publish.sh MYMETA.json MYMETA.yml; do
    if grep -Fxq "$path" "$tmp_dir/MANIFEST"; then
      printf 'Perl CPAN manifest includes forbidden file: %s\n' "$path" >&2
      status=1
    fi
  done
  for path in Makefile.PL lib/Flags2Env.pm; do
    if ! grep -Fxq "$path" "$tmp_dir/MANIFEST"; then
      printf 'Perl CPAN manifest is missing: %s\n' "$path" >&2
      status=1
    fi
  done
  rm -rf "$tmp_dir"
}

audit_r_staging() {
  tmp_dir="${TMPDIR:-/tmp}/flags2env-r-staging-audit-$$"
  rm -rf "$tmp_dir"
  mkdir -p "$tmp_dir/r"
  cp -R "$ROOT_DIR/clients/r/." "$tmp_dir/r/"
  cp "$ROOT_DIR/src/parser.c" "$ROOT_DIR/src/parser.h" "$tmp_dir/r/src/"
  for path in src/flags2env_r.c src/parser.c src/parser.h src/Makevars DESCRIPTION NAMESPACE tests/smoke.R; do
    if [ ! -e "$tmp_dir/r/$path" ]; then
      printf 'staged R package is missing: %s\n' "$path" >&2
      status=1
    fi
  done
  if grep -Eq '\.\./\.\./\.\./src/parser\.h' "$tmp_dir/r/src/flags2env_r.c"; then
    printf 'staged R package still points to repository parser header\n' >&2
    status=1
  fi
  rm -rf "$tmp_dir"
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
  clients/cpp/native/parser.c \
  clients/cpp/native/parser.h \
  clients/python/MANIFEST.in \
  clients/python/pyproject.toml \
  clients/golang/parser.c \
  clients/golang/parser.h \
  clients/rust/Cargo.toml \
  clients/rust/Dockerfile \
  clients/rust/native/parser.c \
  clients/rust/native/parser.h \
  clients/ruby/flags2env.gemspec \
  clients/php/composer.json \
  clients/java/pom.xml \
  clients/java/native/parser.c \
  clients/java/native/parser.h \
  clients/kotlin/build.gradle.kts \
  clients/groovy/build.gradle \
  clients/scala/build.sbt \
  clients/scala/project/plugins.sbt \
  clients/csharp/Flags2Env.nuspec \
  clients/csharp/Flags2Env.csproj \
  clients/csharp/native/parser.c \
  clients/csharp/native/parser.h \
  clients/fsharp/Flags2Env.FSharp.nuspec \
  clients/fsharp/Flags2Env.FSharp.fsproj \
  clients/fsharp/native/parser.c \
  clients/fsharp/native/parser.h \
  clients/dart/CHANGELOG.md \
  clients/dart/LICENSE \
  clients/dart/README.md \
  clients/dart/pubspec.yaml \
  clients/dart/.pubignore \
  clients/swift/Package.swift \
  clients/elixir/README.md \
  clients/elixir/mix.exs \
  clients/elixir/native/flags2env.erl \
  clients/elixir/native/flags2env_nif.c \
  clients/elixir/native/parser.c \
  clients/elixir/native/parser.h \
  clients/erlang/rebar.config \
  clients/erlang/parser.c \
  clients/erlang/parser.h \
  clients/gleam/gleam.toml \
  clients/gleam/src/flags2env.gleam \
  clients/gleam/src/flags2env_native.erl \
  clients/haskell/flags2env.cabal \
  clients/ocaml/dune \
  clients/ocaml/flags2env.opam \
  clients/reasonml/flags2env-reason.opam \
  clients/reasonml/src/dune \
  clients/lua/flags2env-0.1.0-1.rockspec \
  clients/perl/MANIFEST.SKIP \
  clients/lua/flags2env-dev-1.rockspec \
  clients/nim/flags2env.nimble \
  clients/r/.Rbuildignore \
  clients/r/DESCRIPTION \
  clients/r/tests/smoke.R \
  clients/matlab/+flags2env/defaultHeaderPath.m \
  clients/matlab/native/parser.c \
  clients/matlab/native/parser.h \
  clients/julia/LICENSE \
  clients/julia/Project.toml \
  clients/julia/README.md \
  clients/julia/REGISTRATION.md \
  clients/solidity/package.json \
  clients/zig/native/parser.c \
  clients/zig/native/parser.h \
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
require_contains scripts/docker-check-new-clients.sh 'cabal test --extra-lib-dirs=/work/build'
require_contains scripts/docker-check-new-clients.sh 'clients/reasonml/flags2env-reason\.opam'
require_contains scripts/docker-check-new-clients.sh 'npm test && npm pack'
require_contains packaging/homebrew/Formula/flags2env.rb 'class Flags2env < Formula'
require_contains packaging/homebrew/Formula/flags2env.rb 'shell-env'
require_contains packaging/homebrew/README.md 'scripts/publish-homebrew\.sh --release'
require_contains clients/PUBLISHING.md '@JuliaRegistrator register subdir=clients/julia'
require_contains clients/PUBLISHING.md 'clients/zig/native'
require_contains scripts/publish-homebrew.sh 'brew audit --strict --new --online'
require_contains scripts/publish-homebrew.sh 'FLAGS2ENV_HOMEBREW_AUDIT_TARGET'
require_contains scripts/publish-homebrew.sh 'rev-parse "v\$VERSION'
require_contains src/main.c 'shell-env'
require_contains clients/bash/flags2env.bash 'flags2env_apply'
require_contains clients/zsh/flags2env.zsh 'flags2env_apply'
require_contains clients/python/MANIFEST.in '^include lib\.py$'
require_contains clients/rust/Cargo.toml '^include = \['
require_contains clients/rust/Cargo.toml '"native/\*\*"'
require_contains clients/rust/Cargo.toml '"tests/\*\*"'
require_contains clients/rust/Dockerfile 'COPY clients/rust ./clients/rust'
forbid_contains clients/rust/Dockerfile 'COPY src|COPY tests|src/parser\.c|tests/fixtures|make all|LD_LIBRARY_PATH'
forbid_contains clients/rust/tests/smoke.rs '\.\./\.\./build|tests/fixtures|\.\./\.\./tests'
require_contains clients/rust/tests/smoke.rs 'native/parser\.c'
require_same_file src/parser.c clients/rust/native/parser.c
require_same_file src/parser.h clients/rust/native/parser.h
require_contains clients/cpp/CMakeLists.txt 'native/parser\.c'
require_contains clients/cpp/CMakeLists.txt 'target_include_directories\(flags2env_native PUBLIC native\)'
require_contains clients/cpp/CMakeLists.txt 'target_include_directories\(flags2env_cpp INTERFACE include native\)'
require_contains clients/cpp/CMakeLists.txt 'add_test\(NAME flags2env_cpp_smoke'
forbid_contains clients/cpp/CMakeLists.txt '\.\./\.\./src'
require_same_file src/parser.c clients/cpp/native/parser.c
require_same_file src/parser.h clients/cpp/native/parser.h
require_contains clients/golang/lib.go '#cgo CFLAGS: -I\.'
require_contains clients/golang/lib.go '#include "parser\.h"'
forbid_contains clients/golang/lib.go '\.\./\.\./src|\.\./\.\./build|LDFLAGS'
require_same_file src/parser.c clients/golang/parser.c
require_same_file src/parser.h clients/golang/parser.h
require_contains clients/ruby/flags2env.gemspec 'spec\.files'
forbid_contains clients/ruby/flags2env.gemspec '"test\.rb"'
require_contains clients/php/composer.json '"archive"'
require_contains clients/php/composer.json '"\/publish\.sh"'
require_contains clients/java/pom.xml 'central-publishing-maven-plugin'
require_contains clients/java/pom.xml '<publishingServerId>'
require_contains clients/java/pom.xml '<excludes>'
require_contains clients/java/pom.xml '<directory>native</directory>'
require_contains clients/java/pom.xml '<include>\*\*/\*\.c</include>'
require_contains clients/java/pom.xml '<include>\*\*/\*\.h</include>'
forbid_contains clients/java/pom.xml '\.\./\.\./src'
forbid_contains clients/java/pom.xml 'nexus-staging-maven-plugin'
require_contains clients/java/native/flags2env_jni.c '#include "parser\.h"'
forbid_contains clients/java/native/flags2env_jni.c '\.\./\.\./\.\./src/parser\.h'
require_contains clients/java/Dockerfile 'clients/java/native/parser\.c'
forbid_contains clients/java/Dockerfile 'COPY src|COPY tests|src/parser\.c'
require_same_file src/parser.c clients/java/native/parser.c
require_same_file src/parser.h clients/java/native/parser.h
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
require_contains clients/csharp/Flags2Env.nuspec 'native/parser\.c'
require_contains clients/csharp/Flags2Env.nuspec 'native/parser\.h'
forbid_contains clients/csharp/Flags2Env.nuspec '\.\./\.\./src|\.\./\.\./clients'
require_contains clients/csharp/Flags2Env.csproj 'Pack="true"'
require_contains clients/csharp/Flags2Env.csproj 'Include="native/parser\.c"'
require_contains clients/csharp/Flags2Env.csproj 'Include="native/parser\.h"'
require_contains clients/csharp/Flags2Env.csproj 'PackagePath="native/"'
forbid_contains clients/csharp/Flags2Env.csproj '\.\./\.\./src'
require_contains clients/csharp/Flags2EnvTest.cs 'clients/csharp/native/parser\.c'
forbid_contains clients/csharp/Flags2EnvTest.cs 'build/libflags2env|tests/fixtures|\.\./\.\./tests'
require_same_file src/parser.c clients/csharp/native/parser.c
require_same_file src/parser.h clients/csharp/native/parser.h
require_contains clients/fsharp/Flags2Env.FSharp.nuspec '<files>'
require_contains clients/fsharp/Flags2Env.FSharp.nuspec 'exclude='
require_contains clients/fsharp/Flags2Env.FSharp.nuspec 'native/parser\.c'
require_contains clients/fsharp/Flags2Env.FSharp.nuspec 'native/parser\.h'
forbid_contains clients/fsharp/Flags2Env.FSharp.nuspec '\.\./\.\./src|\.\./\.\./clients'
require_contains clients/fsharp/Flags2Env.FSharp.fsproj 'Pack="true"'
require_contains clients/fsharp/Flags2Env.FSharp.fsproj 'Include="native/parser\.c"'
require_contains clients/fsharp/Flags2Env.FSharp.fsproj 'Include="native/parser\.h"'
require_contains clients/fsharp/Flags2Env.FSharp.fsproj 'PackagePath="native/"'
forbid_contains clients/fsharp/Flags2Env.FSharp.fsproj '\.\./\.\./src'
require_contains clients/fsharp/Flags2EnvTest.fs 'clients/fsharp/native/parser\.c'
require_contains clients/fsharp/Flags2EnvTest.fs 'SetDllImportResolver'
forbid_contains clients/fsharp/Flags2EnvTest.fs 'build/libflags2env|tests/fixtures|\.\./\.\./tests'
require_same_file src/parser.c clients/fsharp/native/parser.c
require_same_file src/parser.h clients/fsharp/native/parser.h
require_contains clients/dart/pubspec.yaml '^description:'
require_contains clients/dart/pubspec.yaml '^repository:'
require_contains clients/dart/.pubignore '^Dockerfile$'
require_contains clients/dart/.pubignore '^\.dart_tool/$'
require_contains clients/dart/.pubignore '^pubspec\.lock$'
require_contains clients/dart/.pubignore '^test\.dart$'
require_contains clients/dart/.pubignore '^publish\.sh$'
require_contains clients/swift/Package.swift 'exclude:'
require_contains clients/elixir/mix.exs 'files:'
require_contains clients/elixir/mix.exs 'name: "flags2env_elixir"'
require_contains clients/elixir/mix.exs 'erlc_paths: \["native"\]'
require_contains clients/elixir/mix.exs '"native/flags2env\.erl"'
require_contains clients/elixir/mix.exs '"native/flags2env_nif\.c"'
require_contains clients/elixir/mix.exs '"native/parser\.c"'
require_contains clients/elixir/mix.exs '"native/parser\.h"'
require_contains clients/elixir/README.md 'flags2env_elixir'
require_contains clients/elixir/Dockerfile 'clients/elixir/native/parser\.c'
forbid_contains clients/elixir/Dockerfile 'COPY src|COPY tests|src/parser\.c|tests/fixtures|clients/erlang'
forbid_contains clients/elixir/test.exs 'tests/fixtures|\.\./\.\./tests|\.\./\.cli-flags\.toml'
require_same_file clients/erlang/flags2env.erl clients/elixir/native/flags2env.erl
require_same_file clients/erlang/flags2env_nif.c clients/elixir/native/flags2env_nif.c
require_same_file src/parser.c clients/elixir/native/parser.c
require_same_file src/parser.h clients/elixir/native/parser.h
require_contains clients/erlang/rebar.config '\{files,'
require_contains clients/erlang/rebar.config '"parser\.c"'
require_contains clients/erlang/rebar.config '"parser\.h"'
require_contains clients/erlang/flags2env_nif.c '#include "parser\.h"'
forbid_contains clients/erlang/flags2env_nif.c '\.\./\.\./src/parser\.h'
require_contains clients/erlang/Dockerfile 'clients/erlang/parser\.c'
forbid_contains clients/erlang/Dockerfile 'COPY src|COPY tests|src/parser\.c|tests/fixtures'
require_same_file src/parser.c clients/erlang/parser.c
require_same_file src/parser.h clients/erlang/parser.h
require_contains clients/gleam/Dockerfile 'clients/erlang/parser\.c'
forbid_contains clients/gleam/Dockerfile 'COPY src|COPY tests|src/parser\.c|tests/fixtures'
forbid_contains clients/gleam/test.gleam '/repo/tests|tests/fixtures'
require_contains clients/haskell/flags2env.cabal '^extra-source-files:'
require_contains clients/haskell/flags2env.cabal '^test-suite flags2env-smoke$'
require_contains clients/haskell/flags2env.cabal '^  main-is: test\.hs$'
require_contains clients/ocaml/dune '^\(test'
require_contains clients/ocaml/flags2env.opam '^build:'
require_contains clients/ocaml/flags2env.opam '\{with-test\}'
require_contains clients/reasonml/dune-project '\(name flags2env_reason\)'
require_contains clients/reasonml/dune-project '\(name flags2env-reason\)'
require_contains clients/reasonml/flags2env-reason.opam '^build:'
require_contains clients/reasonml/flags2env-reason.opam '"reason"'
require_contains clients/reasonml/flags2env-reason.opam '"flags2env"'
require_contains clients/reasonml/flags2env-reason.opam '\{with-test\}'
require_absent clients/reasonml/flags2env.opam
require_contains clients/reasonml/src/dune '^\(test'
require_contains clients/perl/MANIFEST.SKIP '^\^blib/'
require_contains clients/perl/MANIFEST.SKIP '^\^publish\\\.sh\$'
require_contains clients/perl/MANIFEST.SKIP '^\^MYMETA\\\.'
require_contains clients/lua/flags2env-dev-1.rockspec '^build ='
require_contains clients/lua/flags2env-dev-1.rockspec 'clients/lua/flags2env\.lua'
require_contains clients/lua/flags2env-0.1.0-1.rockspec '^version = "0\.1\.0-1"'
require_contains clients/lua/flags2env-0.1.0-1.rockspec 'tag = "v0\.1\.0"'
require_contains clients/lua/flags2env-0.1.0-1.rockspec 'clients/lua/flags2env\.lua'
require_contains clients/nim/flags2env.nimble '^installFiles'
require_contains clients/r/.Rbuildignore '\^Dockerfile\$'
require_contains clients/r/src/flags2env_r.c '#include "parser\.h"'
forbid_contains clients/r/src/flags2env_r.c '\.\./\.\./\.\./src/parser\.h'
require_contains clients/r/tests/smoke.R 'parse_flags'
require_contains clients/matlab/test.m 'flags2env\.parse'
require_contains clients/matlab/+flags2env/defaultHeaderPath.m 'native'
require_contains clients/matlab/+flags2env/ensureLoaded.m 'flags2env\.defaultHeaderPath\(\)'
forbid_contains clients/matlab/+flags2env/apply.m 'fullfile\(pwd, "src", "parser\.h"\)'
forbid_contains clients/matlab/+flags2env/ensureLoaded.m 'fullfile\(pwd, "src", "parser\.h"\)'
forbid_contains clients/matlab/+flags2env/parse.m 'fullfile\(pwd, "src", "parser\.h"\)'
forbid_contains clients/matlab/+flags2env/parseProcess.m 'fullfile\(pwd, "src", "parser\.h"\)'
require_same_file src/parser.c clients/matlab/native/parser.c
require_same_file src/parser.h clients/matlab/native/parser.h
require_contains clients/julia/Project.toml '^name = "Flags2Env"'
require_contains clients/julia/Project.toml '^uuid = "[0-9a-f-]{36}"'
require_contains clients/julia/Project.toml '^version = "0\.1\.0"'
require_contains clients/julia/REGISTRATION.md '@JuliaRegistrator register subdir=clients/julia'
require_contains clients/solidity/package.json '"files"'
require_contains clients/solidity/package.json '"test"'
require_contains clients/solidity/package.json '"solc"'
require_contains clients/zig/build.zig 'native/parser\.c'
require_contains clients/zig/build.zig 'b\.path\("native"\)'
forbid_contains clients/zig/build.zig '\.\./\.\./src'
require_same_file src/parser.c clients/zig/native/parser.c
require_same_file src/parser.h clients/zig/native/parser.h
require_contains clients/deno/deno.json '"native"'
require_contains scripts/render-client.mjs 'src/parser\.c'
require_contains scripts/render-client.mjs 'native'
require_contains scripts/publish-client.sh 'cp src/parser\.c src/parser\.h dist/r/src/'
require_contains scripts/publish-client.sh 'npm publish --access public'
require_contains scripts/publish-client.sh 'node scripts/render-client\.mjs deno dist/deno'
require_contains scripts/publish-client.sh 'twine upload'
require_contains scripts/publish-client.sh 'clients/golang/v\$'
require_contains scripts/publish-client.sh 'git tag "\$\{PACKAGE_VERSION:\?set PACKAGE_VERSION\}"'
require_contains scripts/publish-client.sh 'git push origin "v\$\{PACKAGE_VERSION\}"'
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
require_contains scripts/publish-client.sh 'opam lint flags2env-reason\.opam'
require_contains scripts/publish-client.sh 'cpan-upload'
require_contains scripts/publish-client.sh 'luarocks upload flags2env-0\.1\.0-1\.rockspec'
require_contains scripts/publish-client.sh 'nimble publish'
require_contains scripts/publish-client.sh 'submit_cran'
require_contains scripts/publish-client.sh 'zip -r flags2env-matlab\.zip \+flags2env native README\.md'
require_contains scripts/publish-client.sh '@JuliaRegistrator register subdir=clients/julia'
require_contains scripts/docker-check-new-clients.sh 'dotnet run'
require_contains scripts/docker-check-new-clients.sh 'dotnet run --project /tmp/f2e-csharp-test/f2e-csharp-test\.csproj'
require_contains scripts/docker-check-new-clients.sh 'dotnet run --project /tmp/f2e-fsharp-test/f2e-fsharp-test\.fsproj'
forbid_contains scripts/docker-check-new-clients.sh 'FLAGS2ENV_FIXTURE=tests/fixtures|FLAGS2ENV_NATIVE_LIB=build/libflags2env\.so.*dotnet|LD_LIBRARY_PATH=build.*dotnet'
require_contains scripts/docker-check-new-clients.sh 'clients/cpp/native/parser\.c'
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
  clients/rust/tests/smoke.rs \
  clients/elixir/test.exs \
  clients/erlang/flags2env_test.erl \
  clients/gleam/test.gleam \
  clients/r/R/flags2env.R \
  clients/r/tests/smoke.R \
  clients/matlab/+flags2env/defaultHeaderPath.m \
  clients/matlab/test.m \
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

for path in \
  clients/cpp/test.cpp \
  clients/crystal/test.cr \
  clients/fortran/test.f90 \
  clients/haskell/test.hs \
  clients/julia/test/runtests.jl \
  clients/lua/test.lua \
  clients/nim/test.nim \
  clients/ocaml/test.ml \
  clients/reasonml/src/Test.re \
  clients/rust/tests/smoke.rs \
  clients/zig/test.zig
do
  forbid_contains "$path" 'tests/fixtures|\.\./\.\./tests'
done

native_lib="$(native_library_name)"
audit_rendered_js_client nodejs package.json binding.gyp addon.c src/parser.c src/parser.h lib.mjs lib.cjs lib.ts cli.mjs
audit_rendered_js_client bun package.json "native/$native_lib" lib.mjs lib.cjs lib.ts
audit_rendered_js_client deno deno.json "native/$native_lib" mod.ts lib.ts
audit_npm_pack_client solidity "contracts/Flags2Env.sol package.json" "test.js test.ts Dockerfile"
audit_perl_manifest
audit_r_staging

if [ "$status" -eq 0 ]; then
  printf 'client packaging audit passed\n'
fi
exit "$status"
