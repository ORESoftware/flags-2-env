#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
FULL=0
DRY_RUN=0
ONLY=""
MATCHED=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --full)
      FULL=1
      ;;
    --dry-run)
      DRY_RUN=1
      ;;
    --only)
      shift
      if [ "$#" -eq 0 ]; then
        printf '%s\n' '--only requires a client label' >&2
        exit 2
      fi
      ONLY="$1"
      ;;
    *)
      printf 'usage: %s [--full] [--dry-run] [--only LABEL]\n' "$0" >&2
      exit 2
      ;;
  esac
  shift
done

run() {
  label="$1"
  image="$2"
  command="$3"
  if [ -n "$ONLY" ] && [ "$ONLY" != "$label" ]; then
    return
  fi
  MATCHED=1
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[dry-run] docker check %s: %s\n' "$label" "$image"
    printf '[dry-run] docker command %s: %s\n' "$label" "$command"
    return
  fi
  printf '\n==> docker check %s\n' "$label"
  docker run --rm -u 0:0 -v "$ROOT_DIR:/repo:ro" -w /work "$image" sh -euxc "cp -R /repo/. /work && $command"
}

run perl perl:5.38-bookworm \
  'apt-get update && apt-get install -y --no-install-recommends build-essential libffi-dev cpanminus make && cpanm -n FFI::Platypus JSON::PP && make clean && make all && FLAGS2ENV_NATIVE_LIB=build/libflags2env.so perl clients/perl/test.pl'

run dotnet mcr.microsoft.com/dotnet/sdk:8.0 \
  'apt-get update && apt-get install -y --no-install-recommends build-essential python3 && dotnet build clients/csharp/Flags2Env.csproj --nologo && dotnet build clients/fsharp/Flags2Env.FSharp.fsproj --nologo && dotnet new console --language C# --framework net8.0 --output /tmp/f2e-csharp-test --force && cp clients/csharp/Flags2EnvTest.cs /tmp/f2e-csharp-test/Program.cs && dotnet add /tmp/f2e-csharp-test/f2e-csharp-test.csproj reference clients/csharp/Flags2Env.csproj && dotnet run --project /tmp/f2e-csharp-test/f2e-csharp-test.csproj && dotnet new console --language F# --framework net8.0 --output /tmp/f2e-fsharp-test --force && cp clients/fsharp/Flags2EnvTest.fs /tmp/f2e-fsharp-test/Program.fs && dotnet add /tmp/f2e-fsharp-test/f2e-fsharp-test.fsproj reference clients/fsharp/Flags2Env.FSharp.fsproj && dotnet run --project /tmp/f2e-fsharp-test/f2e-fsharp-test.fsproj && dotnet pack clients/csharp/Flags2Env.csproj -c Release --nologo && dotnet pack clients/fsharp/Flags2Env.FSharp.fsproj -c Release --nologo && python3 - <<PY
from pathlib import Path
import zipfile

packages = [
    ("clients/csharp/bin/Release", "OreSoftware.Flags2Env.*.nupkg"),
    ("clients/fsharp/bin/Release", "OreSoftware.Flags2Env.FSharp.*.nupkg"),
]
for directory, pattern in packages:
    package = next(Path(directory).glob(pattern))
    with zipfile.ZipFile(package) as archive:
        names = set(archive.namelist())
    for required in ["README.md", "native/parser.c", "native/parser.h"]:
        if required not in names:
            raise SystemExit(f"{package.name} missing {required}")
    for forbidden in ["Flags2EnvTest.cs", "Flags2EnvTest.fs", "publish.sh", "Dockerfile"]:
        if any(name.endswith(forbidden) for name in names):
            raise SystemExit(f"{package.name} includes {forbidden}")
    if not any(name.startswith("lib/net6.0/") and name.endswith(".dll") for name in names):
        raise SystemExit(f"{package.name} missing net6.0 library")
PY'

