import gleam/dict
import flags2env

pub fn main() {
  let parsed = flags2env.parse(["app", "--debug=t", "--port", "8181"])
  case dict_get(parsed, "DEBUG"), dict_get(parsed, "PORT"), dict_get(parsed, "COLOR") {
    "true", "8181", "true" -> Nil
    _, _, _ -> panic as "unexpected parsed map"
  }
}

fn dict_get(map: dict.Dict(String, String), key: String) -> String {
  case dict.get(map, key) {
    Ok(value) -> value
    Error(_) -> ""
  }
}
