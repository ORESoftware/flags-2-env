import gleam/dict.{type Dict}

@external(erlang, "flags2env_native", "parse_process")
pub fn parse_process() -> Dict(String, String)

@external(erlang, "flags2env_native", "parse_process")
pub fn parse_process_with_config(config_path: String) -> Dict(String, String)

@external(erlang, "flags2env_native", "parse")
pub fn parse(argv: List(String)) -> Dict(String, String)

@external(erlang, "flags2env_native", "parse")
pub fn parse_with_config(argv: List(String), config_path: String) -> Dict(String, String)

@external(erlang, "flags2env_native", "env_map")
pub fn env_map() -> Dict(String, String)

pub fn apply_process(env: Dict(String, String)) -> Dict(String, String) {
  dict.fold(parse_process(), env, fn(combined, key, value) {
    dict.insert(combined, key, value)
  })
}

pub fn apply(argv: List(String), env: Dict(String, String)) -> Dict(String, String) {
  dict.fold(parse(argv), env, fn(combined, key, value) {
    dict.insert(combined, key, value)
  })
}