run java maven:3.9-eclipse-temurin-21 \
  'mvn -q -f clients/java/pom.xml -DskipTests package && jar tf clients/java/target/flags2env-0.1.0.jar > /tmp/flags2env-java-jar-files && jar tf clients/java/target/flags2env-0.1.0-sources.jar > /tmp/flags2env-java-sources-files && jar tf clients/java/target/flags2env-0.1.0-javadoc.jar > /tmp/flags2env-java-javadoc-files && grep -Fxq com/oresoftware/flags2env/Flags2Env.class /tmp/flags2env-java-jar-files && grep -Fxq native/parser.c /tmp/flags2env-java-jar-files && grep -Fxq native/parser.h /tmp/flags2env-java-jar-files && grep -Fxq com/oresoftware/flags2env/Flags2Env.java /tmp/flags2env-java-sources-files && grep -Eq "(index|com/oresoftware/flags2env/Flags2Env)\.html$" /tmp/flags2env-java-javadoc-files && if grep -Eq "(^|/)(Flags2EnvTest\.java|Dockerfile|publish\.sh)$" /tmp/flags2env-java-jar-files /tmp/flags2env-java-sources-files /tmp/flags2env-java-javadoc-files; then printf "Maven artifact includes forbidden local file\n" >&2; exit 1; fi'

run python python:3.12-bookworm \
  'cd clients/python && python -m pip install --no-cache-dir --upgrade build twine && rm -rf dist build *.egg-info && python -m build && python -m twine check dist/* && python - <<PY
import tarfile, zipfile
from pathlib import Path

dist = Path("dist")
sdist = next(dist.glob("flags2env-*.tar.gz"))
wheel = next(dist.glob("flags2env-*-py3-none-any.whl"))
with tarfile.open(sdist) as archive:
    sdist_files = {"/".join(Path(member.name).parts[1:]) for member in archive.getmembers()}
with zipfile.ZipFile(wheel) as archive:
    wheel_files = set(archive.namelist())
for required in ["README.md", "LICENSE", "flags2env.py", "lib.py"]:
    if required not in sdist_files:
        raise SystemExit(f"sdist missing {required}")
for forbidden in ["Dockerfile", "publish.sh", "test.py"]:
    if forbidden in sdist_files:
        raise SystemExit(f"sdist includes {forbidden}")
if "flags2env.py" not in wheel_files or "lib.py" not in wheel_files:
    raise SystemExit("wheel missing runtime modules")
if not any(path.endswith(".dist-info/licenses/LICENSE") for path in wheel_files):
    raise SystemExit("wheel missing dist-info license")
PY'

run rust rust:1-bookworm \
  'apt-get update && apt-get install -y --no-install-recommends build-essential && cd clients/rust && cargo test && cargo package --allow-dirty'

run golang golang:1.23-bookworm \
  'apt-get update && apt-get install -y --no-install-recommends build-essential && cd clients/golang && go test ./...'

run cpp gcc:13-bookworm \
  'apt-get update && apt-get install -y --no-install-recommends cmake && cmake -S clients/cpp -B /tmp/flags2env-cpp-build -DCMAKE_BUILD_TYPE=Release && cmake --build /tmp/flags2env-cpp-build --verbose && ctest --test-dir /tmp/flags2env-cpp-build --output-on-failure && c++ -std=c++17 -Iclients/cpp/include -Iclients/cpp/native -x c++ -c -o /tmp/flags2env-cpp-check.o - <<EOF
#include "flags2env.hpp"
int main() {
  auto parsed = flags2env::parse({"app", "--port", "8080"});
  return parsed.empty() ? 0 : 0;
}
EOF'

run fortran gcc:13-bookworm \
  'apt-get update && apt-get install -y --no-install-recommends gfortran-12 && cc -std=c99 -Wall -Wextra -Wpedantic -O2 -fPIC -c clients/fortran/src/parser.c -Iclients/fortran/src -o /tmp/flags2env-parser.o && gfortran-12 -c clients/fortran/src/flags2env.f90 -J /tmp -o /tmp/flags2env-fortran.o && gfortran-12 -I /tmp clients/fortran/test.f90 /tmp/flags2env-fortran.o /tmp/flags2env-parser.o -o /tmp/flags2env-fortran-test && /tmp/flags2env-fortran-test'

run zig kassany/bookworm-ziglang:0.14.0 \
  'zig version && cd clients/zig && zig build test'

run lua debian:bookworm \
  'apt-get update && apt-get install -y --no-install-recommends build-essential make luajit luarocks && make clean && make all && FLAGS2ENV_NATIVE_LIB=build/libflags2env.so luajit clients/lua/test.lua && luarocks lint clients/lua/flags2env-0.1.0-1.rockspec && luarocks lint clients/lua/flags2env-dev-1.rockspec'

