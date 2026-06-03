FROM oven/bun:1

WORKDIR /repo
COPY . .

RUN apt-get update && apt-get install -y --no-install-recommends build-essential make && rm -rf /var/lib/apt/lists/*
RUN make clean && make all

ENV FLAGS2ENV_NATIVE_LIB=/repo/build/libflags2env.so
CMD cd clients/bun && bun test.mjs && bun test.cjs && bun test.ts
