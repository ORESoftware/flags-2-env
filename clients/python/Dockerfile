FROM python:3.12-bookworm

WORKDIR /repo
COPY . .

RUN apt-get update && apt-get install -y --no-install-recommends build-essential make && rm -rf /var/lib/apt/lists/*
RUN make clean && make all

CMD cd clients/python && python test.py
