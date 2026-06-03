FROM dart:stable

WORKDIR /repo
COPY . .

RUN apt-get update && apt-get install -y --no-install-recommends build-essential make && rm -rf /var/lib/apt/lists/*
RUN make clean && make all
RUN cd clients/dart && dart pub get

CMD cd clients/dart && dart run test.dart
