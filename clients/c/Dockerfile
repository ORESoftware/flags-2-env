FROM gcc:14-bookworm

WORKDIR /repo
COPY Makefile ./
COPY src ./src
COPY tests ./tests
COPY scripts ./scripts
COPY clients/c ./clients/c

RUN apt-get update && apt-get install -y --no-install-recommends clang && rm -rf /var/lib/apt/lists/*
RUN mkdir -p tests/fixtures/nested/deeper && make clean && make all
RUN make borrow-check
RUN cc -std=c99 -Wall -Wextra -Wpedantic -Iclients/c -Isrc clients/c/test.c clients/c/lib.c src/parser.c -o /tmp/flags2env-c-test
RUN useradd --create-home --shell /bin/sh flags2env && \
  mkdir -p /tmp/flags2env-cache && \
  chown -R flags2env:flags2env /repo /tmp/flags2env-cache

ENV HOME=/home/flags2env
ENV XDG_CACHE_HOME=/tmp/flags2env-cache
USER flags2env

CMD ["/tmp/flags2env-c-test"]
