open System
open System.Diagnostics
open System.IO
open System.Runtime.InteropServices
open OreSoftware.Flags2Env.FSharp

let defaultLibraryName () =
  if RuntimeInformation.IsOSPlatform OSPlatform.OSX then "libflags2env.dylib"
  elif RuntimeInformation.IsOSPlatform OSPlatform.Windows then "flags2env.dll"
  else "libflags2env.so"

let findNativeSource () =
  [ "native/parser.c"; "clients/fsharp/native/parser.c" ]
  |> List.tryFind File.Exists
  |> Option.map Path.GetFullPath
  |> Option.defaultWith (fun () -> raise (FileNotFoundException "could not find package-local native/parser.c"))

let runCompiler args =
  let compiler =
    match Environment.GetEnvironmentVariable "CC" with
    | null | "" -> "cc"
    | value -> value
  let startInfo = ProcessStartInfo compiler
  startInfo.UseShellExecute <- false
  startInfo.RedirectStandardOutput <- true
  startInfo.RedirectStandardError <- true
  args |> List.iter (fun arg -> startInfo.ArgumentList.Add arg)
  use proc = Process.Start startInfo
  if isNull proc then failwith "failed to start C compiler"
  proc.WaitForExit()
  if proc.ExitCode <> 0 then
    failwithf "failed to compile native parser: %s%s" (proc.StandardOutput.ReadToEnd()) (proc.StandardError.ReadToEnd())

let buildNativeLibrary () =
  let outputDirectory = Path.Combine(Path.GetTempPath(), $"flags2env-fsharp-{Environment.ProcessId}")
  Directory.CreateDirectory outputDirectory |> ignore
  let output = Path.Combine(outputDirectory, defaultLibraryName ())
  let args =
    if RuntimeInformation.IsOSPlatform OSPlatform.OSX then
      [ "-std=c99"; "-O2"; "-fPIC"; "-dynamiclib"; "-Wl,-install_name,@rpath/libflags2env.dylib"; findNativeSource (); "-o"; output ]
    else
      [ "-std=c99"; "-O2"; "-fPIC"; "-shared"; findNativeSource (); "-o"; output ]
  runCompiler args
  output

let writeConfig () =
  let directory = Path.Combine(Path.GetTempPath(), $"flags2env-fsharp-config-{Environment.ProcessId}")
  Directory.CreateDirectory directory |> ignore
  let path = Path.Combine(directory, ".cli-flags.toml")
  File.WriteAllText(path, """[flags.port]
env = "PORT"
aliases = ["port"]
type = "integer"

[flags.debug]
env = "DEBUG"
aliases = ["debug"]
type = "bool"
true_aliases = ["t"]
""")
  path

[<EntryPoint>]
let main _ =
  let nativeLibrary =
    match Environment.GetEnvironmentVariable "FLAGS2ENV_NATIVE_LIB" with
    | null | "" -> buildNativeLibrary ()
    | value -> value

  NativeLibrary.SetDllImportResolver(
    typeof<LibraryMarker>.Assembly,
    DllImportResolver(fun libraryName _ _ ->
      if libraryName = "flags2env" then NativeLibrary.Load nativeLibrary
      else nativeint 0))

  let configPath =
    match Environment.GetEnvironmentVariable "FLAGS2ENV_FIXTURE" with
    | null | "" -> writeConfig ()
    | value -> value

  let parsed = Flags2Env.parseFromFile configPath [ "app"; "--debug=t"; "--port"; "8181" ]
  if parsed.["DEBUG"] <> "true" || parsed.["PORT"] <> "8181" then
    failwith "unexpected parsed map"

  let env = Map.ofList [ "PORT", "env"; "KEEP", "1" ]
  let parsedOverride = Flags2Env.parseFromFile configPath [ "app"; "--port"; "8181" ]
  let combined = Map.fold (fun acc key value -> Map.add key value acc) env parsedOverride
  if combined.["PORT"] <> "8181" || combined.["KEEP"] <> "1" then
    failwith "unexpected combined map"
  0
