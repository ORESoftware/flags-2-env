# Runtime Clients

Each runtime client binds to the same C ABI:

```c
char *f2e_parse_process_from_file(const char *config_path);
char *f2e_parse_json_argv_from_file(const char *config_path, const char *argv_json);
void f2e_free(char *value);
```

`f2e_parse_process_from_file` reads the current process argv through the host OS where available. `argv_json` is a JSON array of strings for callers that want to pass modified argv explicitly. The return value is a JSON object whose keys are environment variable names and whose values are strings.

The publishing flow should render only the client for the target runtime, copy in the C source or prebuilt native artifact for that platform, and omit every other `clients/*` directory from the package.

BEAM clients use `clients/erlang/flags2env_nif.c` as the shared native implementation. Erlang and Elixir load it through the `flags2env` module; Gleam loads the same C implementation through `clients/gleam/flags2env_native.erl` so the public Gleam module can still be named `flags2env`. Java uses `clients/java/native/flags2env_jni.c` as a JNI bridge.
