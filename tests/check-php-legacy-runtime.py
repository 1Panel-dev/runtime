#!/usr/bin/env python3
"""Bounded CLI/FastCGI regression checks in one disposable local image container."""
import json
from pathlib import Path
import socket
import struct
import subprocess
import sys
import tempfile
import time
from urllib.parse import urlencode


def docker(*args, **kwargs):
    return subprocess.check_output(['docker', *args], text=True, **kwargs).strip()


def record(kind, data=b''):
    return struct.pack('!BBHHBB', 1, kind, 1, len(data), 0, 0) + data


def length(value):
    return bytes([value]) if value < 128 else struct.pack('!I', value | 0x80000000)


def request(port, query='', body=b'', content_type='', cookie=''):
    params = {
        'GATEWAY_INTERFACE': 'CGI/1.1', 'SERVER_PROTOCOL': 'HTTP/1.1',
        'SCRIPT_FILENAME': '/tmp/php-backport-tests/request.php', 'SCRIPT_NAME': '/request.php',
        'DOCUMENT_ROOT': '/tmp/php-backport-tests', 'REQUEST_URI': '/request.php?' + query,
        'REQUEST_METHOD': 'POST' if body else 'GET', 'QUERY_STRING': query,
        'SERVER_NAME': 'localhost', 'SERVER_PORT': '80', 'REMOTE_ADDR': '127.0.0.1',
        'CONTENT_LENGTH': str(len(body)), 'CONTENT_TYPE': content_type, 'HTTP_COOKIE': cookie,
    }
    encoded = b''
    for key, value in params.items():
        key, value = key.encode(), value.encode()
        encoded += length(len(key)) + length(len(value)) + key + value
    output = b''
    with socket.create_connection(('127.0.0.1', port), timeout=15) as connection:
        connection.sendall(record(1, struct.pack('!HB5x', 1, 0)) + record(4, encoded) + record(4))
        try:
            for offset in range(0, len(body), 65535):
                connection.sendall(record(5, body[offset:offset + 65535]))
            connection.sendall(record(5))
        except (BrokenPipeError, ConnectionResetError):
            return b''

        def receive(size):
            data = b''
            while len(data) < size:
                try:
                    part = connection.recv(size - len(data))
                except ConnectionResetError:
                    return None
                if not part:
                    return None
                data += part
            return data

        while True:
            header = receive(8)
            if header is None:
                break
            _, kind, _, size, padding, _ = struct.unpack('!BBHHBB', header)
            data = receive(size + padding)
            assert data is not None, 'truncated FastCGI response'
            if kind == 6:
                output += data[:size]
            if kind == 3:
                break
    return output


def response(port, **kwargs):
    raw = request(port, **kwargs)
    assert b'\r\n\r\n' in raw, raw[:1000]
    return json.loads(raw.split(b'\r\n\r\n', 1)[1])


def multipart(parts):
    boundary = 'legacy-backport-regression'
    body = b''
    for headers, value in parts:
        body += ('--' + boundary + '\r\n' + headers + '\r\n\r\n').encode() + value + b'\r\n'
    return body + ('--' + boundary + '--\r\n').encode(), 'multipart/form-data; boundary=' + boundary


