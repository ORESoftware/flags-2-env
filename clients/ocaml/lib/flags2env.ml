open Ctypes
open Foreign

let default_library_name () =
  match Sys.os_type with
  | "Win32" | "Cygwin" -> "flags2env.dll"
  | "Unix" when Sys.file_exists "/System/Library/CoreServices/SystemVersion.plist" -> "libflags2env.dylib"
  | _ -> "libflags2env.so"

let library_path () =
  match Sys.getenv_opt "FLAGS2ENV_NATIVE_LIB" with
  | Some value -> value
  | None -> default_library_name ()

let lib =
  Dl.dlopen ~filename:(library_path ()) ~flags:[ Dl.RTLD_NOW; Dl.RTLD_LOCAL ]

let parse_json_argv =
  foreign ~from:lib "f2e_parse_json_argv" (string @-> returning (ptr char))

let parse_json_argv_from_file =
  foreign ~from:lib "f2e_parse_json_argv_from_file" (string @-> string @-> returning (ptr char))

let parse_process_native =
  foreign ~from:lib "f2e_parse_process" (void @-> returning (ptr char))

let parse_process_from_file_native =
  foreign ~from:lib "f2e_parse_process_from_file" (string @-> returning (ptr char))

let is_help_requested_json_argv_native =
  foreign ~from:lib "f2e_is_help_requested_json_argv" (string @-> returning int)

let help_table_for_json_argv_native =
  foreign ~from:lib "f2e_help_table_for_json_argv" (string @-> string @-> int @-> returning (ptr char))

let help_table_for_json_argv_from_file_native =
  foreign ~from:lib "f2e_help_table_for_json_argv_from_file"
    (string @-> string @-> string @-> int @-> returning (ptr char))

let free_native =
  foreign ~from:lib "f2e_free" (ptr char @-> returning void)

let strlen =
  foreign "strlen" (ptr char @-> returning size_t)

let string_of_owned ptr =
  if Ctypes.is_null ptr then "{}"
  else
    let len = Unsigned.Size_t.to_int (strlen ptr) in
    let value = Ctypes.string_from_ptr ptr ~length:len in
    free_native ptr;
    value

let map_of_json raw =
  Yojson.Safe.from_string raw
  |> Yojson.Safe.Util.to_assoc
  |> List.map (fun (key, value) -> (key, Yojson.Safe.Util.to_string value))

let parse ?config_path argv =
  let argv_json = `List (List.map (fun value -> `String value) argv) |> Yojson.Safe.to_string in
  let result =
    match config_path with
    | Some path -> parse_json_argv_from_file path argv_json
    | None -> parse_json_argv argv_json
  in
  result |> string_of_owned |> map_of_json

let parse_process ?config_path () =
  let result =
    match config_path with
    | Some path -> parse_process_from_file_native path
    | None -> parse_process_native ()
  in
  result |> string_of_owned |> map_of_json

let argv_to_json argv =
  `List (List.map (fun value -> `String value) argv) |> Yojson.Safe.to_string

let is_help_requested argv =
  is_help_requested_json_argv_native (argv_to_json argv) <> 0

(* Renders the help table for the [commands.*] path selected by argv; with no
   matching command this renders the top-level menu including the Commands
   section when subcommands are declared. Returns "" when no config exists. *)
let help_table ?config_path ?(terminal_columns = 0) ~command argv =
  let argv_json = argv_to_json argv in
  let result =
    match config_path with
    | Some path -> help_table_for_json_argv_from_file_native path command argv_json terminal_columns
    | None -> help_table_for_json_argv_native command argv_json terminal_columns
  in
  if Ctypes.is_null result then ""
  else
    let len = Unsigned.Size_t.to_int (strlen result) in
    let value = Ctypes.string_from_ptr result ~length:len in
    free_native result;
    value

let apply env argv =
  List.fold_left (fun acc pair -> pair :: List.remove_assoc (fst pair) acc) env (parse argv)
