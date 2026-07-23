import type { CliStuff } from "./cli-interfaces.ts";

const config = {
  PORT: 4242,
  RATIO: 0.25,
  DEBUG: true,
  NAME: "matrix",
  ITEMS: [1, "two"],
  LABELS: { region: "test" },
  PAYLOAD: { enabled: true },
  UNTYPED: "123",
} satisfies CliStuff;

if (config.DEBUG !== true || config.LABELS.region !== "test") {
  throw new Error("generated TypeScript interface produced an invalid config");
}

console.log("typescript runtime generated interface passed");
