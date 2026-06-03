import { mkdir, readFile, writeFile } from "node:fs/promises";
import { basename, dirname, join } from "node:path";

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

await mkdir(outDir, { recursive: true });

for (const file of ["lib.ejs", "package.json.ejs", "binding.gyp.ejs"]) {
  try {
    const source = await readFile(join(clientDir, file), "utf8");
    const outName = file === "lib.ejs" ? "lib.js" : basename(file, ".ejs");
    await writeFile(join(outDir, outName), render(source, values));
  } catch (error) {
    if (error.code !== "ENOENT") {
      throw error;
    }
  }
}

console.log(`rendered ${runtime} client to ${outDir}`);
