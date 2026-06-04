FROM oven/bun:1

WORKDIR /repo
COPY Makefile ./
COPY src ./src
COPY tests ./tests
COPY clients/bun ./clients/bun

RUN apt-get update && apt-get install -y --no-install-recommends build-essential make && rm -rf /var/lib/apt/lists/*
RUN mkdir -p tests/fixtures/nested/deeper && make clean && make all
RUN useradd --create-home --shell /bin/sh flags2env && \
  mkdir -p /tmp/flags2env-cache && \
  chown -R flags2env:flags2env /repo /tmp/flags2env-cache

ENV HOME=/home/flags2env
ENV XDG_CACHE_HOME=/tmp/flags2env-cache
ENV FLAGS2ENV_NATIVE_LIB=/repo/build/libflags2env.so
USER flags2env

CMD cd clients/bun && bun test.mjs && bun test.cjs && bun test.ts
