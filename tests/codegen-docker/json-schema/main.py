import json
from pathlib import Path

from jsonschema import Draft202012Validator
from jsonschema.exceptions import ValidationError


schema = json.loads(Path("cli-stuff.schema.json").read_text(encoding="utf-8"))
Draft202012Validator.check_schema(schema)
validator = Draft202012Validator(schema)

assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
assert schema["x-flags2env-stage"] == "coerced"
assert schema["properties"]["PORT"]["x-flags2env-type"] == "integer"
assert schema["properties"]["UNTYPED"]["default"] == "123"
assert schema["properties"]["UNTYPED"]["x-flags2env-type"] == "string"

valid = {
    "PORT": 4242,
    "RATIO": 0.25,
    "DEBUG": True,
    "NAME": "matrix",
    "ITEMS": [1, "two"],
    "LABELS": {"region": "test"},
    "PAYLOAD": {"enabled": True},
    "UNTYPED": "123",
}
validator.validate(valid)

invalid_instances = (
    {**valid, "PORT": "not-an-integer"},
    {key: value for key, value in valid.items() if key != "PORT"},
    {**valid, "UNDECLARED": "value"},
)
for invalid in invalid_instances:
    try:
        validator.validate(invalid)
    except ValidationError:
        pass
    else:
        raise AssertionError(f"generated JSON Schema accepted invalid config: {invalid}")

print("json-schema generated interface passed")
