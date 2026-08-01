export interface StructuredParse {
  flags: Record<string, string>;
  providedFlags: Record<string, string>;
  command: string;
  subcommands: string[];
  extras: string[];
  unknownOptions: string[];
  errors: string[];
}

export interface CommandResolution {
  path: string[];
  label: string;
}

export interface Flags2EnvBrowserClient {
  setConfig(configText: string): void;
  parse(argv: string[]): Record<string, string>;
  parseStructured(argv: string[]): StructuredParse;
  resolveCommands(argv: string[]): CommandResolution;
  auditConfig(): Record<string, unknown>;
  coerce(values: Record<string, unknown>): Record<string, unknown>;
  helpTableForArgv(command: string, argv: string[], terminalColumns?: number): string;
}

export interface CreateFlags2EnvOptions {
  configText?: string;
  moduleOptions?: Record<string, unknown>;
}

export function createFlags2Env(
  options?: CreateFlags2EnvOptions,
): Promise<Flags2EnvBrowserClient>;

export default createFlags2Env;
