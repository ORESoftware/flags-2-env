import std/json
import ./flags2env

let config = "flags2env-nim-smoke.toml"
writeFile(config, """
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

let parsed = parseFromFile(config, @["app", "--debug=t", "--port", "8181"])
doAssert parsed["DEBUG"].getStr() == "true"
doAssert parsed["PORT"].getStr() == "8181"
