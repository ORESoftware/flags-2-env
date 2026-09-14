# Trusted policy path resolution

A `.cli-flags.toml` file is executable policy. A production service or CLI MUST NOT discover that policy by opening a bare relative path from its current working directory, because the launcher, scheduler, user, or an attacker-controlled directory can change what file is selected.

## Recommended resolution order

1. If the application supports an explicit policy override, require it to be an absolute path to a readable regular file. Do not include the supplied path or native parser error payload in public logs.
2. Resolve the running executable with `std::env::current_exe()` and prefer a package-owned path such as `../share/<package>/.cli-flags.toml` relative to the executable directory.
3. Optionally permit a contract colocated with the executable when the packaging model intentionally uses that layout.
4. A source-tree fallback based on `env!("CARGO_MANIFEST_DIR")` is acceptable for local development and test fixtures. It is compile-time-owned, not current-working-directory-owned.
5. If no reviewed contract exists, fail closed. Do not silently continue with environment-only configuration when the program declares CLI support.

## Diagnostics

Treat parser and coercion diagnostics as potentially value-bearing. Production-facing errors should report categories and counts, for example `2 unknown options, 1 parse error, 0 positional extras`. If option names are useful, strip any `=value` suffix and allow only a bounded identifier character set before rendering the name. Never echo positional contents, credential-like values, or native parser error text into ordinary logs.

## Runtime packaging

For a binary installed at `/usr/local/bin/example`, a conventional immutable policy location is `/usr/local/share/example/.cli-flags.toml`. Container tests should prove the reviewed contract exists in the final runtime image, not only in the build stage or repository checkout.

The bundled Rust backend is preferred for Rust CLIs and servers because it avoids a separate `libflags2env` runtime dependency. Dynamic-language and intentional dynamic-library consumers must instead prove the matching native library is present in every shipped artifact.
