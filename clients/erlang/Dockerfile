FROM erlang:27

WORKDIR /repo
COPY . .

RUN apt-get update && apt-get install -y --no-install-recommends build-essential make && rm -rf /var/lib/apt/lists/*
RUN make clean && make all
RUN mkdir -p /tmp/beam/ebin /tmp/beam/priv
RUN erlc -o /tmp/beam/ebin clients/erlang/flags2env.erl clients/erlang/flags2env_test.erl
RUN ERL_INCLUDE="$(erl -noshell -eval 'io:format("~s/erts-~s/include", [code:root_dir(), erlang:system_info(version)]), halt().')" && \
  cc -std=c99 -fPIC -shared -I"$ERL_INCLUDE" clients/erlang/flags2env_nif.c src/parser.c -o /tmp/beam/priv/flags2env_nif.so

CMD erl -noshell -pa /tmp/beam/ebin -s flags2env_test main -s init stop
