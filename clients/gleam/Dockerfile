FROM ghcr.io/gleam-lang/gleam:v1.14.0-erlang

WORKDIR /repo
COPY . .

RUN apt-get update && apt-get install -y --no-install-recommends build-essential make && rm -rf /var/lib/apt/lists/*
RUN make clean && make all
RUN mkdir -p /tmp/beam/ebin /tmp/beam/priv /tmp/gleam/src /tmp/erlang_libs/flags2env_native/ebin /tmp/erlang_libs/flags2env_native/priv
RUN erlc -o /tmp/beam/ebin clients/gleam/flags2env_native.erl && cp /tmp/beam/ebin/flags2env_native.beam /tmp/erlang_libs/flags2env_native/ebin/
RUN ERL_INCLUDE="$(erl -noshell -eval 'io:format("~s/erts-~s/include", [code:root_dir(), erlang:system_info(version)]), halt().')" && \
  cc -std=c99 -DF2E_BEAM_MODULE_NATIVE -fPIC -shared -I"$ERL_INCLUDE" clients/erlang/flags2env_nif.c src/parser.c -o /tmp/beam/priv/flags2env_nif.so && \
  cp /tmp/beam/priv/flags2env_nif.so /tmp/erlang_libs/flags2env_native/priv/
RUN cp clients/gleam/lib.gleam /tmp/gleam/src/flags2env.gleam && cp clients/gleam/test.gleam /tmp/gleam/src/main.gleam
RUN cp tests/fixtures/.cli-flags.toml /tmp/gleam/.cli-flags.toml
RUN printf 'name = "flags2env_test"\nversion = "1.0.0"\n\n[dependencies]\ngleam_stdlib = ">= 0.34.0 and < 2.0.0"\n' > /tmp/gleam/gleam.toml
RUN cd /tmp/gleam && gleam deps download

CMD cd /tmp/gleam && ERL_LIBS="/tmp/erlang_libs" ERL_FLAGS="-pa /tmp/beam/ebin" gleam run -m main