run php php:8.3-cli \
  'apt-get update && apt-get install -y --no-install-recommends build-essential libffi-dev make composer unzip && docker-php-ext-install ffi && make clean && make all && php -d ffi.enable=true clients/php/test.php && cd clients/php && composer validate --strict && rm -f /tmp/flags2env-php-archive.zip && composer archive --format=zip --file=/tmp/flags2env-php-archive && unzip -Z1 /tmp/flags2env-php-archive.zip > /tmp/flags2env-php-archive-files && for required in lib.php README.md LICENSE composer.json; do grep -Eq "(^|/)$required$" /tmp/flags2env-php-archive-files || { printf "Composer archive missing %s\n" "$required" >&2; exit 1; }; done && if grep -Eq "(^|/)(Dockerfile|publish\.sh|test\.php)$" /tmp/flags2env-php-archive-files; then printf "Composer archive includes forbidden local file\n" >&2; exit 1; fi'

run dart dart:stable \
  'apt-get update && apt-get install -y --no-install-recommends build-essential make && make clean && make all && cd clients/dart && dart pub get && dart run test.dart && dart pub publish --dry-run'

run nim nimlang/nim:2.0.10 \
  'apt-get update && apt-get install -y --no-install-recommends build-essential make && make clean && make all && cd clients/nim && nimble check && cd ../.. && LD_LIBRARY_PATH=build nim c -r clients/nim/test.nim'

run crystal crystallang/crystal:1.13.3 \
  'apt-get update && apt-get install -y --no-install-recommends build-essential make && make clean && make all && cd clients/crystal && shards install --production && cd ../.. && LIBRARY_PATH=build LD_LIBRARY_PATH=build crystal clients/crystal/test.cr'

run r r-base:4.4.2 \
  'apt-get update && apt-get install -y --no-install-recommends build-essential make && Rscript -e "install.packages(\"jsonlite\", repos=\"https://cloud.r-project.org\")" && R CMD INSTALL clients/r && cd tests/fixtures && Rscript -e "library(flags2env); parsed <- parse_flags(c(\"app\", \"--debug=t\", \"--port\", \"8181\")); stopifnot(parsed[[\"DEBUG\"]] == \"true\", parsed[[\"PORT\"]] == \"8181\")" && cd /work && R CMD build clients/r && R CMD check --no-manual flags2env_0.1.0.tar.gz && tar -tf flags2env_0.1.0.tar.gz > /tmp/flags2env-r-sdist-files && for required in DESCRIPTION NAMESPACE R/flags2env.R src/flags2env_r.c src/parser.c src/parser.h tests/smoke.R README.md LICENSE; do grep -Fxq "flags2env/$required" /tmp/flags2env-r-sdist-files || { printf "R source package missing %s\n" "$required" >&2; exit 1; }; done && if grep -Eq "/(Dockerfile|publish\.sh|.*\.Rcheck|flags2env_.*\.tar\.gz)$" /tmp/flags2env-r-sdist-files; then printf "R source package includes forbidden local file\n" >&2; exit 1; fi'

run clojure clojure:temurin-21-tools-deps \
  'apt-get update && apt-get install -y --no-install-recommends maven && mvn -q -f clients/java/pom.xml -DskipTests install && cd clients/clojure && clojure -T:build jar && clojure -T:build source-jar && clojure -T:build javadoc-jar && jar tf target/flags2env-clojure-0.1.0.jar > /tmp/flags2env-clojure-jar-files && jar tf target/flags2env-clojure-0.1.0-sources.jar > /tmp/flags2env-clojure-sources-files && jar tf target/flags2env-clojure-0.1.0-javadoc.jar > /tmp/flags2env-clojure-javadoc-files && grep -Fxq com/oresoftware/flags2env.clj /tmp/flags2env-clojure-jar-files && grep -Fxq META-INF/maven/com.oresoftware/flags2env-clojure/pom.xml /tmp/flags2env-clojure-jar-files && grep -Fxq com/oresoftware/flags2env.clj /tmp/flags2env-clojure-sources-files && grep -Fxq README.md /tmp/flags2env-clojure-javadoc-files && if grep -Eq "(^|/)(Dockerfile|publish\.sh|build\.clj|deps\.edn|.*Test.*)$" /tmp/flags2env-clojure-jar-files /tmp/flags2env-clojure-sources-files /tmp/flags2env-clojure-javadoc-files; then printf "Clojure artifact includes forbidden local file\n" >&2; exit 1; fi'

