import { copyFile, mkdir, readFile, readdir, writeFile } from "node:fs/promises";
import { basename, join } from "node:path";

const [runtime, outDir = `dist/${runtime}`] = process.argv.slice(2);

if (!runtime) {
  console.error("usage: node scripts/render-client.mjs <runtime> [out-dir]");
  process.exit(1);
}

const clientDir = join("clients", runtime);

function render(template, values) {
  return template.replace(/<%=\s*([\w]+(?:\s*\|\|\s*'[^']*')?)\s*%>/g, (_match, expr) => {
    const [name, fallback] = expr.split(/\s*\|\|\s*/);
    if (values[name] !== undefined && values[name] !== "") {
      return values[name];
    }
    return fallback ? fallback.slice(1, -1) : "";
  });
}

const values = {
  packageName: process.env.PACKAGE_NAME,
  version: process.env.PACKAGE_VERSION,
  nativeModulePath: process.env.NATIVE_MODULE_PATH,
  nativeLibraryPath: process.env.NATIVE_LIBRARY_PATH,
  nativeLibraryDir: process.env.NATIVE_LIBRARY_DIR,
  addonSource: process.env.ADDON_SOURCE,
  parserSource: process.env.PARSER_SOURCE,
  parserIncludeDir: process.env.PARSER_INCLUDE_DIR,
};

if (runtime === "nodejs") {
  values.addonSource ||= "addon.c";
  values.parserSource ||= "src/parser.c";
  values.parserIncludeDir ||= "src";
}

await mkdir(outDir, { recursive: true });

for (const file of ["package.json.ejs", "binding.gyp.ejs"]) {
  try {
    const source = await readFile(join(clientDir, file), "utf8");
    const outName = basename(file, ".ejs");
    await writeFile(join(outDir, outName), render(source, values));
  } catch (error) {
    if (error.code !== "ENOENT") {
      throw error;
    }
  }
}

for (const file of await readdir(clientDir)) {
  if (["deno.json", "lib.mjs", "lib.cjs", "lib.js", "lib.ts", "mod.ts", "cli.mjs"].includes(file)) {
    await copyFile(join(clientDir, file), join(outDir, file));
  }
}

if (runtime === "nodejs") {
  await copyFile(join(clientDir, "addon.c"), join(outDir, "addon.c"));
  await mkdir(join(outDir, "src"), { recursive: true });
  await copyFile("src/parser.c", join(outDir, "src/parser.c"));
  await copyFile("src/parser.h", join(outDir, "src/parser.h"));
}

if (["bun", "deno"].includes(runtime)) {
  const suffix = process.platform === "darwin" ? "dylib" : process.platform === "win32" ? "dll" : "so";
  const source = process.platform === "win32" ? "build/flags2env.dll" : `build/libflags2env.${suffix}`;
  await mkdir(join(outDir, "native"), { recursive: true });
  await copyFile(source, join(outDir, "native", `libflags2env.${suffix}`));
}

console.log(`rendered ${runtime} client to ${outDir}`);
