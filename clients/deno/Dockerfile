FROM denoland/deno:debian

USER root
WORKDIR /repo
COPY Makefile ./
COPY src ./src
COPY tests ./tests
COPY clients/deno ./clients/deno

ENV DENO_DIR=/tmp/flags2env-cache/deno

RUN apt-get update && apt-get install -y --no-install-recommends build-essential make && rm -rf /var/lib/apt/lists/*
RUN mkdir -p tests/fixtures/nested/deeper && make clean && make all
RUN useradd --create-home --shell /bin/sh flags2env && \
  mkdir -p /tmp/flags2env-cache && \
  chown -R flags2env:flags2env /repo /tmp/flags2env-cache

ENV HOME=/home/flags2env
ENV XDG_CACHE_HOME=/tmp/flags2env-cache
USER flags2env

CMD cd clients/deno && deno run --allow-ffi=/repo/build/libflags2env.so --allow-read=/repo test.ts
