# Flags2Env F#

F# bindings for the `flags2env` native parser.

The package includes `Flags2Env.fs` plus package-local `native/parser.c` and
`native/parser.h` sources. Consumers can point `FLAGS2ENV_NATIVE_LIB` at a
prebuilt native library, or build the bundled C parser source for their target
platform.
