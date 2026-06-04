let () =
  let parsed = Flags2env.parse ~config_path:"tests/fixtures/.cli-flags.toml" [ "app"; "--debug=t"; "--port"; "8181" ] in
  let get key = List.assoc key parsed in
  if get "DEBUG" <> "true" || get "PORT" <> "8181" then
    failwith "unexpected parsed map"
