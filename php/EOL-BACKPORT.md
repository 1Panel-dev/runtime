# PHP 7.4 / 8.0 / 8.1 source backport

`php/7/Dockerfile` and `php/8/Dockerfile` rebuild the exact official FPM baselines below with the PHP project's minimal fixes for CVE-2026-109618 and CVE-2026-109619. See the [2026-10-21 advisory](https://www.php.net/archive/2026.php#2026-10-21-5). These versions remain **EOL**; this is not a new PHP release or ongoing security support. `PHP_VERSION` stays 7.4.33, 8.0.30 or 8.1.34.

| Base version | Official patch commit | Patch SHA256 |
| --- | --- | --- |
| 7.4.33 | [712e60f9edfd03f0960fc4fc3c2c375f42b90aa2](https://github.com/php/php-src/commit/712e60f9edfd03f0960fc4fc3c2c375f42b90aa2) | `5fe57ca6ee96d59b36c6e0ca842843c50884f177bef1e85234cf669b577f5e48` |
| 8.0.30 | [82f8f31b16a035c1b67cc253e79f7cc288f4cc20](https://github.com/php/php-src/commit/82f8f31b16a035c1b67cc253e79f7cc288f4cc20) | `534478c973cef6f493605b7af907f639a364912ee92c24598ddae44c3bc72d1c` |
| 8.1.34 | [1d7dec178a094e6e75b229ce22754045f8c6070a](https://github.com/php/php-src/commit/1d7dec178a094e6e75b229ce22754045f8c6070a) | `c85ad0fddcbff7f2318617eeaa54d271135463b5bf70a01228447e3ed78de96e` |

The helper also pins the original `.tar.xz` SHA256 from PHP's release metadata ([7.4.33](https://www.php.net/releases/index.php?json&version=7.4.33), [8.0.30](https://www.php.net/releases/index.php?json&version=8.0.30), [8.1.34](https://www.php.net/releases/index.php?json&version=8.1.34)). It uses the archive already present at `/usr/src/php.tar.xz` in the official image. No substitute PHP release tarball is fetched during the image build.

## Build behavior

- The helper runs before Composer and any later extension installation. Older patch levels in these three series fail with an unsupported-baseline error. Other series, including 7.3 and 8.2+, return before downloading patches or changing apt, source or binaries.
- The fixed commit's `.patch` is downloaded over HTTPS, checked against the pinned SHA256, then applied forward-only with zero fuzz after a dry-run. A checksum mismatch, pre-extracted source, repeated application or partial patch stops the build. GitHub changing the patch serialization also requires review and a checksum update; it cannot silently alter the build.
- The original `php-config --configure-options`, `PHP_CFLAGS`, `PHP_CPPFLAGS` and `PHP_LDFLAGS` are reused, including architecture, FPM and extension options. Compilation uses two jobs. Dependencies follow the official Debian FPM builds; the existing `prepare-apt` helper handles archived Buster/Bullseye repositories with signature checks enabled. The PHP 8 context carries an identical copy for its old Bullseye bases.
- `make install` replaces CLI/FPM, shared bundled modules (including OPcache), headers, `phpize` and `php-config`. The build compares installed CLI/FPM bytes with the compiled files and checks the new exported allocator-error symbol in both. It preserves `/usr/local/etc`, checks version/configure options, extension directory, API/build identifiers and the loaded module list, and validates FPM configuration after removing build dependencies.
- The patched, unconfigured source is repacked into `/usr/src/php.tar.xz` before compilation. Future `docker-php-source`, `docker-php-ext-install` and the existing `install-php-extensions` therefore use patched headers and OPcache code. The inherited `PHP_SHA256` still describes the **original** official archive; the original checksum, patch commit/checksum and replacement archive checksum are recorded in `/usr/local/share/php/eol-backport` instead.
- The two build contexts contain identical copies of `data/rebuild-php-eol` because existing workflows build them independently. Update both together; the offline test enforces parity. The supported version matrix is unchanged. The 8.2+ security workflow can still assemble its Dockerfiles and copy `data` unchanged.

## 1Panel maintenance image tag

These are **1Panel maintenance image tags**, not new official PHP releases:

| Official base / internal PHP version | 1Panel output image |
| --- | --- |
| 7.4.33 | `1panel/php:7.4.34-fpm` |
| 8.0.30 | `1panel/php:8.0.31-fpm` |
| 8.1.34 | `1panel/php:8.1.35-fpm` |

`php -v`, `PHP_VERSION`, `php-config`, source checksums and every `FROM php:${PHP_VERSION}-fpm` retain the real official baseline in the left column. Do not pass the maintenance tag version as the Docker build's `PHP_VERSION`.

The PHP 7 workflow has separate inputs: `php74Version` defaults to `7.4.33` (base), and `php74ImageVersion` defaults to `7.4.34` (output image). Its PHP 7.3 job keeps its previous default behavior; set the boolean `buildPhp73=false` to publish only the 7.4 maintenance image. The normal PHP 8 workflow maps the exact inputs `8.0.30` and `8.1.34` to maintenance output tags; all other inputs, including 8.2+, keep their previous output tags. Its input names/defaults and Docker build argument are unchanged. The four-version PHP 8 security workflow is unchanged.

CNB's PHP build accepts optional `PHP_IMAGE_VERSION`. When blank, the three exact EOL baselines above map to their maintenance tags; all other versions keep the original `PHP_VERSION` output tag. An explicit `PHP_IMAGE_VERSION` overrides only the output tag. For example, set `DIR=7`, `PHP_VERSION=7.4.33` (or `DIR=8`, `PHP_VERSION=8.0.30` / `8.1.34`). The Docker build argument remains `PHP_VERSION`.

For direct builds:

```sh
docker build --build-arg PHP_VERSION=7.4.33 -t 1panel/php:7.4.34-fpm php/7
docker build --build-arg PHP_VERSION=8.0.30 -t 1panel/php:8.0.31-fpm php/8
docker build --build-arg PHP_VERSION=8.1.34 -t 1panel/php:8.1.35-fpm php/8
```

Building/publishing must be performed separately by the maintainer; these changes do not trigger a release.

## Compatibility

- Session upload progress is forcibly disabled **in source**, even if `session.upload_progress.enabled` reports enabled. Applications relying on `PHP_SESSION_UPLOAD_PROGRESS` must use another progress mechanism.
- OOM/allocation-overflow paths terminate the process immediately with `_exit(1)` and write the error to stderr. PHP shutdown functions, destructors, normal request cleanup and buffered responses may not run. An FPM worker exits; its master must replace it. The build includes a bounded CLI OOM check for exit status and skipped shutdown handlers.
- The official patches also reset request globals and tighten multipart header handling. PHP 7.4 additionally gains `max_multipart_body_parts`, defaulting to `max_input_vars + max_file_uploads` when negative. Applications using unusually large multipart requests should check this limit.
- PHP 8.1 includes OPcache persistence changes. Use rebuilt bundled modules and reinstall third-party extensions against the resulting image; do not copy old `.so` files into it. Matching API identifiers/path are checked, but arbitrary third-party binary compatibility is not guaranteed.
- The old PHP and Debian bases still carry other EOL risks. This narrowly backports the two named CVEs; migrate to a supported PHP branch for continued security maintenance.

## Offline validation

Run `python3 tests/check-php-eol-backport.py` from the repository. It checks shell syntax, helper parity, version gates and the existing four-version 8.2+ workflow's Python Dockerfile assembly. It never builds images or triggers Actions.

For full source checks, download the official `php-7.4.33.tar.xz`, `php-8.0.30.tar.xz` and `php-8.1.34.tar.xz` plus each fixed commit's `.patch` into a separate directory, naming the patches `<full-commit>.patch`, then run:

```sh
python3 tests/check-php-eol-backport.py /path/to/source-inputs
```

This verifies all pinned SHA256 values, applies each patch to temporary extracted source with zero fuzz, rejects a second application and rejects tampered inputs. The helper's `--check-source VERSION SOURCE.tar.xz COMMIT.patch` mode runs an individual offline check.

Before publication, maintainers still need image builds on every published architecture, runtime/FPM request tests, extension-installation tests (especially OPcache and PECL extensions), upload-progress regression checks and representative application/OOM behavior checks. Offline source checks do not establish those results.