run erlang-hex erlang:27 \
  'cd clients/erlang && rebar3 hex build package && mkdir -p /tmp/flags2env-erlang-hex && tar -xf _build/default/lib/flags2env/hex/flags2env-0.1.0.tar -C /tmp/flags2env-erlang-hex contents.tar.gz metadata.config && tar -tzf /tmp/flags2env-erlang-hex/contents.tar.gz > /tmp/flags2env-erlang-hex-files && for required in src/flags2env.erl src/flags2env.app.src c_src/flags2env_nif.c c_src/parser.c c_src/parser.h README.md LICENSE rebar.config; do grep -Fxq "$required" /tmp/flags2env-erlang-hex-files || { printf "Erlang Hex package missing %s\n" "$required" >&2; exit 1; }; done && grep -Fq "{<<\"name\">>,<<\"flags2env\">>}." /tmp/flags2env-erlang-hex/metadata.config && grep -Fq "{<<\"version\">>,<<\"0.1.0\">>}." /tmp/flags2env-erlang-hex/metadata.config && if grep -Eq "(^|/)(Dockerfile|publish\.sh|flags2env_test\.erl)$" /tmp/flags2env-erlang-hex-files; then printf "Erlang Hex package includes forbidden local file\n" >&2; exit 1; fi'

run solidity node:22-bookworm \
  'cd clients/solidity && npm install --no-package-lock --ignore-scripts && npm test && npm pack --dry-run --json > /tmp/flags2env-solidity-pack.json && for required in contracts/Flags2Env.sol package.json README.md LICENSE; do grep -Fq "\"path\":\"$required\"" /tmp/flags2env-solidity-pack.json || grep -Fq "\"path\": \"$required\"" /tmp/flags2env-solidity-pack.json || { printf "Solidity npm package missing %s\n" "$required" >&2; exit 1; }; done && if grep -Eq "\"path\"[[:space:]]*:[[:space:]]*\"(test\\.(js|ts)|Dockerfile|publish\\.sh)\"" /tmp/flags2env-solidity-pack.json; then printf "Solidity npm package includes forbidden local file\n" >&2; exit 1; fi'

run packaging debian:bookworm \
  'sh scripts/audit-client-packaging.sh'

