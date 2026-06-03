<?php

require __DIR__ . '/lib.php';

$suffix = PHP_OS_FAMILY === 'Darwin' ? 'dylib' : (PHP_OS_FAMILY === 'Windows' ? 'dll' : 'so');
$sdk = new Flags2Env(__DIR__ . "/../../build/libflags2env.$suffix");

chdir(__DIR__ . '/../../tests/fixtures/nested/deeper');
$parsed = $sdk->parse(['app', '--debug=t', '--port', '8181']);

if (($parsed['DEBUG'] ?? null) !== 'true' || ($parsed['PORT'] ?? null) !== '8181' || ($parsed['COLOR'] ?? null) !== 'true') {
    fwrite(STDERR, 'unexpected parsed map: ' . json_encode($parsed) . PHP_EOL);
    exit(1);
}
