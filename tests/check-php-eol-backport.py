#!/usr/bin/env python3
"""Offline checks. Optional argument: directory with official tar.xz and patches."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import textwrap

root = Path(__file__).resolve().parents[1]
helper = root / 'php/7/data/rebuild-php-eol'
assert helper.read_bytes() == (root / 'php/8/data/rebuild-php-eol').read_bytes()
assert helper.read_bytes() == (root / 'php/5.6/data/rebuild-php-eol').read_bytes()
assert (root / 'php/7/data/prepare-apt').read_bytes() == (root / 'php/8/data/prepare-apt').read_bytes()
assert (root / 'php/7/data/prepare-apt').read_bytes() == (root / 'php/5.6/data/prepare-apt').read_bytes()

# Stretch lacks VERSION_CODENAME; all archive cases must retain signature checks.
with tempfile.TemporaryDirectory() as tmp:
    directory = Path(tmp)
    release = directory / 'os-release'
    sources = directory / 'sources.list'
    prepare = (root / 'php/7/data/prepare-apt').read_text().replace('/etc/os-release', str(release)).replace('/etc/apt/sources.list', str(sources))
    for version, codename, suite in [('9', 'stretch', 'stretch/updates'), ('10', 'buster', 'buster/updates'), ('11', 'bullseye', 'bullseye-security')]:
        release.write_text('ID=debian\nVERSION_ID=' + version + '\n')
        subprocess.run(['sh', '-eu', '-c', prepare], check=True)
        text = sources.read_text()
        protocol = 'http' if version == '9' else 'https'
        assert f'{protocol}://archive.debian.org/debian {codename} main' in text
        assert f'{protocol}://archive.debian.org/debian-security {suite} main' in text
        assert 'trusted=yes' not in text and 'allow-insecure' not in text
for branch in ('7', '8'):
    dockerfile = (root / f'php/{branch}/Dockerfile').read_text()
    assert dockerfile.startswith('ARG PHP_VERSION\nFROM php:${PHP_VERSION}-fpm\n')
    assert dockerfile.index('RUN sh /usr/local/bin/rebuild-php-eol') < dockerfile.index('composer-setup.php')
    subprocess.run(['sh', '-n', str(root / f'php/{branch}/data/rebuild-php-eol')], check=True)
    subprocess.run(['sh', '-n', str(root / f'php/{branch}/data/prepare-apt')], check=True)

# Fail the test if a skipped/rejected version reaches any build command.
with tempfile.TemporaryDirectory() as tmp:
    bindir = Path(tmp)
    (bindir / 'php-config').write_text('#!/bin/sh\nprintf "%s\\n" "$TEST_VERSION"\n')
    (bindir / 'php-config').chmod(0o755)
    for command in ('apt-get', 'apt-mark', 'curl', 'docker-php-source', 'make', 'php', 'php-fpm'):
        path = bindir / command
        path.write_text('#!/bin/sh\necho BUILD_COMMAND_REACHED >&2\nexit 99\n')
        path.chmod(0o755)
    cases = [('8.2.35', True), ('8.3.36', True), ('8.4.27', True), ('8.5.12', True),
             ('5.6.39', False), ('7.3.32', False), ('7.3.34', False),
             ('5.5.38', False), ('7.0.33', False), ('7.1.33', False), ('7.2.34', False),
             ('7.4.32', False), ('7.4.34', False), ('8.0.29', False), ('8.1.33', False), ('8.1.35', False)]
    for version, success in cases:
        env = dict(os.environ, PATH=str(bindir) + os.pathsep + os.environ['PATH'], TEST_VERSION=version)
        result = subprocess.run(['sh', str(helper)], env=env, capture_output=True, text=True)
        assert (result.returncode == 0) == success, (version, result.stderr)
        assert 'BUILD_COMMAND_REACHED' not in result.stderr
        if not success:
            assert 'unsupported baseline' in result.stderr

# Run only the existing workflow's Python assembly, never a Docker/Actions job.
workflow = (root / '.github/workflows/php8-security-release.yml').read_text()
assembly = textwrap.dedent(workflow.split("python3 - <<'PY'\n", 1)[1].split('\n          PY', 1)[0])
with tempfile.TemporaryDirectory() as tmp:
    for version in ('8.2.35', '8.3.36', '8.4.27', '8.5.12'):
        directory = Path(tmp) / version
        directory.mkdir()
        env = dict(os.environ, PHP_VERSION=version, RUNNER_TEMP=str(directory))
        subprocess.run([sys.executable, '-c', assembly], cwd=root, env=env, check=True)
        context = directory / 'php-security'
        assert (context / 'data/rebuild-php-eol').is_file()
        assert (context / 'data/prepare-apt').is_file()
        assert 'RUN sh /usr/local/bin/rebuild-php-eol' in (context / 'Dockerfile').read_text()
php7 = (root / '.github/workflows/php7-release.yml').read_text()
assert "buildPhp74:\n        description: 'Build and publish PHP 7.4'\n        type: boolean\n        default: true" in php7
assert 'Build PHP-7.4 and Push\n        if: ${{ inputs.buildPhp74 }}' in php7
assert "php74Version:\n        description: 'Official PHP 7.4 base version (7.4.33)'\n        default: '7.4.33'" in php7
assert "php74ImageVersion:\n        description: '1Panel maintenance image version (PHP remains 7.4.33)'\n        default: '7.4.34'" in php7
assert 'PHP_VERSION=${{ github.event.inputs.php74Version }}' in php7
assert '1panel/php:${{ github.event.inputs.php74ImageVersion }}-fpm' in php7
assert '1panel/php:${{ github.event.inputs.php73Version }}-fpm' in php7
assert "buildPhp73:\n        description: 'Also build and publish PHP 7.3'\n        type: boolean\n        default: true" in php7
assert 'Build PHP-7.3 and Push\n        if: ${{ inputs.buildPhp73 }}' in php7
cnb = (root / '.cnb.yml').read_text()
assert '--build-arg PHP_VERSION=$PHP_VERSION' in cnb
assert 'PHP_IMAGE_VERSION:' in (root / '.cnb/web_trigger.yml').read_text()
php8 = (root / '.github/workflows/php8-release.yml').read_text()
assert 'PHP_VERSION=${{ github.event.inputs.phpVersion }}' in php8
assert '1panel/php:${{ steps.image.outputs.version }}-fpm' in php8
tag_step = textwrap.dedent(php8.split('        run: |\n', 1)[1].split('\n      - name:', 1)[0])
cnb_step = textwrap.dedent(cnb.split('web_trigger_build_php_image:', 1)[1].split('          script: |\n', 1)[1].split('\n          exports:', 1)[0])
for base, expected in [('7.4.33', '7.4.34'), ('8.0.30', '8.0.31'), ('8.1.34', '8.1.35'),
                       ('8.2.35', '8.2.35'), ('8.3.36', '8.3.36'), ('8.4.27', '8.4.27'), ('8.5.12', '8.5.12')]:
    with tempfile.TemporaryDirectory() as tmp:
        output = Path(tmp) / 'output'
        env = dict(os.environ, PHP_VERSION=base, PHP_IMAGE_VERSION='', DOCKER_REGISTRY='registry', DOCKER_GROUP='1panel', GITHUB_OUTPUT=str(output))
        if not base.startswith('7.'):
            subprocess.run(['sh', '-eu', '-c', tag_step], env=env, check=True)
            assert output.read_text().strip() == 'version=' + expected
        tag = subprocess.check_output(['sh', '-eu', '-c', cnb_step], env=env, text=True)
        assert tag == f'registry/1panel/php:{expected}-fpm'
        env['PHP_IMAGE_VERSION'] = 'custom'
        tag = subprocess.check_output(['sh', '-eu', '-c', cnb_step], env=env, text=True)
        assert tag == 'registry/1panel/php:custom-fpm'
print('PASS: syntax, context parity, version gates, maintenance tag separation and four 8.2+ workflow assemblies')

if len(sys.argv) == 2:
    sources = Path(sys.argv[1]).resolve()
    for version, commit in (
        ('7.4.33', '712e60f9edfd03f0960fc4fc3c2c375f42b90aa2'),
        ('8.0.30', '82f8f31b16a035c1b67cc253e79f7cc288f4cc20'),
        ('8.1.34', '1d7dec178a094e6e75b229ce22754045f8c6070a'),
    ):
        archive = sources / f'php-{version}.tar.xz'
        patch = sources / f'{commit}.patch'
        command = ['sh', str(helper), '--check-source', version, str(archive), str(patch)]
        subprocess.run(command, check=True)
        with tempfile.TemporaryDirectory() as tmp:
            corrupt = Path(tmp) / 'corrupt.patch'
            corrupt.write_bytes(patch.read_bytes() + b'\ntampered\n')
            result = subprocess.run(command[:-1] + [str(corrupt)], capture_output=True, text=True)
            assert result.returncode != 0, 'tampered patch accepted'
            corrupt_source = Path(tmp) / 'corrupt.tar.xz'
            corrupt_source.write_bytes(b'not the pinned source archive')
            result = subprocess.run(command[:4] + [str(corrupt_source), str(patch)], capture_output=True, text=True)
            assert result.returncode != 0, 'tampered source accepted'
    print('PASS: all official source/patch checksums, zero-fuzz application, repeat and tamper rejection')
elif len(sys.argv) != 1:
    raise SystemExit('usage: check-php-eol-backport.py [SOURCE_DIRECTORY]')
