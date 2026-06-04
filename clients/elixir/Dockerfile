FROM elixir:1.17-otp-27

WORKDIR /repo
COPY clients/elixir ./clients/elixir

RUN apt-get update && apt-get install -y --no-install-recommends build-essential make && rm -rf /var/lib/apt/lists/*
RUN mkdir -p /tmp/beam/ebin /tmp/beam/priv
RUN erlc -o /tmp/beam/ebin clients/elixir/native/flags2env.erl
RUN elixirc -pa /tmp/beam/ebin clients/elixir/lib.ex -o /tmp/beam/ebin
RUN ERL_INCLUDE="$(erl -noshell -eval 'io:format("~s/erts-~s/include", [code:root_dir(), erlang:system_info(version)]), halt().')" && \
  cc -std=c99 -fPIC -shared -I"$ERL_INCLUDE" -Iclients/elixir/native clients/elixir/native/flags2env_nif.c clients/elixir/native/parser.c -o /tmp/beam/priv/flags2env_nif.so
RUN useradd --create-home --shell /bin/sh flags2env && \
  mkdir -p /tmp/flags2env-cache && \
  chown -R flags2env:flags2env /repo /tmp/beam /tmp/flags2env-cache

ENV HOME=/home/flags2env
ENV XDG_CACHE_HOME=/tmp/flags2env-cache
USER flags2env

CMD cd clients/elixir && elixir -pa /tmp/beam/ebin test.exs
