import { parse } from "./lib.ts";

Deno.chdir("../../tests/fixtures/nested/deeper");

const parsed = parse(["app", "--debug=t", "--port", "8181"], {
  libraryPath: new URL("../../build/libflags2env.so", import.meta.url),
});

if (parsed.DEBUG !== "true" || parsed.PORT !== "8181" || parsed.COLOR !== "true") {
  throw new Error(`unexpected parsed map: ${JSON.stringify(parsed)}`);
}
