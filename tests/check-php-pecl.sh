#!/usr/bin/env bash
set -euo pipefail

docker run --rm -i --entrypoint sh "${1:?Usage: bash tests/check-php-pecl.sh IMAGE}" <<'SH'
set -eu
pecl version
pecl remote-info apcu
apcu=$(php -r 'echo PHP_VERSION_ID < 70000 ? "apcu-4.0.11" : "apcu";')
printf '\n' | pecl install "$apcu"
docker-php-ext-enable apcu
php -d apc.enable_cli=1 -r '
if (!extension_loaded("apcu") || !apcu_store("pecl-test", "ok") || apcu_fetch("pecl-test") !== "ok") {
    fwrite(STDERR, "APCu store/fetch failed\n");
    exit(1);
}
echo "APCu store/fetch PASS\n";
'
SH
