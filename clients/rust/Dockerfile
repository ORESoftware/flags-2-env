FROM rust:1-bookworm

WORKDIR /repo
COPY . .

RUN apt-get update && apt-get install -y --no-install-recommends build-essential make && rm -rf /var/lib/apt/lists/*
RUN make clean && make all

ENV LD_LIBRARY_PATH=/repo/build
CMD cd clients/rust && cargo test
