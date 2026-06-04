FROM rust:1-bookworm

WORKDIR /repo
COPY clients/rust ./clients/rust

ENV CARGO_HOME=/tmp/flags2env-cache/cargo
ENV CARGO_TARGET_DIR=/tmp/flags2env-cache/cargo-target

RUN apt-get update && apt-get install -y --no-install-recommends build-essential make && rm -rf /var/lib/apt/lists/*
RUN useradd --create-home --shell /bin/sh flags2env && \
  mkdir -p /tmp/flags2env-cache && \
  chown -R flags2env:flags2env /repo /tmp/flags2env-cache

ENV HOME=/home/flags2env
ENV XDG_CACHE_HOME=/tmp/flags2env-cache
USER flags2env

CMD cd clients/rust && cargo test
