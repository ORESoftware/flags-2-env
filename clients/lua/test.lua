local ok, Flags2Env = pcall(require, "clients.lua.flags2env")
if not ok then
  Flags2Env = require("flags2env")
end

local flags = Flags2Env.new(os.getenv("FLAGS2ENV_NATIVE_LIB") or "build/libflags2env.so")
local config = os.tmpname()
local file = assert(io.open(config, "w"))
file:write([[
[flags.port]
env = "PORT"
aliases = ["port"]
type = "integer"

[flags.debug]
env = "DEBUG"
aliases = ["debug"]
type = "bool"
true_aliases = ["t"]
]])
file:close()

local parsed = flags:parse({ "app", "--debug=t", "--port", "8181" }, config)
assert(parsed.DEBUG == "true" and parsed.PORT == "8181", "unexpected parsed map")

local combined = flags:apply({ PORT = "env", KEEP = "1" }, { "app", "--port", "8181" }, config)
assert(combined.PORT == "8181" and combined.KEEP == "1", "unexpected combined map")
