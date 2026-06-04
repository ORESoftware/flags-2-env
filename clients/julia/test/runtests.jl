using Flags2Env

parsed = Flags2Env.parse(["app", "--debug=t", "--port", "8181"]; config_path="tests/fixtures/.cli-flags.toml")
@assert parsed["DEBUG"] == "true"
@assert parsed["PORT"] == "8181"

combined = Flags2Env.apply(Dict("PORT" => "env", "KEEP" => "1"), ["app", "--port", "8181"]; config_path="tests/fixtures/.cli-flags.toml")
@assert combined["PORT"] == "8181"
@assert combined["KEEP"] == "1"
