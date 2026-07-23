using System.Text.Json;
using Generated;

const string payload = """
    {
      "PORT": 4242,
      "RATIO": 0.25,
      "DEBUG": true,
      "NAME": "matrix",
      "ITEMS": [1, "two"],
      "LABELS": {"region": "test"},
      "PAYLOAD": {"enabled": true},
      "UNTYPED": "123"
    }
    """;

CliStuff config = JsonSerializer.Deserialize<CliStuff>(payload)
    ?? throw new InvalidOperationException("generated C# config did not deserialize");

if (config.PORT != 4242
    || config.NAME != "matrix"
    || config.UNTYPED != "123"
    || config.LABELS["region"].GetString() != "test")
{
    throw new InvalidOperationException("generated C# config has unexpected values");
}

Console.WriteLine("csharp generated interface passed");
