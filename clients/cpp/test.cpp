#include "flags2env.hpp"

#include <cassert>
#include <map>
#include <string>

int main() {
  std::map<std::string, std::string> env{{"PORT", "env"}, {"KEEP", "1"}};
  auto parsed = flags2env::parse_from_file("tests/fixtures/.cli-flags.toml", {"app", "--debug=t", "--port", "8181"});
  assert(parsed["DEBUG"] == "true");
  assert(parsed["PORT"] == "8181");

  auto combined = env;
  for (const auto &pair : flags2env::parse_from_file("tests/fixtures/.cli-flags.toml", {"app", "--port", "8181"})) {
    combined[pair.first] = pair.second;
  }
  assert(combined["PORT"] == "8181");
  assert(combined["KEEP"] == "1");
  return 0;
}
