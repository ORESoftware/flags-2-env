FROM swift:6.0

WORKDIR /repo
COPY Makefile ./
COPY src ./src
COPY tests ./tests
COPY clients/swift ./clients/swift

RUN apt-get update && apt-get install -y --no-install-recommends build-essential make && rm -rf /var/lib/apt/lists/*
RUN mkdir -p tests/fixtures/nested/deeper && make clean && make all
RUN swiftc clients/swift/lib.swift clients/swift/test.swift -o /tmp/flags2env-swift-test
RUN useradd --create-home --shell /bin/sh flags2env && \
  mkdir -p /tmp/flags2env-cache && \
  chown -R flags2env:flags2env /repo /tmp/flags2env-cache

ENV HOME=/home/flags2env
ENV XDG_CACHE_HOME=/tmp/flags2env-cache
USER flags2env

CMD cd clients/swift && /tmp/flags2env-swift-test
