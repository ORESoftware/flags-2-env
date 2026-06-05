let () =
  let config_path = Filename.temp_file "flags2env-ocaml-smoke" ".toml" in
  let out = open_out config_path in
  output_string out {|
[flags.port]
env = "PORT"
aliases = ["port"]
type = "integer"

[flags.debug]
env = "DEBUG"
aliases = ["debug"]
type = "bool"
true_aliases = ["t"]
|};
  close_out out;
  let parsed = Flags2env.parse ~config_path [ "app"; "--debug=t"; "--port"; "8181" ] in
  Sys.remove config_path;
  let get key = List.assoc key parsed in
  if get "DEBUG" <> "true" || get "PORT" <> "8181" then
    failwith "unexpected parsed map"
