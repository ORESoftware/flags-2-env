#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
FULL=0

if [ "${1:-}" = "--full" ]; then
  FULL=1
elif [ "$#" -gt 0 ]; then
  printf 'usage: %s [--full]\n' "$0" >&2
  exit 2
fi

run() {
  label="$1"
  image="$2"
  command="$3"
  printf '\n==> docker check %s\n' "$label"
  docker run --rm -u 0:0 -v "$ROOT_DIR:/repo:ro" -w /work "$image" sh -euxc "cp -R /repo/. /work && $command"
}

run perl perl:5.38-bookworm \
  'apt-get update && apt-get install -y --no-install-recommends build-essential libffi-dev cpanminus make && cpanm -n FFI::Platypus JSON::PP && make clean && make all && FLAGS2ENV_NATIVE_LIB=build/libflags2env.so perl clients/perl/test.pl'

run dotnet mcr.microsoft.com/dotnet/sdk:8.0 \
  'apt-get update && apt-get install -y --no-install-recommends build-essential && dotnet build clients/csharp/Flags2Env.csproj --nologo && dotnet build clients/fsharp/Flags2Env.FSharp.fsproj --nologo && dotnet new console --language C# --framework net8.0 --output /tmp/f2e-csharp-test --force && cp clients/csharp/Flags2EnvTest.cs /tmp/f2e-csharp-test/Program.cs && dotnet add /tmp/f2e-csharp-test/f2e-csharp-test.csproj reference clients/csharp/Flags2Env.csproj && dotnet run --project /tmp/f2e-csharp-test/f2e-csharp-test.csproj && dotnet new console --language F# --framework net8.0 --output /tmp/f2e-fsharp-test --force && cp clients/fsharp/Flags2EnvTest.fs /tmp/f2e-fsharp-test/Program.fs && dotnet add /tmp/f2e-fsharp-test/f2e-fsharp-test.fsproj reference clients/fsharp/Flags2Env.FSharp.fsproj && dotnet run --project /tmp/f2e-fsharp-test/f2e-fsharp-test.fsproj'

run cpp gcc:13-bookworm \
  'cc -std=c99 -Wall -Wextra -Wpedantic -O2 -fPIC -c clients/cpp/native/parser.c -Iclients/cpp/native -o /tmp/flags2env-parser.o && c++ -std=c++17 -Iclients/cpp/include -Iclients/cpp/native clients/cpp/test.cpp /tmp/flags2env-parser.o -o /tmp/flags2env-cpp-test && /tmp/flags2env-cpp-test && c++ -std=c++17 -Iclients/cpp/include -Iclients/cpp/native -x c++ -c -o /tmp/flags2env-cpp-check.o - <<EOF
#include "flags2env.hpp"
int main() {
  auto parsed = flags2env::parse({"app", "--port", "8080"});
  return parsed.empty() ? 0 : 0;
}
EOF'

run fortran gcc:13-bookworm \
  'apt-get update && apt-get install -y --no-install-recommends gfortran && cc -std=c99 -Wall -Wextra -Wpedantic -O2 -fPIC -c src/parser.c -o /tmp/flags2env-parser.o && gfortran -c clients/fortran/src/flags2env.f90 -J /tmp -o /tmp/flags2env-fortran.o && gfortran -I /tmp clients/fortran/test.f90 /tmp/flags2env-fortran.o /tmp/flags2env-parser.o -o /tmp/flags2env-fortran-test && /tmp/flags2env-fortran-test'

run zig kassany/bookworm-ziglang:0.13.0 \
  'zig version && cd clients/zig && zig build test'

run lua debian:bookworm \
  'apt-get update && apt-get install -y --no-install-recommends build-essential make luajit && make clean && make all && FLAGS2ENV_NATIVE_LIB=build/libflags2env.so luajit clients/lua/test.lua'

run nim nimlang/nim:2.0.10 \
  'apt-get update && apt-get install -y --no-install-recommends build-essential make && make clean && make all && LD_LIBRARY_PATH=build nim c -r clients/nim/test.nim'

run crystal crystallang/crystal:1.13.3 \
  'apt-get update && apt-get install -y --no-install-recommends build-essential make && make clean && make all && LIBRARY_PATH=build LD_LIBRARY_PATH=build crystal clients/crystal/test.cr'

run r r-base:4.4.2 \
  'apt-get update && apt-get install -y --no-install-recommends build-essential make && Rscript -e "install.packages(\"jsonlite\", repos=\"https://cloud.r-project.org\")" && R CMD INSTALL clients/r && cd tests/fixtures && Rscript -e "library(flags2env); parsed <- parse_flags(c(\"app\", \"--debug=t\", \"--port\", \"8181\")); stopifnot(parsed[[\"DEBUG\"]] == \"true\", parsed[[\"PORT\"]] == \"8181\")"'

run clojure clojure:temurin-21-tools-deps \
  'apt-get update && apt-get install -y --no-install-recommends maven && mvn -q -f clients/java/pom.xml -DskipTests install && cd clients/clojure && clojure -T:build jar'

run solidity node:22-bookworm \
  'cd clients/solidity && npm install --no-package-lock --ignore-scripts && npm test && npm pack --dry-run --json'

run packaging debian:bookworm \
  'sh scripts/audit-client-packaging.sh'

if [ "$FULL" -eq 1 ]; then
  run jvm gradle:8.10-jdk21 \
    'apt-get update && apt-get install -y --no-install-recommends maven && mvn -q -f clients/java/pom.xml -DskipTests install && gradle -p clients/kotlin compileKotlin --no-daemon && gradle -p clients/groovy compileGroovy --no-daemon'

  run scala sbtscala/scala-sbt:eclipse-temurin-21.0.8_9_1.11.7_2.13.17 \
    'apt-get update && apt-get install -y --no-install-recommends maven && mvn -q -f clients/java/pom.xml -DskipTests install && cd clients/scala && sbt -batch -Dsbt.supershell=false compile'

  run haskell haskell:latest \
    'make clean && make all && cd clients/haskell && cabal update && cabal check && LIBRARY_PATH=/work/build LD_LIBRARY_PATH=/work/build cabal test --extra-lib-dirs=/work/build all'

  run ocaml debian:bookworm \
    'apt-get update && apt-get install -y --no-install-recommends opam ca-certificates && opam lint clients/ocaml/flags2env.opam && opam lint clients/reasonml/flags2env-reason.opam'

  run julia julia:1.10 \
    'make clean && make all && LD_LIBRARY_PATH=build julia --project=clients/julia -e "using Pkg; Pkg.instantiate(); Pkg.test()"'
fi
