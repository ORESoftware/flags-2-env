from __future__ import annotations

import ctypes
import json
import os
import platform
from pathlib import Path
from typing import Mapping, MutableMapping, Sequence


def _default_library_name() -> str:
    system = platform.system()
    if system == "Darwin":
        return "libflags2env.dylib"
    if system == "Windows":
        return "flags2env.dll"
    return "libflags2env.so"


def _load_library(library_path: str | None = None) -> ctypes.CDLL:
    lib = ctypes.CDLL(library_path or _default_library_name())
    lib.f2e_parse_json_argv_from_file.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
    lib.f2e_parse_json_argv_from_file.restype = ctypes.c_void_p
    lib.f2e_free.argtypes = [ctypes.c_void_p]
    lib.f2e_free.restype = None
    return lib


class Flags2Env:
    def __init__(self, library_path: str | None = None) -> None:
        self._lib = _load_library(library_path)

    def parse(self, argv: Sequence[str], config_path: str | None = None) -> dict[str, str]:
        config = (config_path or str(Path.cwd() / ".cli-flags.toml")).encode()
        encoded_argv = json.dumps([str(value) for value in argv]).encode()
        result = self._lib.f2e_parse_json_argv_from_file(config, encoded_argv)
        if not result:
            return {}
        try:
            raw = ctypes.string_at(result).decode()
            return {key: str(value) for key, value in json.loads(raw).items()}
        finally:
            self._lib.f2e_free(result)

    def apply(
        self,
        env: Mapping[str, str] | None = None,
        argv: Sequence[str] | None = None,
        config_path: str | None = None,
    ) -> dict[str, str]:
        merged: MutableMapping[str, str] = dict(os.environ if env is None else env)
        merged.update(self.parse(list(os.sys.argv if argv is None else argv), config_path))
        return dict(merged)
