# Runtime Clients

Each runtime client binds to the same C ABI:

```c
char *f2e_parse_json_argv_from_file(const char *config_path, const char *argv_json);
void f2e_free(char *value);
```

`argv_json` is a JSON array of strings, and the return value is a JSON object whose keys are environment variable names and whose values are strings.

The publishing flow should render only the client for the target runtime, copy in the C source or prebuilt native artifact for that platform, and omit every other `clients/*` directory from the package.
