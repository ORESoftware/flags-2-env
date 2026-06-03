FROM gcc:14-bookworm

WORKDIR /repo
COPY . .

RUN apt-get update && apt-get install -y --no-install-recommends clang && rm -rf /var/lib/apt/lists/*
RUN make clean && make all
RUN make borrow-check
RUN cc -std=c99 -Wall -Wextra -Wpedantic -Iclients/c -Isrc clients/c/test.c clients/c/lib.c src/parser.c -o /tmp/flags2env-c-test

CMD ["/tmp/flags2env-c-test"]
