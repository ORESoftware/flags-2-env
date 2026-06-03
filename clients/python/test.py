import os
import platform

from flags2env import Flags2Env


suffix = "dylib" if platform.system() == "Darwin" else "dll" if platform.system() == "Windows" else "so"
sdk = Flags2Env(f"../../build/libflags2env.{suffix}")

os.chdir("../../tests/fixtures/nested/deeper")
parsed = sdk.parse(["app", "--debug=t", "--port", "8181"])

assert parsed["DEBUG"] == "true", parsed
assert parsed["PORT"] == "8181", parsed
assert parsed["COLOR"] == "true", parsed

explicit = sdk.parse(["app", "--debug=f"], "../../.cli-flags.toml")
assert explicit["DEBUG"] == "false", explicit
assert explicit["PORT"] == "3000", explicit

combined = sdk.apply({"PORT": "env", "KEEP": "1"}, ["app", "--port", "8181"])
assert combined["PORT"] == "8181", combined
assert combined["KEEP"] == "1", combined
assert combined["COLOR"] == "true", combined
