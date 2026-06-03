import { copyFile, mkdir, readFile, readdir, writeFile } from "node:fs/promises";
import { basename, extname, join } from "node:path";

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
  if (["lib.mjs", "lib.cjs", "lib.js", "lib.ts", "mod.ts"].includes(file)) {
    await copyFile(join(clientDir, file), join(outDir, file));
  }
}

console.log(`rendered ${runtime} client to ${outDir}`);