if [ "$FULL" -eq 1 ]; then
  run jvm gradle:8.10-jdk21 \
    'apt-get update && apt-get install -y --no-install-recommends maven && mvn -q -f clients/java/pom.xml -DskipTests install && gradle -p clients/kotlin jar sourcesJar javadocJar --no-daemon && gradle -p clients/groovy jar sourcesJar javadocJar --no-daemon && jar tf clients/kotlin/build/libs/flags2env-kotlin-0.1.0.jar > /tmp/flags2env-kotlin-jar-files && jar tf clients/kotlin/build/libs/flags2env-kotlin-0.1.0-sources.jar > /tmp/flags2env-kotlin-sources-files && jar tf clients/kotlin/build/libs/flags2env-kotlin-0.1.0-javadoc.jar >/dev/null && jar tf clients/groovy/build/libs/flags2env-groovy-0.1.0.jar > /tmp/flags2env-groovy-jar-files && jar tf clients/groovy/build/libs/flags2env-groovy-0.1.0-sources.jar > /tmp/flags2env-groovy-sources-files && jar tf clients/groovy/build/libs/flags2env-groovy-0.1.0-javadoc.jar >/dev/null && grep -Fxq com/oresoftware/flags2env/kotlin/Flags2Env.class /tmp/flags2env-kotlin-jar-files && grep -Fxq com/oresoftware/flags2env/Flags2Env.kt /tmp/flags2env-kotlin-sources-files && grep -Fxq com/oresoftware/flags2env/groovy/Flags2Env.class /tmp/flags2env-groovy-jar-files && grep -Fxq com/oresoftware/flags2env/Flags2Env.groovy /tmp/flags2env-groovy-sources-files && if grep -Eq "(^|/)(Dockerfile|publish\.sh|.*Test.*)$" /tmp/flags2env-kotlin-jar-files /tmp/flags2env-kotlin-sources-files /tmp/flags2env-groovy-jar-files /tmp/flags2env-groovy-sources-files; then printf "Gradle artifact includes forbidden local file\n" >&2; exit 1; fi'

  run scala sbtscala/scala-sbt:eclipse-temurin-21.0.8_9_1.11.7_2.13.17 \
    'apt-get update && apt-get install -y --no-install-recommends maven && mvn -q -f clients/java/pom.xml -DskipTests install && cd clients/scala && sbt -batch -Dsbt.supershell=false package "Compile / packageSrc" "Compile / packageDoc" && jar tf target/scala-2.13/flags2env-scala_2.13-0.1.0.jar > /tmp/flags2env-scala-jar-files && jar tf target/scala-2.13/flags2env-scala_2.13-0.1.0-sources.jar > /tmp/flags2env-scala-sources-files && jar tf target/scala-2.13/flags2env-scala_2.13-0.1.0-javadoc.jar >/dev/null && grep -Fxq "com/oresoftware/flags2env/scala/Flags2Env$.class" /tmp/flags2env-scala-jar-files && grep -Fxq com/oresoftware/flags2env/Flags2Env.scala /tmp/flags2env-scala-sources-files && if grep -Eq "(^|/)(Dockerfile|publish\.sh|.*Test.*)$" /tmp/flags2env-scala-jar-files /tmp/flags2env-scala-sources-files; then printf "Scala artifact includes forbidden local file\n" >&2; exit 1; fi'

  run haskell haskell:latest \
    'make clean && make all && cd clients/haskell && cabal update && cabal check && LIBRARY_PATH=/work/build LD_LIBRARY_PATH=/work/build cabal test --extra-lib-dirs=/work/build all && rm -rf dist-newstyle/sdist && cabal sdist && tar -tf dist-newstyle/sdist/flags2env-0.1.0.tar.gz > /tmp/flags2env-haskell-sdist-files && for required in flags2env.cabal LICENSE README.md src/Flags2Env.hs test.hs; do grep -Eq "/$required$" /tmp/flags2env-haskell-sdist-files || { printf "Hackage sdist missing %s\n" "$required" >&2; exit 1; }; done && if grep -Eq "/(Dockerfile|publish\.sh|dist-newstyle|cabal.project.local)$" /tmp/flags2env-haskell-sdist-files; then printf "Hackage sdist includes forbidden local file\n" >&2; exit 1; fi'

  run swift swift:6.0 \
    'apt-get update && apt-get install -y --no-install-recommends build-essential make && make clean && make all && swift package --disable-sandbox --scratch-path /tmp/flags2env-swift-build describe --type json > /tmp/flags2env-swift-package.json && grep -Fq "\"name\" : \"Flags2Env\"" /tmp/flags2env-swift-package.json && grep -Fq "\"path\" : \"clients/swift\"" /tmp/flags2env-swift-package.json && grep -Fq "\"lib.swift\"" /tmp/flags2env-swift-package.json && swift build --disable-sandbox --scratch-path /tmp/flags2env-swift-build -c release && swiftc clients/swift/lib.swift clients/swift/test.swift -o /tmp/flags2env-swift-test && cd clients/swift && /tmp/flags2env-swift-test'

  run ocaml debian:bookworm \
    'apt-get update && apt-get install -y --no-install-recommends build-essential make opam pkg-config libffi-dev m4 ca-certificates && opam init --disable-sandboxing --bare -y && opam switch create flags2env ocaml-base-compiler.5.1.1 -y && eval "$(opam env --switch=flags2env)" && opam install -y dune ctypes ctypes-foreign yojson reason && make clean && make all && opam lint clients/ocaml/flags2env.opam && opam lint clients/reasonml/flags2env-reason.opam && cd clients/ocaml && FLAGS2ENV_NATIVE_LIB=/work/build/libflags2env.so dune runtest && dune install --prefix="$(opam var prefix)" flags2env && cd ../reasonml && FLAGS2ENV_NATIVE_LIB=/work/build/libflags2env.so dune runtest'

  run julia julia:1.10 \
    'make clean && make all && LD_LIBRARY_PATH=build julia --project=clients/julia -e "using Pkg; Pkg.instantiate(); Pkg.test()"'
fi

if [ -n "$ONLY" ] && [ "$MATCHED" -eq 0 ]; then
  printf 'unknown or disabled client label: %s\n' "$ONLY" >&2
  exit 2
fi
