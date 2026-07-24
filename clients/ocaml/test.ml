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
    failwith "unexpected parsed map";

  let subcommands_path = Filename.temp_file "flags2env-ocaml-subcommands" ".toml" in
  let out = open_out subcommands_path in
  output_string out {|
[flags.verbose]
env = "GITISH_VERBOSE"
aliases = ["verbose"]
type = "bool"

[commands.remote]
help = "Manage remotes."

[commands.remote.commands.add]
help = "Add a remote."

[commands.remote.commands.add.flags.fetch]
env = "GITISH_REMOTE_ADD_FETCH"
aliases = ["fetch"]
short = "f"
type = "bool"
|};
  close_out out;
  let scoped = Flags2env.parse ~config_path:subcommands_path [ "gitish"; "remote"; "add"; "-f" ] in
  let get key = List.assoc key scoped in
  if get "FLAGS2ENV_COMMAND" <> "remote add" || get "GITISH_REMOTE_ADD_FETCH" <> "true" then begin
    Sys.remove subcommands_path;
    failwith "unexpected scoped parse"
  end;
  if not (Flags2env.is_help_requested [ "gitish"; "add"; "--help" ]) then begin
    Sys.remove subcommands_path;
    failwith "help detection failed"
  end;
  if Flags2env.is_help_requested [ "gitish"; "add" ] then begin
    Sys.remove subcommands_path;
    failwith "help false positive"
  end;
  let contains haystack needle =
    let hay_len = String.length haystack and needle_len = String.length needle in
    let rec scan index =
      index + needle_len <= hay_len
      && (String.sub haystack index needle_len = needle || scan (index + 1))
    in
    needle_len = 0 || scan 0
  in
  let scoped_help =
    Flags2env.help_table
      ~config_path:subcommands_path
      ~terminal_columns:100
      ~command:"gitish"
      [ "gitish"; "remote"; "add"; "--help" ]
  in
  let top_help =
    Flags2env.help_table
      ~config_path:subcommands_path
      ~terminal_columns:100
      ~command:"gitish"
      [ "gitish" ]
  in
  Sys.remove subcommands_path;
  if not (contains scoped_help "Command: gitish remote add [OPTIONS]" && contains scoped_help "--fetch") then
    failwith "unexpected scoped help table";
  if not (contains top_help "Commands:" && contains top_help "remote add") then
    failwith "unexpected top-level help table";
  print_endline "ocaml client tests passed"
