-module(flags2env_test).
-export([main/0]).

main() ->
  {ok, Root} = file:get_cwd(),
  ok = file:set_cwd(filename:join([Root, "tests", "fixtures", "nested", "deeper"])),
  Parsed = flags2env:parse(["app", "--debug=t", "--port", "8181"]),
  case {maps:get(<<"DEBUG">>, Parsed), maps:get(<<"PORT">>, Parsed), maps:get(<<"COLOR">>, Parsed)} of
    {<<"true">>, <<"8181">>, <<"true">>} -> halt(0);
    _ -> io:format("unexpected parsed map: ~p~n", [Parsed]), halt(1)
  end.
