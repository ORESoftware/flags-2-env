# syntax=docker/dockerfile:1

FROM debian:bookworm-slim AS generator

RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential make \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /repo
COPY Makefile ./
COPY src ./src
COPY tests/codegen/.cli-flags.toml /schema/.cli-flags.toml

RUN make cli
RUN mkdir -p /generated \
    && build/flags2env generate typescript /schema/.cli-flags.toml --name CliStuff > /generated/cli-interfaces.ts \
    && build/flags2env generate python /schema/.cli-flags.toml --name CliStuff > /generated/cli_interfaces.py \
    && build/flags2env generate go /schema/.cli-flags.toml --name CliStuff > /generated/cli_config.go \
    && build/flags2env generate rust /schema/.cli-flags.toml --name CliStuff > /generated/cli_config.rs \
    && build/flags2env generate java /schema/.cli-flags.toml --name CliStuff > /generated/CliStuff.java \
    && build/flags2env generate csharp /schema/.cli-flags.toml --name CliStuff > /generated/CliStuff.cs \
    && build/flags2env generate dart /schema/.cli-flags.toml --name CliStuff > /generated/cli_stuff.dart \
    && build/flags2env generate json-schema /schema/.cli-flags.toml --name CliStuff > /generated/cli-stuff.schema.json

FROM node:22-bookworm AS test-nodejs

RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential python3 \
    && rm -rf /var/lib/apt/lists/*

COPY . /package
WORKDIR /package
RUN npm pack --pack-destination /tmp

WORKDIR /test
RUN npm init -y \
    && npm pkg set type=module \
    && npm install --no-audit --no-fund \
      /tmp/oresoftware-f2e-0.1.0.tgz \
      @types/node@22 \
      typescript@5
COPY --from=generator /generated/cli-interfaces.ts ./cli-interfaces.ts
COPY tests/codegen/.cli-flags.toml ./.cli-flags.toml
COPY tests/codegen-docker/nodejs/main.ts ./main.ts
RUN ./node_modules/.bin/tsc \
      --strict \
      --target ES2022 \
      --module NodeNext \
      --moduleResolution NodeNext \
      --outDir dist \
      main.ts \
      cli-interfaces.ts

CMD ["node", "dist/main.js"]

FROM node:22-bookworm-slim AS test-typescript

WORKDIR /test
RUN npm install --no-audit --no-fund --no-save typescript@5
COPY --from=generator /generated/cli-interfaces.ts ./cli-interfaces.ts
COPY tests/codegen-docker/typescript/main.ts ./main.ts
RUN ./node_modules/.bin/tsc \
      --strict \
      --target ES2022 \
      --module commonjs \
      --moduleResolution node \
      --outDir dist \
      main.ts \
      cli-interfaces.ts

CMD ["node", "dist/main.js"]

FROM oven/bun:1 AS test-bun

WORKDIR /test
RUN bun add --dev typescript@5
COPY --from=generator /generated/cli-interfaces.ts ./cli-interfaces.ts
COPY tests/codegen-docker/typescript/runtime.ts ./main.ts
RUN bunx tsc \
      --strict \
      --noEmit \
      --allowImportingTsExtensions \
      --moduleResolution bundler \
      --module preserve \
      main.ts \
      cli-interfaces.ts \
    && bun build main.ts --target bun --outdir dist

CMD ["bun", "run", "dist/main.js"]

FROM denoland/deno:debian AS test-deno

WORKDIR /test
COPY --from=generator /generated/cli-interfaces.ts ./cli-interfaces.ts
COPY tests/codegen-docker/typescript/runtime.ts ./main.ts
RUN deno check main.ts \
    && deno compile --quiet --output /test/codegen-matrix main.ts

CMD ["/test/codegen-matrix"]

FROM golang:1.23-bookworm AS test-golang

WORKDIR /test
COPY --from=generator /generated/cli_config.go ./generated/cli_config.go
COPY tests/codegen-docker/golang/go.mod ./go.mod
COPY tests/codegen-docker/golang/main.go ./main.go
RUN go test ./... \
    && go build -o /test/codegen-matrix .

CMD ["/test/codegen-matrix"]

FROM rust:1-bookworm AS test-rust

WORKDIR /test
COPY --from=generator /generated/cli_config.rs ./src/cli_config.rs
COPY tests/codegen-docker/rust/Cargo.toml ./Cargo.toml
COPY tests/codegen-docker/rust/main.rs ./src/main.rs
RUN cargo generate-lockfile \
    && cargo test --locked \
    && cargo build --locked --release

CMD ["/test/target/release/codegen-matrix"]

FROM dart:stable AS test-dart

WORKDIR /test
COPY --from=generator /generated/cli_stuff.dart ./cli_stuff.dart
COPY tests/codegen-docker/dart/pubspec.yaml ./pubspec.yaml
COPY tests/codegen-docker/dart/main.dart ./main.dart
RUN dart pub get \
    && dart analyze \
    && dart compile exe main.dart -o /test/codegen-matrix

CMD ["/test/codegen-matrix"]

FROM eclipse-temurin:21-jdk AS test-java

WORKDIR /test
COPY --from=generator /generated/CliStuff.java ./generated/CliStuff.java
COPY tests/codegen-docker/java/Main.java ./Main.java
RUN javac -Xlint:all -Werror -d out generated/CliStuff.java Main.java

CMD ["java", "-cp", "out", "Main"]

FROM python:3.13-bookworm AS test-python

WORKDIR /test
RUN python -m pip install --no-cache-dir "mypy>=1.15,<2"
COPY --from=generator /generated/cli_interfaces.py ./cli_interfaces.py
COPY tests/codegen-docker/python/main.py ./main.py
RUN python -m py_compile cli_interfaces.py main.py \
    && mypy --strict cli_interfaces.py main.py

CMD ["python", "main.py"]

FROM mcr.microsoft.com/dotnet/sdk:8.0 AS test-csharp

WORKDIR /test
COPY --from=generator /generated/CliStuff.cs ./CliStuff.cs
COPY tests/codegen-docker/csharp/CodegenMatrix.csproj ./CodegenMatrix.csproj
COPY tests/codegen-docker/csharp/Program.cs ./Program.cs
RUN dotnet build --configuration Release

CMD ["dotnet", "/test/bin/Release/net8.0/CodegenMatrix.dll"]

FROM python:3.13-bookworm AS test-json-schema

WORKDIR /test
RUN python -m pip install --no-cache-dir "jsonschema>=4.23,<5"
COPY --from=generator /generated/cli-stuff.schema.json ./cli-stuff.schema.json
COPY tests/codegen-docker/json-schema/main.py ./main.py
RUN python -m py_compile main.py

CMD ["python", "main.py"]
