FROM php:8.3-cli

WORKDIR /repo
COPY . .

RUN apt-get update && apt-get install -y --no-install-recommends build-essential make && rm -rf /var/lib/apt/lists/*
RUN make clean && make all

CMD php -d ffi.enable=true clients/php/test.php
