open System
open OreSoftware.Flags2Env.FSharp

[<EntryPoint>]
let main _ =
  let configPath =
    match Environment.GetEnvironmentVariable "FLAGS2ENV_FIXTURE" with
    | null | "" -> "tests/fixtures/.cli-flags.toml"
    | value -> value

  let parsed = Flags2Env.parseFromFile configPath [ "app"; "--debug=t"; "--port"; "8181" ]
  if parsed.["DEBUG"] <> "true" || parsed.["PORT"] <> "8181" then
    failwith "unexpected parsed map"

  let env = Map.ofList [ "PORT", "env"; "KEEP", "1" ]
  let parsedOverride = Flags2Env.parseFromFile configPath [ "app"; "--port"; "8181" ]
  let combined = Map.fold (fun acc key value -> Map.add key value acc) env parsedOverride
  if combined.["PORT"] <> "8181" || combined.["KEEP"] <> "1" then
    failwith "unexpected combined map"
  0
