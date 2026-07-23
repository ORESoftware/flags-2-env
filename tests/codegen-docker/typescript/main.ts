import type { CliStuff } from "./cli-interfaces.js";

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

if (config.PORT !== 4242 || config.UNTYPED !== "123") {
  throw new Error("generated TypeScript interface produced an invalid config");
}

console.log("typescript generated interface passed");
