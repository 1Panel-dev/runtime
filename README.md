[English](README.md) | [中文](README_zh.md)

# 1Panel Runtime Images

This repository contains runtime images used by 1Panel.

Current images in this repository:

- `1panel/comfyui`
- `1panel/deepseek-harness`
- `1panel/hermes-agent`
- `1panel/openclaw`
- `1panel/vllm-gb10-dspark`
- `1panel/node`
- `1panel/php`
- `1panel/java`

## Images

- `1panel/comfyui`: ComfyUI runtime image for NVIDIA GPUs, built from matching upstream stable releases
- `1panel/deepseek-harness`: DeepSeek Harness image maintained by 1Panel with HTTPS access and persistent runtime data
- `1panel/hermes-agent`: Hermes Agent runtime image maintained by 1Panel with bundled messaging channel dependencies
- `1panel/openclaw`: OpenClaw runtime image built from official source with 1Panel-oriented customizations
- `1panel/vllm-gb10-dspark`: ARM64 vLLM runtime for DeepSeek V4 Flash on two NVIDIA GB10 nodes
- `1panel/node`: Node.js runtime image
- `1panel/php`: PHP-FPM runtime images for multiple versions
- `1panel/java`: Java JDK runtime images based on Eclipse Temurin

## PHP 8 security releases

`Build PHP 8 Security Images` builds PHP 8.2.35, 8.3.36, 8.4.27 and 8.5.12 from pinned upstream Dockerfiles, without waiting for official base image tags. See [source provenance and build instructions](php/8/upstream/README.md).

## PHP extension downloads

