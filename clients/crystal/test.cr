require "./src/flags2env"

config = "tests/fixtures/.cli-flags.toml"
parsed = Flags2Env.parse(["app", "--debug=t", "--port", "8181"], config)
raise "unexpected parsed map" unless parsed["DEBUG"] == "true" && parsed["PORT"] == "8181"

combined = Flags2Env.apply({"PORT" => "env", "KEEP" => "1"}, ["app", "--port", "8181"], config)
raise "unexpected combined map" unless combined["PORT"] == "8181" && combined["KEEP"] == "1"
