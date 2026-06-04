local Flags2Env = require("clients.lua.flags2env")

local flags = Flags2Env.new(os.getenv("FLAGS2ENV_NATIVE_LIB") or "build/libflags2env.so")
local config = "tests/fixtures/.cli-flags.toml"
local parsed = flags:parse({ "app", "--debug=t", "--port", "8181" }, config)
assert(parsed.DEBUG == "true" and parsed.PORT == "8181", "unexpected parsed map")

local combined = flags:apply({ PORT = "env", KEEP = "1" }, { "app", "--port", "8181" }, config)
assert(combined.PORT == "8181" and combined.KEEP == "1", "unexpected combined map")
