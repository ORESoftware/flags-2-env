import type { CommandResolution, StructuredParse } from "./lib.mjs";

export interface Flags2EnvWorkerClient {
  setConfig(configText: string): Promise<void>;
  parse(argv: string[]): Promise<Record<string, string>>;
  parseStructured(argv: string[]): Promise<StructuredParse>;
  resolveCommands(argv: string[]): Promise<CommandResolution>;
  auditConfig(): Promise<Record<string, unknown>>;
  coerce(values: Record<string, unknown>): Promise<Record<string, unknown>>;
  helpTableForArgv(command: string, argv: string[], terminalColumns?: number): Promise<string>;
  terminate(reason?: string): void;
  readonly closed: boolean;
}

export interface CreateFlags2EnvWorkerOptions {
  configText?: string;
  timeoutMs?: number;
  workerUrl?: URL | string;
  workerFactory?: (url: URL | string, init: WorkerOptions) => Worker;
}

export function createFlags2EnvWorker(
  options?: CreateFlags2EnvWorkerOptions,
): Promise<Flags2EnvWorkerClient>;

export default createFlags2EnvWorker;