The PHP 5.6, PHP 7 and PHP 8 images install checksum-pinned PEAR 1.10.18 after compiling PHP. The separate 5.6/7.0–7.2 contexts first upgrade checksum-pinned Archive_Tar 1.4.14 to satisfy its dependency. PHP 5.6 uses the system CA bundle through `SSL_CERT_FILE`, with certificate verification enabled. This includes the upstream [HTTP chunked response fix](https://github.com/pear/pear-core/pull/152), which prevents PECL metadata from failing with `does not have REST info xml available`. The bootstrap uses curl and a local, offline upgrade because the older PEAR downloader cannot fetch the update reliably.

Run `bash tests/check-php-pecl.sh IMAGE` against a built image to download, compile and load APCu in a disposable container and verify a cache write/read. It selects APCu 4.0.11 for PHP 5.6 and needs network access. Run `python3 tests/check-php-pecl-source.py` for offline checks of all seven build contexts and the release wiring.

## Rebuilding PHP images

Commit and push the fixes, then select that branch in Actions. Existing images and running containers do not receive Dockerfile changes automatically.

| Action | Inputs | Published `1panel/php` tags |
| --- | --- | --- |
| Build PHP 5 Image | `php56Version=5.6.40` | `5.6.40-fpm` (amd64) |
| Build PHP 7 Legacy Images | No inputs; builds all three versions | `7.0.33-fpm`, `7.1.33-fpm`, `7.2.34-fpm` |
| Build PHP 7 Image | `buildPhp74=true`, `php74Version=7.4.33`, `php74ImageVersion=7.4.34`, `buildPhp73=true`, `php73Version=7.3.33` | `7.4.34-fpm`, `7.3.33-fpm` |
| Build PHP 8 Image | Run twice: `phpVersion=8.0.30`, then `8.1.34` | `8.0.31-fpm`, `8.1.35-fpm` |

The legacy PHP 7 Action uses the existing Dockerfiles and preserves the previous workflow's amd64/arm64/arm/v7 platform list; local PECL installation checks cover amd64 only. The alternative `php/5.6` context remains available through CNB. Both 5.6 contexts include the PECL fix.

For PHP 8.2+, rebuild only images whose PEAR is older than 1.10.17. `Build PHP 8 Security Images` rebuilds the fixed batch `8.2.35`, `8.3.36`, `8.4.27`, `8.5.12`. After publication, pull the updated base image and rebuild the 1Panel runtime.

## PHP EOL source backports

PHP 5.6.40, 7.0.33, 7.1.33, 7.2.34 and 7.3.33 builds also apply SHA256-pinned local source backports, including the alternate `php/5.6` context. The third-party starting patches have been supplemented with applicable allocation-overflow, VM and request-state changes from PHP's minimal backport. Image tags and internal PHP versions stay unchanged. Use `tests/check-php-legacy-backport.py` for source checks and `tests/check-php-legacy-runtime.py IMAGE` for actual CLI/FPM regressions. These branches remain EOL; provenance, behavior changes and validation instructions are documented below.

PHP 7.4.33, 8.0.30 and 8.1.34 builds apply the official minimal source backports for CVE-2026-109618 / CVE-2026-109619 and rebuild PHP. These branches remain EOL; older patch levels in these series now fail explicitly. `1panel/php:7.4.34-fpm`, `8.0.31-fpm` and `8.1.35-fpm` are 1Panel maintenance image tags based on official PHP 7.4.33, 8.0.30 and 8.1.34 respectively; their internal PHP versions remain unchanged. See [implementation, compatibility changes and validation](php/EOL-BACKPORT.md).

## PHP 7.3 / 7.4

The `Build PHP 7 Image` workflow (`.github/workflows/php7-release.yml`) builds PHP 7.3 and 7.4 from `php/7`, independently of PHP 8. For example:

```bash
docker build --build-arg PHP_VERSION=7.4.33 -t 1panel/php:7.4.34-fpm php/7
```

The build prepares signed Debian archive sources for Buster and Bullseye before installing packages. Archive metadata expiration checks are disabled for these sources; package signature verification stays enabled. The base image includes `libzip4` and `unzip`, so the ZIP runtime library remains available when 1Panel rebuilds a runtime using persisted extension files. Installing the ZIP extension still uses the 1Panel extension installer.

## vLLM GB10 DSpark

`1panel/vllm-gb10-dspark:0.1.1` extends the pinned Anemll DSpark GX10 `0.1.1` image with the deployment patches and DSpark proposer used by the matching 1Panel App Store package. It is published for `linux/arm64` only and requires two NVIDIA GB10 nodes, NVIDIA Container Toolkit, and a working RoCE/InfiniBand link.

## ComfyUI

The ComfyUI image supports `linux/amd64` and `linux/arm64` NVIDIA hosts and includes the same pinned PyTorch 2.13.0 CUDA 13.0 stack on both architectures. GPU operation requires a compatible NVIDIA driver (Linux 580.65.06 or newer for the current CUDA stack) and NVIDIA Container Toolkit. Each upstream stable release is published as one multi-platform image under its exact release tag plus a tag without the leading `v` (for example, `1panel/comfyui:v0.33.1` and `1panel/comfyui:0.33.1`). Docker automatically selects the matching architecture.

Start the container with Docker:

```bash
docker run -d \
  --name comfyui \
  --gpus all \
  -p 8188:8188 \
  -v comfyui-data:/data \
  1panel/comfyui:v0.33.1
```

This example exposes port `8188`, stores persistent data in the `comfyui-data` volume, and requests all NVIDIA GPUs. Change the image tag, host port, or volume name directly in the command when needed.

Models, custom nodes, inputs, outputs, user settings, and runtime-installed Python packages are stored under `/data`. ComfyUI-Manager dependencies are included; enable the manager when needed by appending `--enable-manager` to the command.

For CPU-only operation, omit `--gpus all` and append `--cpu` after the image name. CPU mode works on both architectures but is significantly slower.

The amd64 CUDA variant is intended primarily for RTX 20 series and newer GPUs. The arm64 variant targets NVIDIA's server/SBSA CUDA platforms; it must not be assumed to support every ARM device or Jetson model, which follows NVIDIA's JetPack-specific PyTorch installation path.
