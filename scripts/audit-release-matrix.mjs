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
    ["clients/java/pom.xml", /<include>parser\.c<\/include>/, "Maven package includes parser.c"],
    ["clients/java/pom.xml", /<include>parser\.h<\/include>/, "Maven package includes parser.h"],
    ["clients/java/pom.xml", /<excludes>[\s\S]*<exclude>\*\*\/publish\.sh<\/exclude>/, "Maven resources exclude publish wrappers"],
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
    ["clients/rust/Cargo.toml", /"src\/\*\*"/, "Cargo includes Rust source"],
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
    ["clients/cpp/CMakeLists.txt", /target_include_directories\(flags2env_cpp INTERFACE include \.\.\/\.\.\/src\)/, "C++ target includes header paths"],
  ],
  csharp: [
    ["clients/csharp/Flags2Env.nuspec", /<files>/, "NuGet files list"],
    ["clients/csharp/Flags2Env.nuspec", /exclude="[^"]*\.\.\/\.\.\/clients\/\*\*/, "NuGet excludes other clients"],
  ],
  fsharp: [
    ["clients/fsharp/Flags2Env.FSharp.nuspec", /<files>/, "NuGet files list"],
    ["clients/fsharp/Flags2Env.FSharp.nuspec", /exclude="[^"]*\.\.\/\.\.\/clients\/\*\*/, "NuGet excludes other clients"],
  ],
  php: [
    ["clients/php/composer.json", /"archive"\s*:\s*\{/, "Composer archive controls"],
    ["clients/php/composer.json", /"\/Dockerfile"/, "Composer archive excludes Dockerfile"],
    ["clients/php/composer.json", /"\/test\.php"/, "Composer archive excludes tests"],
  ],
  ruby: [
    ["clients/ruby/flags2env.gemspec", /spec\.files\s*=\s*\[/, "RubyGems files list"],
    ["clients/ruby/flags2env.gemspec", /"lib\.rb"/, "RubyGems includes runtime file"],
  ],
  dart: [
    ["clients/dart/.pubignore", /^Dockerfile$/m, "pub.dev excludes Dockerfile"],
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
    ["clients/elixir/mix.exs", /files: \["lib\.ex", "README\.md", "mix\.exs"\]/, "Hex package file list"],
  ],
  erlang: [
    ["clients/erlang/rebar.config", /\{files, \["flags2env\.erl", "flags2env_nif\.c", "rebar\.config"\]\}/, "Hex package file list"],
  ],
  gleam: [
    ["clients/gleam/gleam.toml", /^repository = /m, "Gleam package repository metadata"],
    ["clients/gleam/gleam.toml", /^licences = \["MIT"\]/m, "Gleam package license metadata"],
  ],
  haskell: [
    ["clients/haskell/flags2env.cabal", /^extra-source-files:/m, "Cabal source manifest controls"],
    ["clients/haskell/flags2env.cabal", /^  exposed-modules: Flags2Env/m, "Cabal exposes runtime module"],
  ],
  ocaml: [
    ["clients/ocaml/flags2env.opam", /^build: \[/m, "opam build metadata"],
    ["clients/ocaml/dune-project", /\(package/, "OCaml dune package metadata"],
  ],
  reasonml: [
    ["clients/reasonml/flags2env.opam", /^build: \[/m, "opam build metadata"],
    ["clients/reasonml/dune-project", /\(package/, "ReasonML dune package metadata"],
  ],
  perl: [
    ["clients/perl/MANIFEST.SKIP", /^\^blib\//m, "CPAN skips build output"],
    ["clients/perl/MANIFEST.SKIP", /^\^Makefile\$/m, "CPAN skips generated Makefile"],
  ],
  lua: [
    ["clients/lua/flags2env-dev-1.rockspec", /^build = \{/m, "LuaRocks build metadata"],
    ["clients/lua/flags2env-dev-1.rockspec", /flags2env = "flags2env\.lua"/, "LuaRocks module mapping"],
  ],
  nim: [
    ["clients/nim/flags2env.nimble", /^installFiles\s+=\s+@\["flags2env\.nim"\]/m, "Nimble install file list"],
  ],
  r: [
    ["clients/r/.Rbuildignore", /^\^Dockerfile\$$/m, "R build excludes Dockerfile"],
    ["clients/r/.Rbuildignore", /^\^publish\\\.sh\$$/m, "R build excludes publish wrapper"],
  ],
  matlab: [
    ["clients/matlab/README.md", /MATLAB bindings use `loadlibrary`/, "MATLAB source-archive usage docs"],
    ["scripts/publish-client.sh", /zip -r flags2env-matlab\.zip \+flags2env README\.md/, "MATLAB publish command archives only MATLAB source"],
  ],
  julia: [
    ["clients/julia/Project.toml", /^name = "Flags2Env"$/m, "Julia package name"],
    ["clients/julia/Project.toml", /^\[compat\]/m, "Julia compatibility metadata"],
  ],
  fortran: [
    ["clients/fortran/fpm.toml", /^\[library\]/m, "fpm library metadata"],
    ["clients/fortran/fpm.toml", /^\[\[test\]\]/m, "fpm smoke test metadata"],
  ],
  zig: [
    ["clients/zig/build.zig", /b\.addModule\("flags2env"/, "Zig package module"],
    ["clients/zig/build.zig", /b\.step\("test", "Run Zig smoke tests"\)/, "Zig smoke test target"],
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
    sources: ["clients/java/src/main/java/com/oresoftware/flags2env/Flags2Env.java", "clients/java/native/flags2env_jni.c"],
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
    controls: ["clients/rust/Cargo.toml"],
    sources: ["clients/rust/src/lib.rs"],
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
    sources: ["clients/cpp/include/flags2env.hpp"],
    tests: ["clients/cpp/test.cpp"],
    publishIncludes: ["git tag"],
  },
  {
    language: "C#",
    client: "csharp",
    repository: "NuGet Gallery",
    controls: ["clients/csharp/Flags2Env.nuspec", "clients/csharp/Flags2Env.csproj"],
    sources: ["clients/csharp/Flags2Env.cs"],
    tests: ["clients/csharp/Flags2EnvTest.cs"],
    publishIncludes: ["dotnet nuget push"],
  },
  {
    language: "F#",
    client: "fsharp",
    repository: "NuGet Gallery",
    controls: ["clients/fsharp/Flags2Env.FSharp.nuspec", "clients/fsharp/Flags2Env.FSharp.fsproj"],
    sources: ["clients/fsharp/Flags2Env.fs"],
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
    controls: ["clients/dart/pubspec.yaml", "clients/dart/.pubignore"],
    sources: ["clients/dart/lib.dart", "clients/dart/lib/flags2env.dart"],
    tests: ["clients/dart/test.dart"],
    publishIncludes: ["dart pub publish"],
  },
  {
    language: "Elixir",
    client: "elixir",
    repository: "Hex.pm",
    controls: ["clients/elixir/mix.exs"],
    sources: ["clients/elixir/lib.ex"],
    tests: ["clients/elixir/test.exs"],
    publishIncludes: ["mix hex.publish"],
  },
  {
    language: "Erlang",
    client: "erlang",
    repository: "Hex.pm",
    controls: ["clients/erlang/rebar.config"],
    sources: ["clients/erlang/flags2env.erl", "clients/erlang/flags2env_nif.c"],
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
    controls: ["clients/ocaml/flags2env.opam", "clients/ocaml/dune-project"],
    sources: ["clients/ocaml/lib/flags2env.ml"],
    tests: ["clients/ocaml/test.ml"],
    publishIncludes: ["opam publish submit"],
  },
  {
    language: "ReasonML",
    client: "reasonml",
    repository: "opam Repository",
    controls: ["clients/reasonml/flags2env.opam", "clients/reasonml/dune-project"],
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
    controls: ["clients/lua/flags2env-dev-1.rockspec"],
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
    tests: [],
    publishIncludes: ["submit_cran"],
  },
  {
    language: "MATLAB",
    client: "matlab",
    repository: "Source archive / Git repository",
    controls: ["clients/matlab/README.md"],
    sources: ["clients/matlab/+flags2env/parse.m", "clients/matlab/+flags2env/apply.m"],
    tests: [],
    publishIncludes: ["zip -r flags2env-matlab.zip"],
  },
  {
    language: "Julia",
    client: "julia",
    repository: "Julia General Registry",
    controls: ["clients/julia/Project.toml"],
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
    sources: ["clients/zig/src/flags2env.zig"],
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
  dryRunPublish(entry);
}

if (failures > 0) {
  console.error(`release matrix audit failed with ${failures} issue(s)`);
  process.exit(1);
}

console.log(`release matrix audit passed (${matrix.length} entries)`);
