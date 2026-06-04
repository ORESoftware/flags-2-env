using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;

namespace OreSoftware.Flags2Env
{
    internal static class Flags2EnvTest
    {
        private static void Main()
        {
            string nativeLibrary = Environment.GetEnvironmentVariable("FLAGS2ENV_NATIVE_LIB") ?? BuildNativeLibrary();
            string configPath = Environment.GetEnvironmentVariable("FLAGS2ENV_FIXTURE") ?? WriteConfig();

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

        private static string BuildNativeLibrary()
        {
            string outputDirectory = Path.Combine(Path.GetTempPath(), $"flags2env-csharp-{Environment.ProcessId}");
            Directory.CreateDirectory(outputDirectory);
            string output = Path.Combine(outputDirectory, DefaultLibraryName());
            var args = new List<string> { "-std=c99", "-O2", "-fPIC" };
            if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
            {
                args.AddRange(new[] { "-dynamiclib", "-Wl,-install_name,@rpath/libflags2env.dylib" });
            }
            else
            {
                args.Add("-shared");
            }
            args.AddRange(new[] { FindNativeSource(), "-o", output });
            RunCompiler(args);
            return output;
        }

        private static string FindNativeSource()
        {
            foreach (string candidate in new[] { "native/parser.c", "clients/csharp/native/parser.c" })
            {
                if (File.Exists(candidate))
                {
                    return Path.GetFullPath(candidate);
                }
            }
            throw new FileNotFoundException("could not find package-local native/parser.c");
        }

        private static void RunCompiler(IEnumerable<string> args)
        {
            var startInfo = new ProcessStartInfo(Environment.GetEnvironmentVariable("CC") ?? "cc")
            {
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
            };
            foreach (string arg in args)
            {
                startInfo.ArgumentList.Add(arg);
            }

            using Process process = Process.Start(startInfo) ?? throw new InvalidOperationException("failed to start C compiler");
            process.WaitForExit();
            if (process.ExitCode != 0)
            {
                throw new Exception($"failed to compile native parser: {process.StandardOutput.ReadToEnd()}{process.StandardError.ReadToEnd()}");
            }
        }

        private static string WriteConfig()
        {
            string directory = Path.Combine(Path.GetTempPath(), $"flags2env-csharp-config-{Environment.ProcessId}");
            Directory.CreateDirectory(directory);
            string path = Path.Combine(directory, ".cli-flags.toml");
            File.WriteAllText(path, @"[flags.port]
env = ""PORT""
aliases = [""port""]
type = ""integer""

[flags.debug]
env = ""DEBUG""
aliases = [""debug""]
type = ""bool""
true_aliases = [""t""]
");
            return path;
        }

        private static string DefaultLibraryName()
        {
            if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX)) return "libflags2env.dylib";
            if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows)) return "flags2env.dll";
            return "libflags2env.so";
        }
    }
}
