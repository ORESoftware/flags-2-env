FROM gcc:14-bookworm

WORKDIR /repo
COPY . .

RUN make clean && make all
RUN cc -std=c99 -Wall -Wextra -Wpedantic -Iclients/c -Isrc clients/c/test.c clients/c/lib.c src/parser.c -o /tmp/flags2env-c-test

CMD ["/tmp/flags2env-c-test"]
