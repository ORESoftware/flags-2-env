# flags2env MATLAB

MATLAB bindings use `loadlibrary` and `calllib` against the native
`flags2env` shared library.

```matlab
env = flags2env.parse(["app", "--port", "8080"], "path/to/.cli-flags.toml");
```

Pass `libraryPath` and `headerPath` when the native library is not discoverable
from MATLAB's current path. The source archive includes `native/parser.h` for
`loadlibrary` and `native/parser.c` for source builds of the shared library.
