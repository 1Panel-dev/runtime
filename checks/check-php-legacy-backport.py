#!/usr/bin/env python3
"""Check pinned legacy patches against official sources; optional 7.3 tar.xz path."""
import hashlib
import os
from pathlib import Path
import re
import subprocess
import sys
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SOURCES = {
    '5.6.40': '1369a51eee3995d7fbd1c5342e5cc917760e276d561595b6052b21ace2656d1c',
    '7.0.33': 'ab8c5be6e32b1f8d032909dedaaaa4bbb1a209e519abb01a52ce3914f9a13d96',
    '7.1.33': 'bd7c0a9bd5433289ee01fd440af3715309faf583f75832b64fe169c100d52968',
    '7.2.34': '409e11bc6a2c18707dfc44bc61c820ddfd81e17481470f3405ee7822d8379903',
    '7.3.33': '166eaccde933381da9516a2b70ad0f447d7cec4b603d07b9a916032b215b90cc',
}
oom_checks = []

for version, source_sha in SOURCES.items():
    context = ROOT / 'php' / ('7' if version == '7.3.33' else version)
    patch = context / 'data/CVE-2026-109618-109619.patch'
    patch_sha = hashlib.sha256(patch.read_bytes()).hexdigest()
    if version == '7.3.33':
        archive = Path(sys.argv[1]) if len(sys.argv) == 2 else None
        build = (context / 'data/rebuild-php-eol').read_text()
        assert f'7.3.33.patch' in (context / 'Dockerfile').read_text()
    else:
        archive = context / f'data/php-{version}.tar.xz'
        build = (context / 'Dockerfile').read_text()
        assert build.index('patch -d /usr/src/php') < build.index('./configure \\\n', build.index('patch -d /usr/src/php'))
        assert 'tar --exclude=.docker-extracted -cJf /tmp/php-patched.tar.xz' in build
        assert 'SHUTDOWN_RAN' in build
        assert 'if grep -q SHUTDOWN_RAN /tmp/backport-oom.log; then exit 1; fi;' in build
        oom_checks.append(build.rsplit('\nRUN ', 1)[1].replace('\\\n', ''))
    assert source_sha in build, version
    assert patch_sha in build, (version, 'update the pinned patch SHA256 after reviewing changes')
    if archive is None:
        print('SKIP 7.3.33 source: pass the official php-7.3.33.tar.xz path')
        continue
    assert hashlib.sha256(archive.read_bytes()).hexdigest() == source_sha, version
    with tempfile.TemporaryDirectory() as tmp:
        source = Path(tmp)
        # Extract only known regular source files. Never trust archive paths or links.
        with tarfile.open(archive) as tar:
            for name in set(re.findall(r'^--- a/(\S+)', patch.read_text(), re.M)) | {'main/php_version.h'}:
                assert '..' not in Path(name).parts and not name.startswith('/')
                member = tar.getmember(f'php-{version}/{name}')
                assert member.isfile()
                target = source / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(tar.extractfile(member).read())
        command = ['patch', '-d', str(source), '-p1', '-F0', '-N']
        for args in (command + ['--dry-run'], command):
            with patch.open() as incoming:
                subprocess.run(args, stdin=incoming, stdout=subprocess.DEVNULL, check=True)
        with patch.open() as incoming:
            repeated = subprocess.run(command + ['--dry-run'], stdin=incoming, capture_output=True)
        assert repeated.returncode != 0, (version, 'repeated patch accepted')
        main = (source / 'main/main.c').read_text()
        shutdown = re.search(r'void php_request_shutdown\(void \*dummy\).*?\n}\n/\* }}} \*/', main, re.S).group()
        assert re.search(r'PG\(modules_activated\)\s*=\s*0', shutdown), version
        assert '|| 1)' in (source / 'ext/session/session.c').read_text()
        multipart = (source / 'main/rfc1867.c').read_text()
        assert 'max_multipart_body_parts' in multipart and '--body_parts_cnt' in multipart
        assert 'substring_conf(char *start, size_t len' in multipart
        allocation = (source / 'Zend/zend_alloc.c').read_text()
        assert 'zend_mm_safe_error_ex' in allocation and '_exit(1)' in allocation
        for path in (source / 'Zend').iterdir():
            text = path.read_text()
            assert not re.search(r'zend_error(?:_noreturn)?\(E_ERROR,\s*"(?:Possible integer overflow|Integer overflow in memory allocation|String allocation overflow|String size overflow|Balloc\(\)[^"]*alloc)', text), (version, path.name)
        if version.startswith('7.'):
            assert 'zend_mm_safe_error_ex' in (source / 'Zend/zend_multiply.h').read_text()
            for filename in ('zend_vm_def.h', 'zend_vm_execute.h'):
                vm = (source / 'Zend' / filename).read_text()
                assert 'ZSTR_MAX_LEN - ZSTR_LEN(op2_str)' in vm, (version, filename)
            assert (source / 'main/php_variables.c').read_text().count('array_init_singleton(') == 4
        assert f'#define PHP_VERSION "{version}"' in (source / 'main/php_version.h').read_text()
        print('PASS', version, 'source SHA256, zero-fuzz apply, repeat rejection, allocation/VM/state/parser guards')

assert (ROOT / 'php/5.6/data/CVE-2026-109618-109619.patch').read_bytes() == (ROOT / 'php/5.6.40/data/CVE-2026-109618-109619.patch').read_bytes()
assert len(set(oom_checks)) == 1
# Exercise build-time failure handling: callback execution and wrong exit codes must fail.
with tempfile.TemporaryDirectory() as tmp:
    directory = Path(tmp)
    for name, source in {
        'php-fpm': '#!/bin/sh\nexit 0\n',
        'php': '#!/bin/sh\necho "Allowed memory size exhausted"\ncase "$TEST_OOM_CASE" in callback) echo SHUTDOWN_RAN;; wrong_status) exit 0;; esac\nexit 1\n',
    }.items():
        path = directory / name
        path.write_text(source)
        path.chmod(0o755)
    script = oom_checks[0].replace('/tmp/backport-oom.log', str(directory / 'oom.log'))
    for case in ('good', 'callback', 'wrong_status'):
        env = dict(os.environ, PATH=str(directory) + os.pathsep + os.environ['PATH'], TEST_OOM_CASE=case)
        result = subprocess.run(['sh', '-c', script], env=env, capture_output=True)
        assert (result.returncode == 0) == (case == 'good'), case
print('PASS: build OOM checks reject callback execution and wrong exit status')
helper = ROOT / 'php/7/data/rebuild-php-eol'
for version in ('5.6.40', '7.3.33'):
    context = ROOT / 'php' / ('7' if version == '7.3.33' else version)
    archive = Path(sys.argv[1]) if version == '7.3.33' and len(sys.argv) == 2 else context / f'data/php-{version}.tar.xz'
    if not archive.exists():
        continue
    patch = context / 'data/CVE-2026-109618-109619.patch'
    command = ['sh', str(helper), '--check-source', version, str(archive), str(patch)]
    subprocess.run(command, stdout=subprocess.DEVNULL, check=True)
    with tempfile.TemporaryDirectory() as tmp:
        bad = Path(tmp) / 'tampered.patch'
        bad.write_bytes(patch.read_bytes() + b'\ntampered\n')
        assert subprocess.run(command[:-1] + [str(bad)], capture_output=True).returncode != 0
        bad.write_bytes(b'not the pinned source')
        assert subprocess.run(command[:4] + [str(bad), str(patch)], capture_output=True).returncode != 0
print('PASS: alternate 5.6 context parity; helper rejects tampered source and patches')
