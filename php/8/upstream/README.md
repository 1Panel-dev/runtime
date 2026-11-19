# PHP 8 security source builds

These Debian Trixie FPM Dockerfiles build PHP **8.2.36, 8.3.37, 8.4.28 and 8.5.13** from source. They include the security fixes in the [PHP releases on 2026-11-19](https://www.php.net/archive/2026.php), including the PHP-FPM, session, timezone-cache and backtrace fixes listed in the [PHP changelog](https://www.php.net/ChangeLog-8.php).

Source: [docker-library/php](https://github.com/docker-library/php), pinned to security-update commit [`8f7cce49542f60a52d87a852a46a734cc1de78fc`](https://github.com/docker-library/php/commit/8f7cce49542f60a52d87a852a46a734cc1de78fc). Each version directory contains the unchanged upstream `<minor>/trixie/fpm/Dockerfile`. The shared `docker-php-*` scripts and MIT license match that revision. This builds from the official released PHP source without requiring Docker Hub's PHP image publication to finish.

The source archive SHA256 values match the [PHP downloads page](https://www.php.net/downloads.php?source=Y). Both SHA256 and GPG signature verification remain enabled in the Dockerfiles.

Run **Build PHP 8 Security Images** (`.github/workflows/php8-security-release.yml`) manually after committing and pushing the workflow to the default branch. It uses the existing `DOCKERHUB_USERNAME` and `DOCKERHUB_PASSWORD` secrets to publish:

- `1panel/php:8.2.36-fpm`
- `1panel/php:8.3.37-fpm`
- `1panel/php:8.4.28-fpm`
- `1panel/php:8.5.13-fpm`

Each tag includes `linux/amd64`, `linux/arm/v7` and `linux/arm64/v8`. Versions and platform builds run sequentially, with PHP compilation limited to two jobs. This source build does not require the new `php:<version>-fpm` tags to exist on Docker Hub.

The workflow creates a temporary two-stage Dockerfile: the pinned upstream FPM build, then the existing `php/8/Dockerfile` configuration based on that stage. This preserves the Supervisor entrypoint, Composer, extension installer and UID/GID settings without duplicating them. It changes only the upstream stage name and compile parallelism during assembly, then checks the PHP version and FPM configuration in every built platform before pushing. The normal **Build PHP 8 Image** workflow remains available once official base images are published.
