from __future__ import annotations

import ctypes
import json
import os
import platform
import sys
from typing import Mapping, MutableMapping, Sequence


def _default_library_name() -> str:
    system = platform.system()
    if system == "Darwin":
        return "libflags2env.dylib"
    if system == "Windows":
        return "flags2env.dll"
    return "libflags2env.so"


def _load_library(library_path: str | None = None) -> ctypes.CDLL:
    resolved_path = library_path or os.environ.get("FLAGS2ENV_NATIVE_LIB") or _default_library_name()
    lib = ctypes.CDLL(resolved_path)
    lib.f2e_parse_json_argv.argtypes = [ctypes.c_char_p]
    lib.f2e_parse_json_argv.restype = ctypes.c_void_p
    lib.f2e_parse_json_argv_from_file.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
    lib.f2e_parse_json_argv_from_file.restype = ctypes.c_void_p
    lib.f2e_parse_process.argtypes = []
    lib.f2e_parse_process.restype = ctypes.c_void_p
    lib.f2e_parse_process_from_file.argtypes = [ctypes.c_char_p]
    lib.f2e_parse_process_from_file.restype = ctypes.c_void_p
    lib.f2e_is_help_requested_json_argv.argtypes = [ctypes.c_char_p]
    lib.f2e_is_help_requested_json_argv.restype = ctypes.c_int
    lib.f2e_help_table_for_json_argv.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int]
    lib.f2e_help_table_for_json_argv.restype = ctypes.c_void_p
    lib.f2e_help_table_for_json_argv_from_file.argtypes = [
        ctypes.c_char_p,
        ctypes.c_char_p,
        ctypes.c_char_p,
        ctypes.c_int,
    ]
    lib.f2e_help_table_for_json_argv_from_file.restype = ctypes.c_void_p
    lib.f2e_coerce_json.argtypes = [ctypes.c_char_p]
    lib.f2e_coerce_json.restype = ctypes.c_void_p
    lib.f2e_coerce_json_from_file.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
    lib.f2e_coerce_json_from_file.restype = ctypes.c_void_p
    lib.f2e_generate_types.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
    lib.f2e_generate_types.restype = ctypes.c_void_p
    lib.f2e_generate_types_from_file.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p]
    lib.f2e_generate_types_from_file.restype = ctypes.c_void_p
    lib.f2e_free.argtypes = [ctypes.c_void_p]
    lib.f2e_free.restype = None
    return lib


class CoercionError(TypeError):
    def __init__(self, errors: list[str]) -> None:
        super().__init__(f"flags2env could not coerce config: {'; '.join(errors)}")
        self.errors = list(errors)


class Flags2Env:
    def __init__(self, library_path: str | None = None) -> None:
        self._lib = _load_library(library_path)

    def parse(self, argv: Sequence[str], config_path: str | None = None) -> dict[str, str]:
        encoded_argv = json.dumps([str(value) for value in argv]).encode()
        result = (
            self._lib.f2e_parse_json_argv_from_file(config_path.encode(), encoded_argv)
            if config_path
            else self._lib.f2e_parse_json_argv(encoded_argv)
        )
        if not result:
            return {}
        try:
            raw = ctypes.string_at(result).decode()
            return {key: str(value) for key, value in json.loads(raw).items()}
        finally:
            self._lib.f2e_free(result)

    def parse_process(self, config_path: str | None = None) -> dict[str, str]:
        result = (
            self._lib.f2e_parse_process_from_file(config_path.encode())
            if config_path
            else self._lib.f2e_parse_process()
        )
        if not result:
            return {}
        try:
            raw = ctypes.string_at(result).decode()
            return {key: str(value) for key, value in json.loads(raw).items()}
        finally:
            self._lib.f2e_free(result)

    def coerce(self, values: Mapping[str, object] | None = None, config_path: str | None = None) -> dict[str, object]:
        """Coerces declared env keys (including subcommand flag envs, command
        marker envs, and the command path env) to their declared types."""
        payload = json.dumps(dict(os.environ if values is None else values)).encode()
        result = (
            self._lib.f2e_coerce_json_from_file(config_path.encode(), payload)
            if config_path
            else self._lib.f2e_coerce_json(payload)
        )
        if not result:
            raise CoercionError(["coercion failed"])
        try:
            report = json.loads(ctypes.string_at(result).decode())
        finally:
            self._lib.f2e_free(result)
        if not report.get("ok"):
            raise CoercionError([str(error) for error in report.get("errors", [])])
        return dict(report.get("value", {}))

    def generate_types(self, language: str, type_name: str | None = None, config_path: str | None = None) -> str:
        """Generates importable types; subcommand flag envs and command envs
        are included as optional fields."""
        encoded_name = (type_name or "").encode() or None
        result = (
            self._lib.f2e_generate_types_from_file(config_path.encode(), language.encode(), encoded_name)
            if config_path
            else self._lib.f2e_generate_types(language.encode(), encoded_name)
        )
        if not result:
            raise ValueError(f"could not generate {language} types; check the language, type name, and config audit")
        try:
            return ctypes.string_at(result).decode()
        finally:
            self._lib.f2e_free(result)

    def is_help_requested(self, argv: Sequence[str] | None = None) -> bool:
        encoded_argv = json.dumps([str(value) for value in (sys.argv if argv is None else argv)]).encode()
        return bool(self._lib.f2e_is_help_requested_json_argv(encoded_argv))

    def help_table(
        self,
        command: str,
        argv: Sequence[str] | None = None,
        config_path: str | None = None,
        terminal_columns: int = 0,
    ) -> str:
        """Renders the help table for the [commands.*] path selected by argv.

        With no argv (or no matching command) this renders the top-level menu,
        including the Commands section when subcommands are declared.
        """
        encoded_argv = json.dumps([str(value) for value in (sys.argv if argv is None else argv)]).encode()
        result = (
            self._lib.f2e_help_table_for_json_argv_from_file(
                config_path.encode(), command.encode(), encoded_argv, terminal_columns
            )
            if config_path
            else self._lib.f2e_help_table_for_json_argv(command.encode(), encoded_argv, terminal_columns)
        )
        if not result:
            return ""
        try:
            return ctypes.string_at(result).decode()
        finally:
            self._lib.f2e_free(result)

    def apply(
        self,
        env: Mapping[str, str] | None = None,
        argv: Sequence[str] | None = None,
        config_path: str | None = None,
    ) -> dict[str, str]:
        merged: MutableMapping[str, str] = dict(os.environ if env is None else env)
        merged.update(self.parse(list(sys.argv if argv is None else argv), config_path))
        return dict(merged)

    def apply_process(
        self,
        env: Mapping[str, str] | None = None,
        config_path: str | None = None,
    ) -> dict[str, str]:
        merged: MutableMapping[str, str] = dict(os.environ if env is None else env)
        merged.update(self.parse_process(config_path))
        return dict(merged)