def main(image):
    with tempfile.TemporaryDirectory() as tmp:
        directory = Path(tmp)
        directory.chmod(0o755)
        (directory / 'request.php').write_text('''<?php
if (isset($_GET['oom'])) {
    register_shutdown_function(function () { file_put_contents('/tmp/backport-shutdown-ran', 'bad'); });
    str_repeat('x', 32 * 1024 * 1024);
}
if (isset($_GET['fatal'])) { backport_undefined_function(); }
if (isset($_GET['warning'])) { trigger_error('next request warning', E_USER_WARNING); }
session_start();
$copy = $_POST;
$copy['backport_copy_check'] = array('value' => 'ok');
unset($copy['backport_copy_check']);
$copy_ok = $copy === $_POST;
if (isset($copy['items'][0]['name'])) {
    $copy['items'][0]['extra'] = 'copy';
    $copy['items'][0]['name'] = 'changed';
    $copy_ok = $copy_ok && !isset($_POST['items'][0]['extra']) && $_POST['items'][0]['name'] === '0';
}
echo json_encode(array('version' => PHP_VERSION, 'sapi' => PHP_SAPI, 'pid' => getmypid(),
    'post' => $_POST, 'get' => $_GET, 'files' => $_FILES, 'session' => $_SESSION, 'copy_ok' => $copy_ok));
set_error_handler(function () { echo 'STALE_ERROR_HANDLER'; });
set_exception_handler(function ($error) { echo 'STALE_EXCEPTION_HANDLER'; });
''')
        (directory / 'fpm.conf').write_text('''[global]
daemonize = no
error_log = /proc/self/fd/2
[www]
listen = 9000
user = www-data
group = www-data
pm = static
pm.max_children = 1
pm.max_requests = 0
catch_workers_output = yes
php_admin_value[memory_limit] = 16M
php_admin_flag[display_errors] = off
php_admin_flag[log_errors] = on
php_admin_value[max_multipart_body_parts] = 4
php_admin_value[max_input_vars] = 20000
php_admin_flag[session.upload_progress.enabled] = on
php_admin_flag[session.upload_progress.cleanup] = off
php_admin_value[session.upload_progress.min_freq] = 0
php_admin_value[session.save_path] = /tmp
''')
        probe = directory / 'probe'
        probe.mkdir()
        (probe / 'config.m4').write_text('''PHP_ARG_ENABLE(backport_probe, whether to enable backport_probe, [ --enable-backport_probe Enable probe])
if test "$PHP_BACKPORT_PROBE" != "no"; then
  PHP_NEW_EXTENSION(backport_probe, backport_probe.c, $ext_shared)
fi
''')
        (probe / 'backport_probe.c').write_text('''#ifdef HAVE_CONFIG_H
#include "config.h"
#endif
#include "php.h"
PHP_FUNCTION(backport_allocation_overflow) {
    void *memory = safe_emalloc((size_t)-1, 2, 0);
    efree(memory);
    RETURN_FALSE;
}
#if PHP_VERSION_ID >= 70000
PHP_FUNCTION(backport_hash_overflow) {
    HashTable table;
    zend_hash_init(&table, (uint32_t)-1, NULL, ZVAL_PTR_DTOR, 0);
    zend_hash_destroy(&table);
    RETURN_FALSE;
}
#endif
static const zend_function_entry functions[] = {
    PHP_FE(backport_allocation_overflow, NULL)
#if PHP_VERSION_ID >= 70000
    PHP_FE(backport_hash_overflow, NULL)
#endif
    PHP_FE_END
};
zend_module_entry backport_probe_module_entry = {
    STANDARD_MODULE_HEADER, "backport_probe", functions,
    NULL, NULL, NULL, NULL, NULL, "1.0", STANDARD_MODULE_PROPERTIES
};
#ifdef COMPILE_DL_BACKPORT_PROBE
ZEND_GET_MODULE(backport_probe)
#endif
''')
        container = docker('create', '--entrypoint', 'php-fpm', '-p', '127.0.0.1::9000',
                           image, '-F', '-y', '/tmp/php-backport-tests/fpm.conf')
        try:
            docker('cp', str(directory) + '/.', container + ':/tmp/php-backport-tests')
            docker('start', container)
            port = int(docker('port', container, '9000/tcp').rsplit(':', 1)[1])
            deadline = time.monotonic() + 30
            while True:
                try:
                    first = response(port)
                    break
                except (OSError, AssertionError):
                    if time.monotonic() > deadline:
                        raise
                    time.sleep(0.2)
            version = first['version']
            assert first['sapi'] == 'fpm-fcgi'
            assert first['copy_ok']
            assert response(port, query='warning=1')['pid'] == first['pid']
            nested = {f'items[{i}][name]': str(i) for i in range(100)}
            parsed = response(port, body=urlencode(nested).encode(), content_type='application/x-www-form-urlencoded')
            assert len(parsed['post']['items']) == 100
            assert parsed['post']['items'][99]['name'] == '99'
            assert parsed['copy_ok']
            body, kind = multipart([
                ('Content-Disposition: form-data; name="PHP_SESSION_UPLOAD_PROGRESS"', b'legacy-check'),
                ('Content-Disposition: form-data; name="foo"\r\nContent-Disposition: form-data; name="ignored"', b'bar'),
                ('Content-Disposition: form-data; name="file"; filename="test.txt"\r\nContent-Type: text/plain', b'upload check'),
            ])
            uploaded = response(port, body=body, content_type=kind, cookie='PHPSESSID=legacybackportcheck')
            assert uploaded['post']['foo'] == 'bar' and 'ignored' not in uploaded['post']
            assert uploaded['files']['file']['error'] == 0 and uploaded['files']['file']['size'] == 12
            assert 'upload_progress_legacy-check' not in uploaded['session']
            body, kind = multipart([(f'Content-Disposition: form-data; name="f{i}"', b'value') for i in range(6)])
            limited = response(port, body=body, content_type=kind)
            assert len(limited['post']) == 4 and 'f4' not in limited['post']
            request(port, query='fatal=1')
            assert response(port)['pid'] == first['pid'], 'ordinary fatal must not kill the worker'
            # Exhaust memory before request.php runs, while constructing input arrays.
            deep = {('field' + str(i) + '[n]' * 32): 'x' for i in range(10000)}
            raw = request(port, body=urlencode(deep).encode(), content_type='application/x-www-form-urlencoded')
            assert b'"sapi"' not in raw, 'input parsing did not exhaust the bounded memory limit'
            assert b'STALE_' not in raw, 'input OOM invoked a previous request handler'
            after_parse_oom = response(port)
            assert after_parse_oom['pid'] != first['pid'], 'input OOM worker was not replaced'
            request(port, query='oom=1')
            assert response(port)['pid'] != after_parse_oom['pid'], 'OOM worker was not replaced'
            logs = docker('logs', container, stderr=subprocess.STDOUT)
            assert logs.count('exited with code 1') >= 2 and 'Allowed memory size' in logs, logs
            assert 'exited on signal' not in logs, logs
            assert subprocess.run(['docker', 'exec', container, 'test', '-e', '/tmp/backport-shutdown-ran']).returncode == 1
            assert 'SHUTDOWN_RAN' not in docker('exec', container, 'sh', '-c',
                'php -n -d memory_limit=16M -r \'register_shutdown_function(function () { echo "SHUTDOWN_RAN"; }); str_repeat("x", 33554432);\' 2>&1; test "$?" = 1')
            docker('exec', container, 'sh', '-eu', '-c',
                   'cd /tmp/php-backport-tests/probe; phpize >build.log 2>&1; '
                   './configure --enable-backport_probe >>build.log 2>&1; make -j2 >>build.log 2>&1', timeout=180)
            for function in ['backport_allocation_overflow'] + ([] if version.startswith('5.') else ['backport_hash_overflow']):
                result = subprocess.run(['docker', 'exec', container, 'php', '-n', '-d',
                    'extension=/tmp/php-backport-tests/probe/modules/backport_probe.so', '-r',
                    'register_shutdown_function(function () { echo "SHUTDOWN_RAN"; }); ' + function + '();'], capture_output=True, text=True)
                assert result.returncode == 1 and 'SHUTDOWN_RAN' not in result.stdout, result
                assert 'overflow' in result.stderr.lower(), result.stderr
            docker('exec', container, 'sh', '-eu', '-c',
                   'docker-php-source extract; grep -q zend_mm_safe_error_ex /usr/src/php/Zend/zend_alloc.h')
            docker('exec', container, 'sh', '-eu', '-c',
                   'php -n -d zend_extension="$(php-config --extension-dir)/opcache.so" -d opcache.enable_cli=1 '
                   '-r \'if (!extension_loaded("Zend OPcache")) exit(1); echo "OPcache loaded";\'')
            print('PASS', image, version, 'CLI + compiled extension overflow + OPcache + FPM repeat/fatal/input-OOM/script-OOM recovery + uploads/progress/multipart/nested fields')
        except BaseException:
            print(docker('logs', container), file=sys.stderr)
            subprocess.run(['docker', 'exec', container, 'cat', '/tmp/php-backport-tests/probe/build.log'])
            raise
        finally:
            docker('rm', '-f', container)


if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit('Usage: check-php-legacy-runtime.py IMAGE')
    main(sys.argv[1])
