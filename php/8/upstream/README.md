# PHP 8 security source builds

These Debian Trixie FPM Dockerfiles build PHP **8.2.35, 8.3.36, 8.4.27 and 8.5.12** from source. They include the fixes for CVE-2026-109618 and CVE-2026-109619 announced in the [PHP security release on 2026-10-21](https://www.php.net/archive/2026.php#2026-10-21-5).

Source: [docker-library/php PR #1694](https://github.com/docker-library/php/pull/1694), pinned to commit [`f6048b5f6e3c2202ee082665a4ccc0d90de291a3`](https://github.com/docker-library/php/commit/f6048b5f6e3c2202ee082665a4ccc0d90de291a3). The PR was **not merged** when synchronized; its [build CI passed](https://github.com/docker-library/php/actions/runs/39610715899), but that CI does not publish official Docker Hub images. Each version directory contains the unchanged upstream `<minor>/trixie/fpm/Dockerfile`. The shared `docker-php-*` scripts and MIT license also come from that revision.

The source archive SHA256 values match the [PHP downloads page](https://www.php.net/downloads.php?source=Y). Both SHA256 and GPG signature verification remain enabled in the Dockerfiles.

Run **Build PHP 8 Security Images** (`.github/workflows/php8-security-release.yml`) manually after committing and pushing the workflow to the default branch. It uses the existing `DOCKERHUB_USERNAME` and `DOCKERHUB_PASSWORD` secrets to publish:

- `1panel/php:8.2.35-fpm`
- `1panel/php:8.3.36-fpm`
- `1panel/php:8.4.27-fpm`
- `1panel/php:8.5.12-fpm`

Each tag includes `linux/amd64`, `linux/arm/v7` and `linux/arm64/v8`. Versions and platform builds run sequentially, with PHP compilation limited to two jobs. This source build does not require the new `php:<version>-fpm` tags to exist on Docker Hub.

The workflow creates a temporary two-stage Dockerfile: the pinned upstream FPM build, then the existing `php/8/Dockerfile` configuration based on that stage. This preserves the Supervisor entrypoint, Composer, extension installer and UID/GID settings without duplicating them. It changes only the upstream stage name and compile parallelism during assembly, then checks the PHP version and FPM configuration in every built platform before pushing. The normal **Build PHP 8 Image** workflow remains available once official base images are published.
