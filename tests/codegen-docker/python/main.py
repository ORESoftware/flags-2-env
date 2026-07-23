from cli_interfaces import CliStuff


config: CliStuff = {
    "PORT": 4242,
    "RATIO": 0.25,
    "DEBUG": True,
    "NAME": "matrix",
    "ITEMS": [1, "two"],
    "LABELS": {"region": "test"},
    "PAYLOAD": {"enabled": True},
    "UNTYPED": "123",
}

assert config["PORT"] == 4242
assert config["NAME"] == "matrix"
assert config["UNTYPED"] == "123"
assert config["LABELS"]["region"] == "test"

print("python generated interface passed")
