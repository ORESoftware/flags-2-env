#include "flags2env.hpp"

#include <cassert>
#include <cstdio>
#include <fstream>
#include <map>
#include <string>

int main() {
  const std::string config = "flags2env-cpp-smoke.toml";
  std::ofstream(config) << R"([flags.port]
env = "PORT"
aliases = ["port"]
type = "integer"

[flags.debug]
env = "DEBUG"
aliases = ["debug"]
type = "bool"
true_aliases = ["t"]
)";

  std::map<std::string, std::string> env{{"PORT", "env"}, {"KEEP", "1"}};
  auto parsed = flags2env::parse_from_file(config, {"app", "--debug=t", "--port", "8181"});
  assert(parsed["DEBUG"] == "true");
  assert(parsed["PORT"] == "8181");

  auto combined = env;
  for (const auto &pair : flags2env::parse_from_file(config, {"app", "--port", "8181"})) {
    combined[pair.first] = pair.second;
  }
  assert(combined["PORT"] == "8181");
  assert(combined["KEEP"] == "1");
  std::remove(config.c_str());
  return 0;
}
