#!/usr/bin/env node
import { existsSync, readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { join } from "node:path";

const root = new URL("..", import.meta.url).pathname;

const requiredClients = [
  "nodejs", "python", "java", "kotlin", "scala", "groovy", "clojure",
  "rust", "golang", "c", "cpp", "csharp", "fsharp", "php", "ruby",
  "swift", "dart", "elixir", "erlang", "gleam", "haskell", "ocaml",
  "reasonml", "perl", "lua", "nim", "r", "matlab", "julia", "fortran",
  "zig", "crystal", "solidity", "bash", "zsh",
];

const expectedRepositories = {
  nodejs: "npm Registry",
  python: "PyPI",
  java: "Maven Central / Sonatype",
  kotlin: "Maven Central / Sonatype",
  scala: "Maven Central / Sonatype",
  groovy: "Maven Central / Sonatype",
  clojure: "Maven Central / Sonatype",
  rust: "crates.io",
  golang: "Git repository / pkg.go.dev",
  c: "Git repository / Homebrew source build",
  cpp: "Git repository / source archive",
  csharp: "NuGet Gallery",
  fsharp: "NuGet Gallery",
  php: "Packagist",
  ruby: "RubyGems.org",
  swift: "Git repository / SwiftPM",
  dart: "pub.dev",
  elixir: "Hex.pm",
  erlang: "Hex.pm",
  gleam: "Hex.pm",
  haskell: "Hackage",
  ocaml: "opam Repository",
  reasonml: "opam Repository",
  perl: "CPAN",
  lua: "LuaRocks Repository",
  nim: "Nimble Package Index",
  r: "CRAN / R-universe",
  matlab: "Source archive / Git repository",
  julia: "Julia General Registry",
  fortran: "Git repository / fpm package",
  zig: "Git repository / Zig package",
  crystal: "Git repository / Shards",
  solidity: "npm Registry",
  bash: "Homebrew / Git repository",
  zsh: "Homebrew / Git repository",
};

const packageControls = {
  nodejs: [
    [".npmignore", /^!clients\/nodejs\//m, "npm allowlist includes Node.js client"],
    ["package.json", /"files"\s*:\s*\[/, "npm package files allowlist"],
    ["package.json", /"clients\/nodejs\/lib\.mjs"/, "npm package includes Node.js ESM client"],
    ["package.json", /"clients\/bun\/lib\.mjs"/, "npm package includes Bun entry"],
    ["package.json", /"clients\/deno\/mod\.ts"/, "npm package includes Deno entry"],
  ],
  python: [
    ["clients/python/MANIFEST.in", /^include lib\.py$/m, "PyPI MANIFEST includes runtime module"],
    ["clients/python/MANIFEST.in", /^exclude Dockerfile$/m, "PyPI MANIFEST excludes Dockerfile"],
    ["clients/python/MANIFEST.in", /^exclude test\.py$/m, "PyPI MANIFEST excludes test file"],
  ],
  java: [
    ["clients/java/pom.xml", /central-publishing-maven-plugin/, "Maven Central publishing plugin"],
    ["clients/java/pom.xml", /<directory>native<\/directory>/, "Maven package uses package-local native sources"],
    ["clients/java/pom.xml", /<include>\*\*\/\*\.c<\/include>/, "Maven package includes C sources"],
    ["clients/java/pom.xml", /<include>\*\*\/\*\.h<\/include>/, "Maven package includes C headers"],
    ["clients/java/pom.xml", /<excludes>[\s\S]*<exclude>\*\*\/publish\.sh<\/exclude>/, "Maven resources exclude publish wrappers"],
    ["clients/java/native/flags2env_jni.c", /#include "parser\.h"/, "JNI source includes package-local parser header"],
    ["clients/java/Dockerfile", /clients\/java\/native\/parser\.c/, "Java Docker smoke builds package-local parser source"],
  ],
  kotlin: [
    ["clients/kotlin/build.gradle.kts", /`maven-publish`/, "Gradle maven-publish plugin"],
    ["clients/kotlin/build.gradle.kts", /ossrh-staging-api\.central\.sonatype\.com/, "Kotlin publishes through Central Portal OSSRH compatibility endpoint"],
    ["clients/kotlin/build.gradle.kts", /CENTRAL_TOKEN_USERNAME/, "Kotlin uses Central Portal token env vars"],
    ["clients/kotlin/build.gradle.kts", /artifactId = "flags2env-kotlin"/, "Kotlin artifact id"],
    ["clients/kotlin/build.gradle.kts", /exclude\("publish\.sh"\)/, "Kotlin jar excludes publish wrapper"],
  ],
  scala: [
    ["clients/scala/build.sbt", /sonatypeCentralHost/, "Scala uses Sonatype Central portal host"],
    ["clients/scala/build.sbt", /publishTo := sonatypePublishToBundle\.value/, "Scala Sonatype bundle publishing"],
    ["clients/scala/build.sbt", /publishMavenStyle := true/, "Scala Maven-style package"],
    ["clients/scala/project/plugins.sbt", /sbt-sonatype/, "Scala Sonatype plugin"],
  ],
  groovy: [
    ["clients/groovy/build.gradle", /id 'maven-publish'/, "Groovy Gradle maven-publish plugin"],
    ["clients/groovy/build.gradle", /ossrh-staging-api\.central\.sonatype\.com/, "Groovy publishes through Central Portal OSSRH compatibility endpoint"],
    ["clients/groovy/build.gradle", /CENTRAL_TOKEN_USERNAME/, "Groovy uses Central Portal token env vars"],
    ["clients/groovy/build.gradle", /artifactId = 'flags2env-groovy'/, "Groovy artifact id"],
    ["clients/groovy/build.gradle", /exclude 'publish\.sh'/, "Groovy jar excludes publish wrapper"],
  ],
  clojure: [
    ["clients/clojure/build.clj", /sign-and-deploy-file/, "Clojure Sonatype deploy command"],
    ["clients/clojure/build.clj", /ossrh-staging-api\.central\.sonatype\.com/, "Clojure publishes through Central Portal OSSRH compatibility endpoint"],
    ["clients/clojure/build.clj", /source-jar/, "Clojure source jar generation"],
    ["clients/clojure/build.clj", /com\.oresoftware\/flags2env-clojure/, "Clojure Maven artifact id"],
  ],
  rust: [
    ["clients/rust/Cargo.toml", /^include = \[/m, "Cargo include allowlist"],
    ["clients/rust/Cargo.toml", /"native\/\*\*"/, "Cargo includes package-local parser sources"],
    ["clients/rust/Cargo.toml", /"src\/\*\*"/, "Cargo includes Rust source"],
    ["clients/rust/Cargo.toml", /"tests\/\*\*"/, "Cargo includes package-local smoke tests"],
    ["clients/rust/Dockerfile", /COPY clients\/rust \.\/clients\/rust/, "Rust Docker smoke copies only the Rust package"],
    ["clients/rust/tests/smoke.rs", /native\/parser\.c/, "Rust smoke test builds package-local parser source"],
  ],
  golang: [
    ["clients/golang/go.mod", /^module github\.com\/oresoftware\/flags-2-env\/clients\/golang$/m, "Go module path for pkg.go.dev indexing"],
    ["clients/golang/lib.go", /#cgo CFLAGS: -I\./, "Go module builds against package-local C sources"],
    ["clients/golang/lib.go", /#include "parser\.h"/, "Go module includes package-local parser header"],
    ["scripts/publish-client.sh", /clients\/golang\/v\$\{PACKAGE_VERSION/, "Go submodule release uses path-prefixed tags"],
  ],
  c: [
    ["Makefile", /^all: shared static cli$/m, "native C build target publishes CLI and libraries"],
    ["packaging/homebrew/Formula/flags2env.rb", /bin\.install "build\/flags2env"/, "Homebrew installs native CLI"],
    ["packaging/homebrew/Formula/flags2env.rb", /lib\.install "build\/libflags2env\.a"/, "Homebrew installs C static library"],
  ],
  cpp: [
    ["clients/cpp/CMakeLists.txt", /add_library\(flags2env_cpp INTERFACE\)/, "C++ package exposes interface target"],
    ["clients/cpp/CMakeLists.txt", /add_library\(flags2env_native STATIC native\/parser\.c\)/, "C++ package builds package-local parser source"],
    ["clients/cpp/CMakeLists.txt", /target_include_directories\(flags2env_cpp INTERFACE include native\)/, "C++ target includes package-local header paths"],
    ["clients/cpp/CMakeLists.txt", /add_test\(NAME flags2env_cpp_smoke/, "C++ CMake registers smoke test"],
  ],
  csharp: [
    ["clients/csharp/Flags2Env.nuspec", /<files>/, "NuGet files list"],
    ["clients/csharp/Flags2Env.nuspec", /native\/parser\.c/, "NuGet includes package-local parser source"],
    ["clients/csharp/Flags2Env.nuspec", /native\/parser\.h/, "NuGet includes package-local parser header"],
    ["clients/csharp/Flags2Env.csproj", /Include="native\/parser\.c"[\s\S]*PackagePath="native\/"/, "dotnet pack includes package-local parser source"],
    ["clients/csharp/Flags2Env.csproj", /Include="native\/parser\.h"[\s\S]*PackagePath="native\/"/, "dotnet pack includes package-local parser header"],
    ["clients/csharp/Flags2EnvTest.cs", /clients\/csharp\/native\/parser\.c/, "C# smoke test can build package-local parser source"],
  ],
  fsharp: [
    ["clients/fsharp/Flags2Env.FSharp.nuspec", /<files>/, "NuGet files list"],
    ["clients/fsharp/Flags2Env.FSharp.nuspec", /native\/parser\.c/, "NuGet includes package-local parser source"],
    ["clients/fsharp/Flags2Env.FSharp.nuspec", /native\/parser\.h/, "NuGet includes package-local parser header"],
    ["clients/fsharp/Flags2Env.FSharp.fsproj", /Include="native\/parser\.c"[\s\S]*PackagePath="native\/"/, "dotnet pack includes package-local parser source"],
    ["clients/fsharp/Flags2Env.FSharp.fsproj", /Include="native\/parser\.h"[\s\S]*PackagePath="native\/"/, "dotnet pack includes package-local parser header"],
    ["clients/fsharp/Flags2EnvTest.fs", /SetDllImportResolver/, "F# smoke test resolves package-local parser library"],
  ],
  php: [
    ["clients/php/composer.json", /"archive"\s*:\s*\{/, "Composer archive controls"],
    ["clients/php/composer.json", /"\/Dockerfile"/, "Composer archive excludes Dockerfile"],
    ["clients/php/composer.json", /"\/publish\.sh"/, "Composer archive excludes publish wrapper"],
    ["clients/php/composer.json", /"\/test\.php"/, "Composer archive excludes tests"],
  ],
  ruby: [
    ["clients/ruby/flags2env.gemspec", /spec\.files\s*=\s*\[/, "RubyGems files list"],
    ["clients/ruby/flags2env.gemspec", /"lib\.rb"/, "RubyGems includes runtime file"],
    ["clients/ruby/flags2env.gemspec", /spec\.files\s*=\s*\[\s*"lib\.rb"\s*\]/, "RubyGems excludes smoke tests"],
  ],
  dart: [
    ["clients/dart/pubspec.yaml", /^description:/m, "pub.dev package description"],
    ["clients/dart/pubspec.yaml", /^repository:/m, "pub.dev repository metadata"],
    ["clients/dart/.pubignore", /^Dockerfile$/m, "pub.dev excludes Dockerfile"],
    ["clients/dart/.pubignore", /^\.dart_tool\/$/m, "pub.dev excludes local Dart tool state"],
    ["clients/dart/.pubignore", /^pubspec\.lock$/m, "pub.dev excludes app lockfile"],
    ["clients/dart/.pubignore", /^test\.dart$/m, "pub.dev excludes test file"],
    ["clients/dart/.pubignore", /^publish\.sh$/m, "pub.dev excludes publish wrapper"],
  ],
  swift: [
    ["Package.swift", /path: "clients\/swift"/, "root SwiftPM manifest points at Swift client"],
    ["Package.swift", /exclude: \["Dockerfile", "Package\.swift", "test\.swift", "publish\.sh"\]/, "root SwiftPM manifest excludes non-runtime files"],
    ["clients/swift/Package.swift", /exclude: \["Dockerfile", "test\.swift", "publish\.sh"\]/, "SwiftPM target excludes non-runtime files"],
    ["scripts/publish-client.sh", /git tag "\$\{PACKAGE_VERSION:\?set PACKAGE_VERSION\}"/, "Swift release uses full semantic version tag"],
  ],
  elixir: [
    ["clients/elixir/mix.exs", /name: "flags2env_elixir"/, "Elixir Hex package name avoids Erlang package collision"],
    ["clients/elixir/mix.exs", /erlc_paths: \["native"\]/, "Elixir package compiles package-local Erlang module"],
    ["clients/elixir/mix.exs", /"native\/flags2env\.erl"/, "Elixir Hex package includes Erlang facade"],
    ["clients/elixir/mix.exs", /"native\/flags2env_nif\.c"/, "Elixir Hex package includes NIF source"],
    ["clients/elixir/mix.exs", /"native\/parser\.c"/, "Elixir Hex package includes parser source"],
    ["clients/elixir/mix.exs", /"native\/parser\.h"/, "Elixir Hex package includes parser header"],
    ["clients/elixir/README.md", /flags2env_elixir/, "Elixir package README documents Hex package name"],
    ["clients/elixir/Dockerfile", /clients\/elixir\/native\/parser\.c/, "Elixir Docker smoke builds package-local parser source"],
  ],
  erlang: [
    ["clients/erlang/rebar.config", /\{files, \["flags2env\.erl", "flags2env_nif\.c", "parser\.c", "parser\.h", "rebar\.config"\]\}/, "Hex package file list"],
    ["clients/erlang/flags2env_nif.c", /#include "parser\.h"/, "Erlang NIF includes package-local parser header"],
    ["clients/erlang/Dockerfile", /clients\/erlang\/parser\.c/, "Erlang Docker smoke builds package-local parser source"],
  ],
  gleam: [
    ["clients/gleam/gleam.toml", /^repository = /m, "Gleam package repository metadata"],
    ["clients/gleam/gleam.toml", /^licences = \["MIT"\]/m, "Gleam package license metadata"],
    ["clients/gleam/Dockerfile", /clients\/erlang\/parser\.c/, "Gleam Docker smoke builds package-local parser source"],
  ],
  haskell: [
    ["clients/haskell/flags2env.cabal", /^extra-source-files:/m, "Cabal source manifest controls"],
    ["clients/haskell/flags2env.cabal", /^  exposed-modules: Flags2Env/m, "Cabal exposes runtime module"],
    ["clients/haskell/flags2env.cabal", /^test-suite flags2env-smoke$/m, "Cabal exposes smoke test suite"],
    ["clients/haskell/flags2env.cabal", /^  main-is: test\.hs$/m, "Cabal smoke test entrypoint"],
  ],
  ocaml: [
    ["clients/ocaml/flags2env.opam", /^build: \[/m, "opam build metadata"],
    ["clients/ocaml/flags2env.opam", /\{with-test\}/, "opam test metadata"],
    ["clients/ocaml/dune-project", /\(package/, "OCaml dune package metadata"],
    ["clients/ocaml/dune", /\(test/, "OCaml dune smoke test"],
  ],
  reasonml: [
    ["clients/reasonml/flags2env.opam", /^build: \[/m, "opam build metadata"],
    ["clients/reasonml/flags2env.opam", /"reason"/, "ReasonML opam Reason syntax dependency"],
    ["clients/reasonml/flags2env.opam", /\{with-test\}/, "ReasonML opam test metadata"],
    ["clients/reasonml/dune-project", /\(package/, "ReasonML dune package metadata"],
    ["clients/reasonml/src/dune", /\(test/, "ReasonML dune smoke test"],
  ],
  perl: [
    ["clients/perl/MANIFEST.SKIP", /^\^blib\//m, "CPAN skips build output"],
    ["clients/perl/MANIFEST.SKIP", /^\^Makefile\$/m, "CPAN skips generated Makefile"],
    ["clients/perl/MANIFEST.SKIP", /^\^MYMETA\\\./m, "CPAN skips generated MYMETA files"],
    ["clients/perl/MANIFEST.SKIP", /^\^publish\\\.sh\$/m, "CPAN skips publish wrapper"],
  ],
  lua: [
    ["clients/lua/flags2env-dev-1.rockspec", /^build = \{/m, "LuaRocks build metadata"],
    ["clients/lua/flags2env-dev-1.rockspec", /flags2env = "clients\/lua\/flags2env\.lua"/, "LuaRocks dev module mapping from repository root"],
    ["clients/lua/flags2env-0.1.0-1.rockspec", /^version = "0\.1\.0-1"$/m, "LuaRocks stable version"],
    ["clients/lua/flags2env-0.1.0-1.rockspec", /tag = "v0\.1\.0"/, "LuaRocks stable source tag"],
    ["clients/lua/flags2env-0.1.0-1.rockspec", /flags2env = "clients\/lua\/flags2env\.lua"/, "LuaRocks stable module mapping from repository root"],
  ],
  nim: [
    ["clients/nim/flags2env.nimble", /^installFiles\s+=\s+@\["flags2env\.nim"\]/m, "Nimble install file list"],
  ],
  r: [
    ["clients/r/.Rbuildignore", /^\^Dockerfile\$$/m, "R build excludes Dockerfile"],
    ["clients/r/.Rbuildignore", /^\^publish\\\.sh\$$/m, "R build excludes publish wrapper"],
    ["clients/r/src/flags2env_r.c", /#include "parser\.h"/, "R staged package includes local parser header"],
    ["clients/r/tests/smoke.R", /parse_flags/, "R package smoke test"],
  ],
  matlab: [
    ["clients/matlab/README.md", /MATLAB bindings use `loadlibrary`/, "MATLAB source-archive usage docs"],
    ["clients/matlab/README.md", /native\/parser\.h/, "MATLAB docs mention package-local loadlibrary header"],
    ["clients/matlab/+flags2env/defaultHeaderPath.m", /native/, "MATLAB default header path is package-local"],
    ["clients/matlab/+flags2env/ensureLoaded.m", /flags2env\.defaultHeaderPath\(\)/, "MATLAB loader uses package-local default header"],
    ["clients/matlab/test.m", /flags2env\.parse/, "MATLAB smoke test"],
    ["scripts/publish-client.sh", /zip -r flags2env-matlab\.zip \+flags2env native README\.md/, "MATLAB publish command archives MATLAB source and native header/source"],
  ],
  julia: [
    ["clients/julia/Project.toml", /^name = "Flags2Env"$/m, "Julia package name"],
    ["clients/julia/Project.toml", /^uuid = "[0-9a-f-]{36}"$/m, "Julia package UUID"],
    ["clients/julia/Project.toml", /^version = "0\.1\.0"$/m, "Julia package version"],
    ["clients/julia/Project.toml", /^\[compat\]/m, "Julia compatibility metadata"],
    ["clients/julia/REGISTRATION.md", /@JuliaRegistrator register subdir=clients\/julia/, "Julia subdir Registrator instruction"],
  ],
  fortran: [
    ["clients/fortran/fpm.toml", /^\[library\]/m, "fpm library metadata"],
    ["clients/fortran/fpm.toml", /^\[\[test\]\]/m, "fpm smoke test metadata"],
  ],
  zig: [
    ["clients/zig/build.zig", /b\.addModule\("flags2env"/, "Zig package module"],
    ["clients/zig/build.zig", /b\.step\("test", "Run Zig smoke tests"\)/, "Zig smoke test target"],
    ["clients/zig/build.zig", /native\/parser\.c/, "Zig package builds against package-local C parser"],
    ["clients/zig/build.zig", /b\.path\("native"\)/, "Zig package uses package-local include path"],
  ],
  crystal: [
    ["clients/crystal/shard.yml", /^name: flags2env$/m, "Shard package name"],
    ["clients/crystal/shard.yml", /^crystal: /m, "Shard Crystal version constraint"],
  ],
  solidity: [
    ["clients/solidity/package.json", /"files"\s*:\s*\[\s*"contracts"\s*\]/, "Solidity npm package files allowlist"],
    ["clients/solidity/package.json", /"solc":/, "Solidity compiler smoke dependency"],
  ],
  bash: [
    ["packaging/homebrew/Formula/flags2env.rb", /clients\/bash\/flags2env\.bash/, "Homebrew installs bash helper"],
  ],
  zsh: [
    ["packaging/homebrew/Formula/flags2env.rb", /clients\/zsh\/flags2env\.zsh/, "Homebrew installs zsh helper"],
  ],
};

const forbiddenPackageContent = {
  csharp: [
    ["clients/csharp/Flags2Env.nuspec", /\.\.\/\.\.\/src|\.\.\/\.\.\/clients/, "C# NuGet spec reaches outside package root"],
    ["clients/csharp/Flags2Env.csproj", /\.\.\/\.\.\/src/, "C# project pack item reaches outside package root"],
    ["clients/csharp/Flags2EnvTest.cs", /build\/libflags2env|tests\/fixtures|\.\.\/\.\.\/tests/, "C# smoke test depends on repo build output or fixture tree"],
  ],
  fsharp: [
    ["clients/fsharp/Flags2Env.FSharp.nuspec", /\.\.\/\.\.\/src|\.\.\/\.\.\/clients/, "F# NuGet spec reaches outside package root"],
    ["clients/fsharp/Flags2Env.FSharp.fsproj", /\.\.\/\.\.\/src/, "F# project pack item reaches outside package root"],
    ["clients/fsharp/Flags2EnvTest.fs", /build\/libflags2env|tests\/fixtures|\.\.\/\.\.\/tests/, "F# smoke test depends on repo build output or fixture tree"],
  ],
  elixir: [
    ["clients/elixir/Dockerfile", /COPY src|COPY tests|src\/parser\.c|tests\/fixtures|clients\/erlang/, "Elixir Docker smoke depends on repo source, fixtures, or Erlang client tree"],
    ["clients/elixir/test.exs", /tests\/fixtures|\.\.\/\.\.\/tests|\.\.\/\.cli-flags\.toml/, "Elixir smoke test depends on repo fixture tree"],
  ],
  java: [
    ["clients/java/pom.xml", /\.\.\/\.\.\/src/, "Java Maven package reaches into repo source directory"],
    ["clients/java/native/flags2env_jni.c", /\.\.\/\.\.\/\.\.\/src\/parser\.h/, "JNI source reaches into repo source directory"],
    ["clients/java/Dockerfile", /COPY src|COPY tests|src\/parser\.c/, "Java Docker smoke depends on repo source or fixture tree"],
  ],
  erlang: [
    ["clients/erlang/flags2env_nif.c", /\.\.\/\.\.\/src\/parser\.h/, "Erlang NIF reaches into repo source directory"],
    ["clients/erlang/Dockerfile", /COPY src|COPY tests|src\/parser\.c|tests\/fixtures/, "Erlang Docker smoke depends on repo source or fixture tree"],
    ["clients/erlang/flags2env_test.erl", /tests\/fixtures|\.\.\/\.\.\/tests/, "Erlang smoke test depends on repo fixture tree"],
  ],
  gleam: [
    ["clients/gleam/Dockerfile", /COPY src|COPY tests|src\/parser\.c|tests\/fixtures/, "Gleam Docker smoke depends on repo source or fixture tree"],
    ["clients/gleam/test.gleam", /\/repo\/tests|tests\/fixtures/, "Gleam smoke test depends on repo fixture tree"],
  ],
  rust: [
    ["clients/rust/Dockerfile", /COPY src|COPY tests|src\/parser\.c|tests\/fixtures|make all|LD_LIBRARY_PATH/, "Rust Docker smoke depends on repo source, fixtures, or build artifacts"],
    ["clients/rust/tests/smoke.rs", /\.\.\/\.\.\/build|tests\/fixtures|\.\.\/\.\.\/tests/, "Rust smoke test depends on repo build output or fixture tree"],
  ],
  cpp: [
    ["clients/cpp/test.cpp", /tests\/fixtures|\.\.\/\.\.\/tests/, "C++ smoke test depends on repo fixture tree"],
  ],
  crystal: [
    ["clients/crystal/test.cr", /tests\/fixtures|\.\.\/\.\.\/tests/, "Crystal smoke test depends on repo fixture tree"],
  ],
  fortran: [
    ["clients/fortran/test.f90", /tests\/fixtures|\.\.\/\.\.\/tests/, "Fortran smoke test depends on repo fixture tree"],
  ],
  haskell: [
    ["clients/haskell/test.hs", /tests\/fixtures|\.\.\/\.\.\/tests/, "Haskell smoke test depends on repo fixture tree"],
  ],
  julia: [
    ["clients/julia/test/runtests.jl", /tests\/fixtures|\.\.\/\.\.\/tests/, "Julia smoke test depends on repo fixture tree"],
  ],
  lua: [
    ["clients/lua/test.lua", /tests\/fixtures|\.\.\/\.\.\/tests/, "Lua smoke test depends on repo fixture tree"],
  ],
  nim: [
    ["clients/nim/test.nim", /tests\/fixtures|\.\.\/\.\.\/tests/, "Nim smoke test depends on repo fixture tree"],
  ],
  ocaml: [
    ["clients/ocaml/test.ml", /tests\/fixtures|\.\.\/\.\.\/tests/, "OCaml smoke test depends on repo fixture tree"],
  ],
  reasonml: [
    ["clients/reasonml/src/Test.re", /tests\/fixtures|\.\.\/\.\.\/tests/, "ReasonML smoke test depends on repo fixture tree"],
  ],
  matlab: [
    ["clients/matlab/+flags2env/apply.m", /fullfile\(pwd, "src", "parser\.h"\)/, "MATLAB apply uses repo-root parser header default"],
    ["clients/matlab/+flags2env/ensureLoaded.m", /fullfile\(pwd, "src", "parser\.h"\)/, "MATLAB loader uses repo-root parser header default"],
    ["clients/matlab/+flags2env/parse.m", /fullfile\(pwd, "src", "parser\.h"\)/, "MATLAB parse uses repo-root parser header default"],
    ["clients/matlab/+flags2env/parseProcess.m", /fullfile\(pwd, "src", "parser\.h"\)/, "MATLAB parseProcess uses repo-root parser header default"],
    ["clients/matlab/README.md", /tests\/fixtures/, "MATLAB README example depends on repo fixture tree"],
  ],
  zig: [
    ["clients/zig/test.zig", /tests\/fixtures|\.\.\/\.\.\/tests/, "Zig smoke test depends on repo fixture tree"],
  ],
};

const matrix = [
  {
    language: "JavaScript",
    client: "nodejs",
    repository: "npm Registry",
    controls: [".npmignore", "package.json"],
    sources: ["clients/nodejs/lib.mjs", "clients/nodejs/lib.cjs", "clients/nodejs/lib.ts", "clients/nodejs/addon.c"],
    tests: ["clients/nodejs/test.mjs", "clients/nodejs/test.cjs", "clients/nodejs/test.ts"],
    publishIncludes: ["npm publish --access public"],
  },
  {
    language: "Python",
    client: "python",
    repository: "PyPI",
    controls: ["clients/python/MANIFEST.in", "clients/python/pyproject.toml"],
    sources: ["clients/python/lib.py", "clients/python/flags2env.py"],
    tests: ["clients/python/test.py"],
    publishIncludes: ["twine upload"],
  },
  {
    language: "Java",
    client: "java",
    repository: "Maven Central / Sonatype",
    controls: ["clients/java/pom.xml"],
    sources: ["clients/java/src/main/java/com/oresoftware/flags2env/Flags2Env.java", "clients/java/native/flags2env_jni.c", "clients/java/native/parser.c", "clients/java/native/parser.h"],
    tests: ["clients/java/src/test/java/com/oresoftware/flags2env/Flags2EnvTest.java"],
    publishIncludes: ["mvn -P release deploy"],
  },
  {
    language: "Kotlin",
    client: "kotlin",
    repository: "Maven Central / Sonatype",
    controls: ["clients/kotlin/build.gradle.kts"],
    sources: ["clients/kotlin/src/main/kotlin/com/oresoftware/flags2env/Flags2Env.kt"],
    tests: [],
    publishIncludes: ["gradle publish", "publish-central-ossrh-compat.sh"],
  },
  {
    language: "Scala",
    client: "scala",
    repository: "Maven Central / Sonatype",
    controls: ["clients/scala/build.sbt", "clients/scala/project/plugins.sbt"],
    sources: ["clients/scala/src/main/scala/com/oresoftware/flags2env/Flags2Env.scala"],
    tests: [],
    publishIncludes: ["sbt publishSigned sonatypeBundleRelease"],
  },
  {
    language: "Groovy",
    client: "groovy",
    repository: "Maven Central / Sonatype",
    controls: ["clients/groovy/build.gradle"],
    sources: ["clients/groovy/src/main/groovy/com/oresoftware/flags2env/Flags2Env.groovy"],
    tests: [],
    publishIncludes: ["gradle publish", "publish-central-ossrh-compat.sh"],
  },
  {
    language: "Clojure",
    client: "clojure",
    repository: "Maven Central / Sonatype",
    controls: ["clients/clojure/build.clj", "clients/clojure/deps.edn"],
    sources: ["clients/clojure/src/com/oresoftware/flags2env.clj"],
    tests: [],
    publishIncludes: ["clojure -T:build", "publish-central-ossrh-compat.sh"],
  },
  {
    language: "Rust",
    client: "rust",
    repository: "crates.io",
    controls: ["clients/rust/Cargo.toml", "clients/rust/Dockerfile"],
    sources: ["clients/rust/src/lib.rs", "clients/rust/native/parser.c", "clients/rust/native/parser.h"],
    tests: ["clients/rust/tests/smoke.rs"],
    publishIncludes: ["cargo publish"],
  },
  {
    language: "Go",
    client: "golang",
    repository: "Git repository / pkg.go.dev",
    controls: ["clients/golang/go.mod"],
    sources: ["clients/golang/lib.go", "clients/golang/parser.c", "clients/golang/parser.h"],
    tests: ["clients/golang/lib_test.go"],
    publishIncludes: ["git tag \"clients/golang/v"],
  },
  {
    language: "C",
    client: "c",
    repository: "Git repository / Homebrew source build",
    controls: ["Makefile", "packaging/homebrew/Formula/flags2env.rb"],
    sources: ["clients/c/lib.c", "clients/c/lib.h", "src/parser.c", "src/parser.h"],
    tests: ["clients/c/test.c"],
    publishIncludes: ["git tag"],
  },
  {
    language: "C++",
    client: "cpp",
    repository: "Git repository / source archive",
    controls: ["clients/cpp/CMakeLists.txt"],
    sources: ["clients/cpp/include/flags2env.hpp", "clients/cpp/native/parser.c", "clients/cpp/native/parser.h"],
    tests: ["clients/cpp/test.cpp"],
    publishIncludes: ["git tag"],
  },
  {
    language: "C#",
    client: "csharp",
    repository: "NuGet Gallery",
    controls: ["clients/csharp/Flags2Env.nuspec", "clients/csharp/Flags2Env.csproj"],
    sources: ["clients/csharp/Flags2Env.cs", "clients/csharp/native/parser.c", "clients/csharp/native/parser.h"],
    tests: ["clients/csharp/Flags2EnvTest.cs"],
    publishIncludes: ["dotnet nuget push"],
  },
  {
    language: "F#",
    client: "fsharp",
    repository: "NuGet Gallery",
    controls: ["clients/fsharp/Flags2Env.FSharp.nuspec", "clients/fsharp/Flags2Env.FSharp.fsproj"],
    sources: ["clients/fsharp/Flags2Env.fs", "clients/fsharp/native/parser.c", "clients/fsharp/native/parser.h"],
    tests: ["clients/fsharp/Flags2EnvTest.fs"],
    publishIncludes: ["dotnet nuget push"],
  },
  {
    language: "PHP",
    client: "php",
    repository: "Packagist",
    controls: ["clients/php/composer.json"],
    sources: ["clients/php/lib.php"],
    tests: ["clients/php/test.php"],
    publishIncludes: ["composer archive"],
  },
  {
    language: "Ruby",
    client: "ruby",
    repository: "RubyGems.org",
    controls: ["clients/ruby/flags2env.gemspec"],
    sources: ["clients/ruby/lib.rb"],
    tests: ["clients/ruby/test.rb"],
    publishIncludes: ["gem push"],
  },
  {
    language: "Swift",
    client: "swift",
    repository: "Git repository / SwiftPM",
    controls: ["Package.swift", "clients/swift/Package.swift"],
    sources: ["clients/swift/lib.swift"],
    tests: ["clients/swift/test.swift"],
    publishIncludes: ["git tag \"${PACKAGE_VERSION"],
  },
  {
    language: "Dart",
    client: "dart",
    repository: "pub.dev",
    controls: ["clients/dart/pubspec.yaml", "clients/dart/.pubignore", "clients/dart/LICENSE", "clients/dart/README.md", "clients/dart/CHANGELOG.md"],
    sources: ["clients/dart/lib.dart", "clients/dart/lib/flags2env.dart"],
    tests: ["clients/dart/test.dart"],
    publishIncludes: ["dart pub publish"],
  },
  {
    language: "Elixir",
    client: "elixir",
    repository: "Hex.pm",
    controls: ["clients/elixir/mix.exs", "clients/elixir/README.md"],
    sources: ["clients/elixir/lib.ex", "clients/elixir/native/flags2env.erl", "clients/elixir/native/flags2env_nif.c", "clients/elixir/native/parser.c", "clients/elixir/native/parser.h"],
    tests: ["clients/elixir/test.exs"],
    publishIncludes: ["mix hex.publish"],
  },
  {
    language: "Erlang",
    client: "erlang",
    repository: "Hex.pm",
    controls: ["clients/erlang/rebar.config"],
    sources: ["clients/erlang/flags2env.erl", "clients/erlang/flags2env_nif.c", "clients/erlang/parser.c", "clients/erlang/parser.h"],
    tests: ["clients/erlang/flags2env_test.erl"],
    publishIncludes: ["rebar3 hex publish"],
  },
  {
    language: "Gleam",
    client: "gleam",
    repository: "Hex.pm",
    controls: ["clients/gleam/gleam.toml"],
    sources: ["clients/gleam/src/flags2env.gleam", "clients/gleam/src/flags2env_native.erl"],
    tests: ["clients/gleam/test.gleam"],
    publishIncludes: ["rebar3 hex publish"],
  },
  {
    language: "Haskell",
    client: "haskell",
    repository: "Hackage",
    controls: ["clients/haskell/flags2env.cabal"],
    sources: ["clients/haskell/src/Flags2Env.hs"],
    tests: ["clients/haskell/test.hs"],
    publishIncludes: ["cabal upload"],
  },
  {
    language: "OCaml",
    client: "ocaml",
    repository: "opam Repository",
    controls: ["clients/ocaml/flags2env.opam", "clients/ocaml/dune-project", "clients/ocaml/dune"],
    sources: ["clients/ocaml/lib/flags2env.ml"],
    tests: ["clients/ocaml/test.ml"],
    publishIncludes: ["opam publish submit"],
  },
  {
    language: "ReasonML",
    client: "reasonml",
    repository: "opam Repository",
    controls: ["clients/reasonml/flags2env.opam", "clients/reasonml/dune-project", "clients/reasonml/src/dune"],
    sources: ["clients/reasonml/src/Flags2Env.re"],
    tests: ["clients/reasonml/src/Test.re"],
    publishIncludes: ["opam publish submit"],
  },
  {
    language: "Perl",
    client: "perl",
    repository: "CPAN",
    controls: ["clients/perl/Makefile.PL", "clients/perl/MANIFEST.SKIP"],
    sources: ["clients/perl/lib/Flags2Env.pm"],
    tests: ["clients/perl/test.pl"],
    publishIncludes: ["cpan-upload"],
  },
  {
    language: "Lua",
    client: "lua",
    repository: "LuaRocks Repository",
    controls: ["clients/lua/flags2env-dev-1.rockspec", "clients/lua/flags2env-0.1.0-1.rockspec"],
    sources: ["clients/lua/flags2env.lua"],
    tests: ["clients/lua/test.lua"],
    publishIncludes: ["luarocks upload"],
  },
  {
    language: "Nim",
    client: "nim",
    repository: "Nimble Package Index",
    controls: ["clients/nim/flags2env.nimble"],
    sources: ["clients/nim/flags2env.nim"],
    tests: ["clients/nim/test.nim"],
    publishIncludes: ["nimble publish"],
  },
  {
    language: "R",
    client: "r",
    repository: "CRAN / R-universe",
    controls: ["clients/r/DESCRIPTION", "clients/r/.Rbuildignore"],
    sources: ["clients/r/R/flags2env.R", "clients/r/src/flags2env_r.c"],
    tests: ["clients/r/tests/smoke.R"],
    publishIncludes: ["submit_cran"],
  },
  {
    language: "MATLAB",
    client: "matlab",
    repository: "Source archive / Git repository",
    controls: ["clients/matlab/README.md", "scripts/publish-client.sh"],
    sources: [
      "clients/matlab/+flags2env/parse.m",
      "clients/matlab/+flags2env/apply.m",
      "clients/matlab/+flags2env/defaultHeaderPath.m",
      "clients/matlab/native/parser.c",
      "clients/matlab/native/parser.h",
    ],
    tests: ["clients/matlab/test.m"],
    publishIncludes: ["zip -r flags2env-matlab.zip"],
  },
  {
    language: "Julia",
    client: "julia",
    repository: "Julia General Registry",
    controls: ["clients/julia/Project.toml", "clients/julia/LICENSE", "clients/julia/README.md", "clients/julia/REGISTRATION.md"],
    sources: ["clients/julia/src/Flags2Env.jl"],
    tests: ["clients/julia/test/runtests.jl"],
    publishIncludes: ["Registrator"],
  },
  {
    language: "Fortran",
    client: "fortran",
    repository: "Git repository / fpm package",
    controls: ["clients/fortran/fpm.toml"],
    sources: ["clients/fortran/src/flags2env.f90"],
    tests: ["clients/fortran/test.f90"],
    publishIncludes: ["git tag"],
  },
  {
    language: "Zig",
    client: "zig",
    repository: "Git repository / Zig package",
    controls: ["clients/zig/build.zig"],
    sources: ["clients/zig/src/flags2env.zig", "clients/zig/native/parser.c", "clients/zig/native/parser.h"],
    tests: ["clients/zig/test.zig"],
    publishIncludes: ["git tag"],
  },
  {
    language: "Crystal",
    client: "crystal",
    repository: "Git repository / Shards",
    controls: ["clients/crystal/shard.yml"],
    sources: ["clients/crystal/src/flags2env.cr"],
    tests: ["clients/crystal/test.cr"],
    publishIncludes: ["git tag"],
  },
  {
    language: "Solidity",
    client: "solidity",
    repository: "npm Registry",
    controls: ["clients/solidity/package.json"],
    sources: ["clients/solidity/contracts/Flags2Env.sol"],
    tests: ["clients/solidity/package.json"],
    publishIncludes: ["npm publish --access public"],
  },
  {
    language: "Bash",
    client: "bash",
    repository: "Homebrew / Git repository",
    controls: ["packaging/homebrew/Formula/flags2env.rb"],
    sources: ["clients/bash/flags2env.bash"],
    tests: ["clients/bash/test.bash"],
    publishIncludes: ["git tag"],
  },
  {
    language: "Zsh",
    client: "zsh",
    repository: "Homebrew / Git repository",
    controls: ["packaging/homebrew/Formula/flags2env.rb"],
    sources: ["clients/zsh/flags2env.zsh"],
    tests: ["clients/zsh/test.zsh"],
    publishIncludes: ["git tag"],
  },
];

let failures = 0;

function requirePath(entry, kind, path) {
  if (!existsSync(join(root, path))) {
    console.error(`${entry.language}: missing ${kind}: ${path}`);
    failures++;
  }
}

function readText(entry, path) {
  const fullPath = join(root, path);
  if (!existsSync(fullPath)) {
    console.error(`${entry.language}: missing package control: ${path}`);
    failures++;
    return "";
  }
  return readFileSync(fullPath, "utf8");
}

function requirePackageControls(entry) {
  const checks = packageControls[entry.client] || [];
  for (const [path, pattern, description] of checks) {
    const text = readText(entry, path);
    if (text && !pattern.test(text)) {
      console.error(`${entry.language}: package control failed (${description}) in ${path}`);
      failures++;
    }
  }
}

function forbidPackageContent(entry) {
  const checks = forbiddenPackageContent[entry.client] || [];
  for (const [path, pattern, description] of checks) {
    const text = readText(entry, path);
    if (text && pattern.test(text)) {
      console.error(`${entry.language}: forbidden package content (${description}) in ${path}`);
      failures++;
    }
  }
}

function requireMatrixCompleteness() {
  const seen = new Map();
  for (const entry of matrix) {
    if (seen.has(entry.client)) {
      console.error(`${entry.language}: duplicate client entry also used by ${seen.get(entry.client)}`);
      failures++;
    }
    seen.set(entry.client, entry.language);
  }

  for (const client of requiredClients) {
    if (!seen.has(client)) {
      console.error(`missing required client in release matrix: ${client}`);
      failures++;
    }
    if (!packageControls[client]) {
      console.error(`missing package-control assertions for required client: ${client}`);
      failures++;
    }
  }

  for (const entry of matrix) {
    const expected = expectedRepositories[entry.client];
    if (expected && entry.repository !== expected) {
      console.error(`${entry.language}: expected repository "${expected}", got "${entry.repository}"`);
      failures++;
    }
  }
}

function dryRunPublish(entry) {
  const result = spawnSync(`clients/${entry.client}/publish.sh`, ["--dry-run"], {
    cwd: root,
    encoding: "utf8",
  });
  if (result.status !== 0) {
    console.error(`${entry.language}: publish dry-run failed`);
    process.stderr.write(result.stderr);
    failures++;
    return;
  }
  for (const expected of entry.publishIncludes) {
    if (!result.stdout.includes(expected)) {
      console.error(`${entry.language}: publish dry-run missing "${expected}"`);
      failures++;
    }
  }
}

requireMatrixCompleteness();

for (const entry of matrix) {
  requirePath(entry, "client directory", `clients/${entry.client}`);
  requirePath(entry, "publish wrapper", `clients/${entry.client}/publish.sh`);
  for (const path of entry.controls) {
    requirePath(entry, "package control", path);
  }
  for (const path of entry.sources) {
    requirePath(entry, "source", path);
  }
  for (const path of entry.tests) {
    requirePath(entry, "test", path);
  }
  requirePackageControls(entry);
  forbidPackageContent(entry);
  dryRunPublish(entry);
}

if (failures > 0) {
  console.error(`release matrix audit failed with ${failures} issue(s)`);
  process.exit(1);
}

console.log(`release matrix audit passed (${matrix.length} entries)`);
