require "./src/flags2env"

file = File.tempfile("flags2env-crystal-smoke", ".toml")
config = file.path
file.print <<-TOML
[flags.port]
env = "PORT"
aliases = ["port"]
type = "integer"

[flags.debug]
env = "DEBUG"
aliases = ["debug"]
type = "bool"
true_aliases = ["t"]
TOML
file.close
at_exit { File.delete(config) if File.exists?(config) }

parsed = Flags2Env.parse(["app", "--debug=t", "--port", "8181"], config)
raise "unexpected parsed map" unless parsed["DEBUG"] == "true" && parsed["PORT"] == "8181"

combined = Flags2Env.apply({"PORT" => "env", "KEEP" => "1"}, ["app", "--port", "8181"], config)
raise "unexpected combined map" unless combined["PORT"] == "8181" && combined["KEEP"] == "1"
