FROM swift:6.0

WORKDIR /repo
COPY . .

RUN apt-get update && apt-get install -y --no-install-recommends build-essential make && rm -rf /var/lib/apt/lists/*
RUN make clean && make all
RUN swiftc clients/swift/lib.swift clients/swift/test.swift -o /tmp/flags2env-swift-test

CMD cd clients/swift && /tmp/flags2env-swift-test
