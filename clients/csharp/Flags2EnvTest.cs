using System;
using System.Collections.Generic;

namespace OreSoftware.Flags2Env
{
    internal static class Flags2EnvTest
    {
        private static void Main()
        {
            string nativeLibrary = Environment.GetEnvironmentVariable("FLAGS2ENV_NATIVE_LIB") ?? "build/libflags2env.so";
            string configPath = Environment.GetEnvironmentVariable("FLAGS2ENV_FIXTURE") ?? "tests/fixtures/.cli-flags.toml";

            using var flags = new Flags2Env(nativeLibrary);
            var parsed = flags.Parse(new[] { "app", "--debug=t", "--port", "8181" }, configPath);
            if (parsed["DEBUG"] != "true" || parsed["PORT"] != "8181")
            {
                throw new Exception("unexpected parsed map");
            }

            var env = new Dictionary<string, string> { ["PORT"] = "env", ["KEEP"] = "1" };
            var combined = flags.Apply(env, new[] { "app", "--port", "8181" }, configPath);
            if (combined["PORT"] != "8181" || combined["KEEP"] != "1")
            {
                throw new Exception("unexpected combined map");
            }
        }
    }
}
