import os
from pathlib import Path
from tempfile import TemporaryDirectory

from flags2env import Flags2Env
from lib import _default_library_name, _resolve_library_path


with TemporaryDirectory() as directory:
    root = Path(directory)
    platform_library = root / _default_library_name()
    platform_library.touch()

    for canonical_name in (
        "libflags2env.dylib",
        "libflags2env.so",
        "flags2env.dll",
    ):
        requested = root / canonical_name
        expected = requested if requested == platform_library else platform_library
        assert Path(_resolve_library_path(str(requested))) == expected

    custom_path = root / "custom-flags2env.so"
    assert _resolve_library_path(str(custom_path)) == str(custom_path)


sdk = Flags2Env(f"../../build/{_default_library_name()}")

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

coerced = sdk.coerce(
    {"GITISH_COMMAND": "remote add", "GITISH_CMD_ADD": "true", "GITISH_REMOTE_ADD_FETCH": "true"},
    subcommands_config,
)
assert coerced["GITISH_COMMAND"] == "remote add", coerced
assert coerced["GITISH_CMD_ADD"] is True, coerced
assert coerced["GITISH_REMOTE_ADD_FETCH"] is True, coerced

try:
    sdk.coerce({"GITISH_COMMAND": 42}, subcommands_config)
    raise AssertionError("expected CoercionError")
except Exception as error:
    assert "command_env" in str(error), error

generated = sdk.generate_types("typescript", "GitishConfig", subcommands_config)
assert "GITISH_COMMAND?: string;" in generated, generated
assert "GITISH_CMD_ADD?: boolean;" in generated, generated

print("python client extended tests passed")
