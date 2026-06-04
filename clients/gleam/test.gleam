import gleam/dict
import flags2env

pub fn main() {
  let parsed =
    flags2env.parse_with_config(
      ["app", "--debug=t", "--port", "8181"],
      ".cli-flags.toml",
    )
  case dict_get(parsed, "DEBUG"), dict_get(parsed, "PORT") {
    "true", "8181" -> Nil
    _, _ -> panic as "unexpected parsed map"
  }

  let explicit =
    flags2env.parse_with_config(
      ["app", "--debug=f"],
      ".cli-flags.toml",
    )
  case dict_get(explicit, "DEBUG"), dict_get(explicit, "PORT") {
    "false", "3000" -> Nil
    _, _ -> panic as "unexpected explicit config map"
  }

  let combined =
    flags2env.apply(
      ["app", "--port", "8181"],
      dict.from_list([#("PORT", "env"), #("KEEP", "1")]),
    )
  case dict_get(combined, "PORT"), dict_get(combined, "KEEP") {
    "8181", "1" -> Nil
    _, _ -> panic as "unexpected combined map"
  }
}

fn dict_get(map: dict.Dict(String, String), key: String) -> String {
  case dict.get(map, key) {
    Ok(value) -> value
    Error(_) -> ""
  }
}
