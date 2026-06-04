local ffi = require("ffi")

ffi.cdef([[
char *f2e_parse_json_argv(const char *argv_json);
char *f2e_parse_json_argv_from_file(const char *config_path, const char *argv_json);
char *f2e_parse_process(void);
char *f2e_parse_process_from_file(const char *config_path);
void f2e_free(char *value);
]])

local function default_library_name()
  if package.config:sub(1, 1) == "\\" then
    return "flags2env.dll"
  end
  local handle = io.popen("uname -s 2>/dev/null")
  local os_name = handle and handle:read("*l") or ""
  if handle then handle:close() end
  if os_name == "Darwin" then
    return "libflags2env.dylib"
  end
  return "libflags2env.so"
end

local function escape_json(value)
  return '"' .. tostring(value)
    :gsub("\\", "\\\\")
    :gsub('"', '\\"')
    :gsub("\b", "\\b")
    :gsub("\f", "\\f")
    :gsub("\n", "\\n")
    :gsub("\r", "\\r")
    :gsub("\t", "\\t") .. '"'
end

local function argv_json(argv)
  local out = {}
  for i, value in ipairs(argv or {}) do
    out[i] = escape_json(value)
  end
  return "[" .. table.concat(out, ",") .. "]"
end

local function decode_string(raw, index)
  index = index + 1
  local out = {}
  while index <= #raw do
    local ch = raw:sub(index, index)
    if ch == '"' then
      return table.concat(out), index + 1
    end
    if ch == "\\" then
      index = index + 1
      local escaped = raw:sub(index, index)
      local replacements = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
      out[#out + 1] = replacements[escaped] or escaped
    else
      out[#out + 1] = ch
    end
    index = index + 1
  end
  return table.concat(out), index
end

local function decode_object(raw)
  local out = {}
  local index = 1
  while index <= #raw do
    local ch = raw:sub(index, index)
    if ch == '"' then
      local key
      key, index = decode_string(raw, index)
      index = raw:find(":", index, true) or index
      while raw:sub(index, index) ~= '"' and index <= #raw do
        index = index + 1
      end
      local value
      value, index = decode_string(raw, index)
      out[key] = value
    else
      index = index + 1
    end
  end
  return out
end

local Flags2Env = {}
Flags2Env.__index = Flags2Env

function Flags2Env.new(library_path)
  return setmetatable({ lib = ffi.load(library_path or os.getenv("FLAGS2ENV_NATIVE_LIB") or default_library_name()) }, Flags2Env)
end

function Flags2Env:_owned(ptr)
  if ptr == nil then
    return {}
  end
  local raw = ffi.string(ptr)
  self.lib.f2e_free(ptr)
  return decode_object(raw)
end

function Flags2Env:parse(argv, config_path)
  local encoded = argv_json(argv)
  if config_path then
    return self:_owned(self.lib.f2e_parse_json_argv_from_file(config_path, encoded))
  end
  return self:_owned(self.lib.f2e_parse_json_argv(encoded))
end

function Flags2Env:parse_process(config_path)
  if config_path then
    return self:_owned(self.lib.f2e_parse_process_from_file(config_path))
  end
  return self:_owned(self.lib.f2e_parse_process())
end

function Flags2Env:apply(env, argv, config_path)
  local combined = {}
  for key, value in pairs(env or {}) do combined[key] = value end
  for key, value in pairs(self:parse(argv, config_path)) do combined[key] = value end
  return combined
end

return Flags2Env
