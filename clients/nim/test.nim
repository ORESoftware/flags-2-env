import std/json
import ./flags2env

let parsed = parseFromFile("tests/fixtures/.cli-flags.toml", @["app", "--debug=t", "--port", "8181"])
doAssert parsed["DEBUG"].getStr() == "true"
doAssert parsed["PORT"].getStr() == "8181"
