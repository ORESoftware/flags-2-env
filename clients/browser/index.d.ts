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

export interface AuditReport {
  ok?: boolean;
  errors?: string[];
  warnings?: string[];
  [key: string]: unknown;
}

export interface BrowserClient {
  parse(argv?: string[]): Record<string, string>;
  parseStructured(argv?: string[]): StructuredParse;
  resolveCommands(argv?: string[]): CommandResolution;
  auditConfig(): AuditReport;
  helpTableForArgv(command?: string, argv?: string[], terminalColumns?: number): string;
  completionScript(shell: string, command?: string): string;
  coerce(values: Record<string, unknown>): Record<string, unknown>;
}

export interface BrowserClientOptions {
  /** Absolute path inside the private Emscripten virtual filesystem. */
  configPath?: string;
  /** Test-only module factory injection. */
  moduleFactory?: (options: { noInitialRun: boolean }) => Promise<unknown>;
}

export class CoercionError extends TypeError {
  readonly errors: string[];
}

export function createFlags2EnvBrowser(
  config: string,
  options?: BrowserClientOptions,
): Promise<BrowserClient>;

export default createFlags2EnvBrowser;
