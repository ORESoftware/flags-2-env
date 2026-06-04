FROM golang:1.23-bookworm

WORKDIR /repo/clients/golang
COPY clients/golang ./

ENV GOCACHE=/tmp/flags2env-cache/go-build
ENV GOPATH=/tmp/flags2env-cache/go

RUN apt-get update && apt-get install -y --no-install-recommends build-essential make && rm -rf /var/lib/apt/lists/*
RUN useradd --create-home --shell /bin/sh flags2env && \
  mkdir -p /tmp/flags2env-cache && \
  chown -R flags2env:flags2env /repo /tmp/flags2env-cache

ENV HOME=/home/flags2env
ENV XDG_CACHE_HOME=/tmp/flags2env-cache
USER flags2env

CMD go test ./...
