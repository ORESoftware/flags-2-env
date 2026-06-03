<?php

final class Flags2Env
{
    private FFI $ffi;

    public function __construct(?string $libraryPath = null)
    {
        $libraryPath ??= self::defaultLibraryPath();
        $this->ffi = FFI::cdef(
            'char *f2e_parse_json_argv_from_file(const char *config_path, const char *argv_json);
             char *f2e_parse_process_from_file(const char *config_path);
             void f2e_free(char *value);',
            $libraryPath
        );
    }

    /**
     * @param array<int, string> $argv
     * @return array<string, string>
     */
    public function parse(array $argv, ?string $configPath = null): array
    {
        $configPath ??= getcwd() . DIRECTORY_SEPARATOR . '.cli-flags.toml';
        $result = $this->ffi->f2e_parse_json_argv_from_file($configPath, json_encode(array_values($argv)));
        if ($result === null) {
            return [];
        }

        try {
            $decoded = json_decode(FFI::string($result), true, flags: JSON_THROW_ON_ERROR);
            return array_map(static fn ($value): string => (string) $value, $decoded);
        } finally {
            $this->ffi->f2e_free($result);
        }
    }

    /**
     * @return array<string, string>
     */
    public function parseProcess(?string $configPath = null): array
    {
        $configPath ??= getcwd() . DIRECTORY_SEPARATOR . '.cli-flags.toml';
        $result = $this->ffi->f2e_parse_process_from_file($configPath);
        if ($result === null) {
            return [];
        }

        try {
            $decoded = json_decode(FFI::string($result), true, flags: JSON_THROW_ON_ERROR);
            return array_map(static fn ($value): string => (string) $value, $decoded);
        } finally {
            $this->ffi->f2e_free($result);
        }
    }

    /**
     * @param array<string, string> $env
     * @param array<int, string> $argv
     * @return array<string, string>
     */
    public function apply(array $env, array $argv, ?string $configPath = null): array
    {
        return array_replace($env, $this->parse($argv, $configPath));
    }

    /**
     * @param array<string, string> $env
     * @return array<string, string>
     */
    public function applyProcess(array $env, ?string $configPath = null): array
    {
        return array_replace($env, $this->parseProcess($configPath));
    }

    private static function defaultLibraryPath(): string
    {
        return match (PHP_OS_FAMILY) {
            'Darwin' => 'libflags2env.dylib',
            'Windows' => 'flags2env.dll',
            default => 'libflags2env.so',
        };
    }
}
