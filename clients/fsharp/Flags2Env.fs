namespace OreSoftware.Flags2Env.FSharp

open System
open System.Collections.Generic
open System.Runtime.InteropServices
open System.Text
open System.Text.Json

/// Public marker used by consumers that need the assembly containing the
/// native bindings (for example, to register a DllImport resolver).
type LibraryMarker = class end

module Flags2Env =
  [<DllImport("flags2env", CallingConvention = CallingConvention.Cdecl)>]
  extern nativeint f2e_parse_json_argv(nativeint argvJson)

  [<DllImport("flags2env", CallingConvention = CallingConvention.Cdecl)>]
  extern nativeint f2e_parse_json_argv_from_file(nativeint configPath, nativeint argvJson)

  [<DllImport("flags2env", CallingConvention = CallingConvention.Cdecl)>]
  extern nativeint f2e_parse_process()

  [<DllImport("flags2env", CallingConvention = CallingConvention.Cdecl)>]
  extern nativeint f2e_parse_process_from_file(nativeint configPath)

  [<DllImport("flags2env", CallingConvention = CallingConvention.Cdecl)>]
  extern void f2e_free(nativeint value)

  let private utf8 (value: string) =
    let bytes = Encoding.UTF8.GetBytes(value + "\000")
    let ptr = Marshal.AllocCoTaskMem bytes.Length
    Marshal.Copy(bytes, 0, ptr, bytes.Length)
    ptr

  let private decode result =
    if result = nativeint 0 then
      Map.empty
    else
      try
        let json = Marshal.PtrToStringUTF8 result
        let parsed = JsonSerializer.Deserialize<Dictionary<string, string>>(json)
        if isNull parsed then Map.empty
        else parsed |> Seq.map (fun pair -> pair.Key, pair.Value) |> Map.ofSeq
      finally
        f2e_free result

  let parse (argv: seq<string>) =
    let argvPtr = utf8 (JsonSerializer.Serialize(argv))
    try f2e_parse_json_argv argvPtr |> decode
    finally Marshal.FreeCoTaskMem argvPtr

  let parseFromFile configPath (argv: seq<string>) =
    let configPtr = utf8 configPath
    let argvPtr = utf8 (JsonSerializer.Serialize(argv))
    try f2e_parse_json_argv_from_file(configPtr, argvPtr) |> decode
    finally
      Marshal.FreeCoTaskMem configPtr
      Marshal.FreeCoTaskMem argvPtr

  let parseProcess () =
    f2e_parse_process () |> decode

  let parseProcessFromFile configPath =
    let configPtr = utf8 configPath
    try f2e_parse_process_from_file configPtr |> decode
    finally Marshal.FreeCoTaskMem configPtr

  let apply env argv =
    Map.fold (fun acc key value -> Map.add key value acc) env (parse argv)
