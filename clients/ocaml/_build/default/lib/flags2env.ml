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

let coerce_json_native =
  foreign ~from:lib "f2e_coerce_json" (string @-> returning (ptr char))

let coerce_json_from_file_native =
  foreign ~from:lib "f2e_coerce_json_from_file" (string @-> string @-> returning (ptr char))

let generate_types_native =
  foreign ~from:lib "f2e_generate_types" (string @-> string_opt @-> returning (ptr char))

let generate_types_from_file_native =
  foreign ~from:lib "f2e_generate_types_from_file" (string @-> string @-> string_opt @-> returning (ptr char))

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

exception Coercion_error of string list

(* Coerces declared env keys (including subcommand flag envs, command marker
   envs, and the command path env) to their declared types. *)
let coerce ?config_path values =
  let payload = `Assoc values |> Yojson.Safe.to_string in
  let result =
    match config_path with
    | Some path -> coerce_json_from_file_native path payload
    | None -> coerce_json_native payload
  in
  if Ctypes.is_null result then raise (Coercion_error [ "coercion failed" ]);
  let raw = string_of_owned result in
  let report = Yojson.Safe.from_string raw in
  let ok =
    match Yojson.Safe.Util.member "ok" report with
    | `Bool value -> value
    | _ -> false
  in
  if not ok then begin
    let errors =
      Yojson.Safe.Util.member "errors" report
      |> Yojson.Safe.Util.to_list
      |> List.map Yojson.Safe.Util.to_string
    in
    raise (Coercion_error errors)
  end;
  Yojson.Safe.Util.member "value" report |> Yojson.Safe.Util.to_assoc

(* Generates importable types; subcommand flag envs and command envs are
   included as optional fields. Returns "" when generation fails. *)
let generate_types ?config_path ?type_name language =
  let result =
    match config_path with
    | Some path -> generate_types_from_file_native path language type_name
    | None -> generate_types_native language type_name
  in
  if Ctypes.is_null result then "" else string_of_owned result

let apply env argv =
  List.fold_left (fun acc pair -> pair :: List.remove_assoc (fst pair) acc) env (parse argv)
