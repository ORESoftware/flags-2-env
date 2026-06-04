package = "flags2env"
version = "0.1.0-1"
source = {
  url = "git+https://github.com/ORESoftware/flags-2-env.git",
  tag = "v0.1.0"
}
description = {
  summary = "LuaJIT bindings for flags2env",
  detailed = "Thin LuaJIT FFI bindings over the flags2env C ABI.",
  homepage = "https://github.com/ORESoftware/flags-2-env",
  license = "MIT"
}
dependencies = {
  "lua >= 5.1"
}
build = {
  type = "builtin",
  modules = {
    flags2env = "clients/lua/flags2env.lua"
  }
}
