FROM denoland/deno:debian

USER root
WORKDIR /repo
COPY . .

RUN apt-get update && apt-get install -y --no-install-recommends build-essential make && rm -rf /var/lib/apt/lists/*
RUN make clean && make all

CMD cd clients/deno && deno run --allow-ffi --allow-read --allow-env test.ts
