import { apply, parse } from "./lib.ts";

Deno.chdir("../../tests/fixtures/nested/deeper");
const options = {
  libraryPath: new URL("../../build/libflags2env.so", import.meta.url),
};

const parsed = parse(["app", "--debug=t", "--port", "8181"], {
  libraryPath: options.libraryPath,
});

if (parsed.DEBUG !== "true" || parsed.PORT !== "8181" || parsed.COLOR !== "true") {
  throw new Error(`unexpected parsed map: ${JSON.stringify(parsed)}`);
}

const explicit = parse(["app", "--debug=f"], { ...options, configPath: "../../.cli-flags.toml" });
if (explicit.DEBUG !== "false" || explicit.PORT !== "3000") {
  throw new Error(`unexpected explicit config map: ${JSON.stringify(explicit)}`);
}

const combined = apply({ PORT: "env", KEEP: "1" }, ["app", "--port", "8181"], options);
if (combined.PORT !== "8181" || combined.KEEP !== "1" || combined.COLOR !== "true") {
  throw new Error(`unexpected combined map: ${JSON.stringify(combined)}`);
}
