#!/usr/bin/env python3
"""Offline checks for every PHP PECL bootstrap and its release entry points."""
from pathlib import Path
import re
import subprocess

root = Path(__file__).resolve().parents[1]
contexts = ('5.6', '5.6.40', '7.0.33', '7.1.33', '7.2.34', '7', '8')
for context in contexts:
    dockerfile = (root / f'php/{context}/Dockerfile').read_text()
    assert 'https://pear.php.net/get/PEAR-1.10.18.tgz' in dockerfile, context
    assert '276db000b4e0a9388c7f5168522174bae4144c8c411a71d480b82ec25ee3bc8b' in dockerfile, context
    assert dockerfile.index('pear upgrade --offline --loose /tmp/PEAR.tgz') < dockerfile.index('pecl channel-update https://pecl.php.net/channel.xml'), context
    if context not in ('7', '8'):
        assert 'https://pear.php.net/get/Archive_Tar-1.4.14.tgz' in dockerfile, context
        assert '4af263e4fdfcb400f888f84cccf8d05d1be2eb78128349431405b2ffb0c0c9f4' in dockerfile, context
        assert dockerfile.index('pear upgrade --offline --loose /tmp/Archive_Tar.tgz') < dockerfile.index('pear upgrade --offline --loose /tmp/PEAR.tgz'), context
        assert 'pecl update-channels' not in dockerfile, context
    if context.startswith('5.6'):
        assert 'ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt' in dockerfile, context
    # Docker removes full-line comments before joining continued instructions.
    instructions = '\n'.join(line for line in dockerfile.splitlines() if not line.lstrip().startswith('#'))
    instructions = instructions.replace('\\\n', '')
    for command in re.findall(r'^RUN (.*)$', instructions, re.M):
        subprocess.run(['sh', '-n', '-c', command], check=True)

workflow = (root / '.github/workflows/php7-legacy-release.yml').read_text()
assert re.findall(r'- phpVersion: "([^"]+)"\s+imageVersion: "([^"]+)"', workflow) == [
    ('7.0.33', '7.0.34'), ('7.1.33', '7.1.34'), ('7.2.34', '7.2.35')]
assert 'context: php/${{ matrix.phpVersion }}' in workflow
assert 'file: php/${{ matrix.phpVersion }}/Dockerfile' in workflow
assert 'tags: 1panel/php:${{ matrix.imageVersion }}-fpm' in workflow
assert 'context: php/5.6.40' in (root / '.github/workflows/php5-release.yml').read_text()
subprocess.run(['bash', '-n', str(root / 'tests/check-php-pecl.sh')], check=True)
print('PASS: seven PECL bootstraps, RUN shell syntax, legacy CA and release contexts')
