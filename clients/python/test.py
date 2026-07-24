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

subcommands_config = "../../../subcommands/.cli-flags.toml"
scoped = sdk.parse(["gitish", "add", "-A"], subcommands_config)
assert scoped["GITISH_COMMAND"] == "add", scoped
assert scoped["GITISH_ADD_ALL"] == "true", scoped

assert sdk.is_help_requested(["gitish", "add", "--help"]) is True
assert sdk.is_help_requested(["gitish", "add"]) is False

scoped_help = sdk.help_table(
    "gitish",
    ["gitish", "remote", "add", "--help"],
    subcommands_config,
    terminal_columns=100,
)
assert "Command: gitish remote add [OPTIONS]" in scoped_help, scoped_help
assert "--fetch" in scoped_help, scoped_help

top_help = sdk.help_table("gitish", ["gitish"], subcommands_config, terminal_columns=100)
assert "Commands:" in top_help, top_help
assert "remote add" in top_help, top_help

print("python client tests passed")
