using Flags2Env

config_path = tempname() * ".toml"
write(config_path, """
[flags.port]
env = "PORT"
aliases = ["port"]
type = "integer"

[flags.debug]
env = "DEBUG"
aliases = ["debug"]
type = "bool"
true_aliases = ["t"]
""")

parsed = Flags2Env.parse(["app", "--debug=t", "--port", "8181"]; config_path=config_path)
@assert parsed["DEBUG"] == "true"
@assert parsed["PORT"] == "8181"

combined = Flags2Env.apply(Dict("PORT" => "env", "KEEP" => "1"), ["app", "--port", "8181"]; config_path=config_path)
@assert combined["PORT"] == "8181"
@assert combined["KEEP"] == "1"
