-module(flags2env_test).
-export([main/0]).

main() ->
  {ok, Root} = file:get_cwd(),
  ok = file:set_cwd(filename:join([Root, "tests", "fixtures", "nested", "deeper"])),
  Parsed = flags2env:parse(["app", "--debug=t", "--port", "8181"]),
  assert_map("parsed", Parsed, [{<<"DEBUG">>, <<"true">>}, {<<"PORT">>, <<"8181">>}, {<<"COLOR">>, <<"true">>}]),

  Explicit = flags2env:parse(["app", "--debug=f"], "../../.cli-flags.toml"),
  assert_map("explicit", Explicit, [{<<"DEBUG">>, <<"false">>}, {<<"PORT">>, <<"3000">>}]),

  Combined = flags2env:apply(["app", "--port", "8181"], #{<<"PORT">> => <<"env">>, <<"KEEP">> => <<"1">>}),
  assert_map("combined", Combined, [{<<"PORT">>, <<"8181">>}, {<<"KEEP">>, <<"1">>}, {<<"COLOR">>, <<"true">>}]),
  halt(0).

assert_map(Label, Map, Expected) ->
  case lists:all(fun({Key, Value}) -> maps:get(Key, Map, undefined) =:= Value end, Expected) of
    true -> ok;
    false -> io:format("unexpected ~s map: ~p~n", [Label, Map]), halt(1)
  end.
