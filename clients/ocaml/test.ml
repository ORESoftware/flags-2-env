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
  let coerced =
    Flags2env.coerce
      ~config_path:subcommands_path
      [ ("FLAGS2ENV_COMMAND", `String "remote add"); ("GITISH_REMOTE_ADD_FETCH", `String "true") ]
  in
  let coerce_rejected =
    match Flags2env.coerce ~config_path:subcommands_path [ ("FLAGS2ENV_COMMAND", `Int 42) ] with
    | _ -> false
    | exception Flags2env.Coercion_error _ -> true
  in
  let generated =
    Flags2env.generate_types ~config_path:subcommands_path ~type_name:"GitishConfig" "typescript"
  in
  Sys.remove subcommands_path;
  if List.assoc "FLAGS2ENV_COMMAND" coerced <> `String "remote add"
     || List.assoc "GITISH_REMOTE_ADD_FETCH" coerced <> `Bool true then
    failwith "unexpected coerced map";
  if not coerce_rejected then failwith "expected coercion error";
  if not (contains scoped_help "Command: gitish remote add [OPTIONS]" && contains scoped_help "--fetch") then
    failwith "unexpected scoped help table";
  if not (contains top_help "Commands:" && contains top_help "remote add") then
    failwith "unexpected top-level help table";
  if not (contains generated "FLAGS2ENV_COMMAND?: string;") then
    failwith "unexpected generated types";
  print_endline "ocaml client tests passed"
