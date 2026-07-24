# syntax=docker/dockerfile:1
# Builds the C core from a clean checkout and runs the full CLI test suite
# (including the subcommand suites) inside Linux containers, covering both
# glibc and musl toolchains.

FROM debian:bookworm-slim AS test-debian

RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential make git zsh \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /repo
COPY Makefile .cli-flags.toml ./
COPY src ./src
COPY scripts/audit-changed-cli-flags.sh ./scripts/audit-changed-cli-flags.sh
COPY clients/bash ./clients/bash
COPY clients/zsh ./clients/zsh
COPY tests ./tests

RUN make cli \
    && cc -std=c99 -Wall -Wextra -Wpedantic -O2 -Isrc src/parser.c tests/api_hardening.c -o build/api-hardening

CMD ["sh", "-ec", "./tests/run.sh && ./build/api-hardening"]

FROM alpine:3.20 AS test-alpine

RUN apk add --no-cache build-base make bash zsh git

WORKDIR /repo
COPY Makefile .cli-flags.toml ./
COPY src ./src
COPY scripts/audit-changed-cli-flags.sh ./scripts/audit-changed-cli-flags.sh
COPY clients/bash ./clients/bash
COPY clients/zsh ./clients/zsh
COPY tests ./tests

RUN make cli \
    && cc -std=c99 -Wall -Wextra -Wpedantic -O2 -Isrc src/parser.c tests/api_hardening.c -o build/api-hardening

CMD ["sh", "-ec", "./tests/run.sh && ./build/api-hardening"]
