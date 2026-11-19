[English](README.md) | [中文](README_zh.md)

# 1Panel Container Images

This repository builds and publishes container images used by 1Panel, covering AI agents, language runtimes, model inference and high availability databases.

## Image categories

| Category | Images |
| --- | --- |
| AI agents | `1panel/deepseek-harness`, `1panel/hermes-agent`, `1panel/openclaw` |
| Language runtimes | `1panel/node`, `1panel/php`, `1panel/java` |
| Model inference and generation | `1panel/vllm`, `1panel/comfyui` |
| Database replication | `1panel/mysql-cluster`, `1panel/postgresql-cluster`, `1panel/redis-cluster` |

## Images

- `1panel/comfyui`: ComfyUI runtime image for NVIDIA GPUs, built from matching upstream stable releases
- `1panel/deepseek-harness`: DeepSeek Harness image maintained by 1Panel with HTTPS access and persistent runtime data
- `1panel/hermes-agent`: Hermes Agent runtime image maintained by 1Panel with bundled messaging channel dependencies
- `1panel/openclaw`: OpenClaw runtime image built from official source with 1Panel-oriented customizations
- `1panel/vllm`: ARM64 vLLM runtimes for two-node DeepSeek V4 Flash and four-node DeepSeek V4.1 Flash on NVIDIA GB10, plus a synced AMD64 DeepSeek 4.1 Flash variant
- `1panel/node`: Node.js runtime image
- `1panel/php`: PHP-FPM runtime images for multiple versions
- `1panel/java`: Java JDK runtime images based on Eclipse Temurin
- `1panel/mysql-cluster`: MySQL primary/replica image with 1Panel installation package compatibility
- `1panel/postgresql-cluster`: PostgreSQL streaming replication image with 1Panel installation package compatibility
- `1panel/redis-cluster`: Redis primary/replica image with 1Panel installation package compatibility

## Repository layout

| Path | Purpose |
| --- | --- |
| `deepseek-harness/`, `hermes-agent/`, `openclaw/` | Agent image sources and startup configuration |
| `node/`, `php/`, `java/` | Language runtime images and version-specific build files |
| `vllm-gb10-dual-node/`, `comfyui/` | Model inference and generation images and deployment adaptations |
| [database-ha/](database-ha/README.md) | Database replication image sources and supported version mappings |
| [checks/](checks/README.md) | Source, configuration, patch and container runtime checks |
| `.github/workflows/`, `.cnb.yml`, `.cnb/` | Build, validation, publication and repository synchronization workflows |

## Database replication images

Database image sources and supported version mappings are grouped under [database-ha/](database-ha/README.md). Their runtime checks are maintained in the shared [checks/](checks/README.md) directory.

| Image | Full version tags | Series aliases |
| --- | --- | --- |
| `1panel/mysql-cluster` | `8.4.13` | `8.4` |
| `1panel/postgresql-cluster` | `15.20`, `16.16`, `17.12`, `18.7` | `15`, `16`, `17`, `18` |
| `1panel/redis-cluster` | `6.2.24`, `7.4.12`, `8.10.3` | `6.2`, `7.4`, `8.10` |

Full version tags use the upstream database patch versions pinned in [versions.json](database-ha/versions.json), without an `r` revision suffix. Rebuilding the same database version reuses its full version tag and may change the digest; use a digest to pin a specific build. Series aliases follow the existing version rules: MySQL and Redis use major.minor; PostgreSQL uses the major version. Each alias points to its latest published patch. Primary and replica nodes use the same image with different replication environment variables.

`Build Database Replication Images` builds and checks each selected series on native amd64 and arm64 runners using `<full-version>-amd64` and `<full-version>-arm64` candidate tags. Select a database and series, or use `all` to build every supported entry. Manual runs default to build and test only; enabling `publish` pushes the verified architecture images and, after all selected builds pass, publishes multi-platform manifests under both the full version tag and its series alias, for example `1panel/postgresql-cluster:17.12` and `1panel/postgresql-cluster:17`.

The companion new App Store packages use full database patch versions with `-master` or `-slave` suffixes and require 1Panel v2.6 through `supportVersion: 2.6`. Historical packages retain their historical images; migration of existing clusters needs a separate procedure. This minimum panel version does not mean panel-side safeguards against ordinary upgrades from old to new images or mixed-generation nodes have been implemented.

The supported list includes the existing 1Panel HA series still maintained upstream and adds PostgreSQL 18 and Redis 8.10. MySQL 5.7/8.0 and PostgreSQL 13/14 have reached EOL; Redis 8.0 is marked unsupported in the upstream security policy. See [support decisions and upstream sources](database-ha/README.md#版本维护范围).

These images provide primary/replica replication. Existing cluster migration, cross-major database upgrades and automatic failover require separate procedures and validation.

## Image checks

[checks/](checks/README.md) provides a shared validation entry point for maintainers and CI. Its nine scripts comprise four offline checks and five container checks:

| Check type | Scope |
| --- | --- |
| Source and configuration | Dockerfiles, entrypoints, version constraints, image tags and release workflow consistency |
| Source patches | Checksums, patch application and rejection of repeated application or tampered inputs |
| Container behavior | PHP extensions and CLI/FPM behavior, database client connections, backup and restore, replication and restart persistence |

The database build workflow runs the corresponding container check after building each version and architecture. The Java and PHP scripts in this directory currently run manually. Image builds and publication are controlled by the workflows; checks run independently of application startup.

Run the relevant offline checks before building, then validate the built image for each affected version and architecture before publication. A successful check covers the cases actually executed; `SKIP` identifies cases that were not verified. The directory guide lists commands, dependencies and validation boundaries.

## PHP 8 security releases

`Build PHP 8 Security Images` builds PHP 8.2.36, 8.3.37, 8.4.28 and 8.5.13 from pinned upstream Dockerfiles, without waiting for official base image tags. See [source provenance and build instructions](php/8/upstream/README.md).

## PHP extension downloads

The PHP 5.6, PHP 7 and PHP 8 images install checksum-pinned PEAR 1.10.18 after compiling PHP. The separate 5.6/7.0–7.2 contexts first upgrade checksum-pinned Archive_Tar 1.4.14 to satisfy its dependency. PHP 5.6 uses the system CA bundle through `SSL_CERT_FILE`, with certificate verification enabled. This includes the upstream [HTTP chunked response fix](https://github.com/pear/pear-core/pull/152), which prevents PECL metadata from failing with `does not have REST info xml available`. The bootstrap uses curl and a local, offline upgrade because the older PEAR downloader cannot fetch the update reliably.

Run `bash checks/check-php-pecl.sh IMAGE` against a built image to download, compile and load APCu in a disposable container and verify a cache write/read. It selects APCu 4.0.11 for PHP 5.6 and needs network access. Run `python3 checks/check-php-pecl-source.py` for offline checks of all seven build contexts and the release wiring.

## Rebuilding PHP images

Commit and push the fixes, then select that branch in Actions. Existing images and running containers do not receive Dockerfile changes automatically.

| Action | Inputs | Published `1panel/php` tags |
| --- | --- | --- |
| Build PHP 5 Image | `php56Version=5.6.41` | `5.6.41-fpm` (amd64) |
| Build PHP 7 Legacy Images | No inputs; builds all three versions | `7.0.34-fpm`, `7.1.34-fpm`, `7.2.35-fpm` |
| Build PHP 7 Image | `buildPhp74=true`, `php74Version=7.4.33`, `php74ImageVersion=7.4.34`, `buildPhp73=true`, `php73Version=7.3.33`, `php73ImageVersion=7.3.34` | `7.4.34-fpm`, `7.3.34-fpm` |
| Build PHP 8 Image | Run twice: `phpVersion=8.0.30`, then `8.1.34` | `8.0.31-fpm`, `8.1.35-fpm` |

The legacy PHP 7 Action uses the existing Dockerfiles and preserves the previous workflow's amd64/arm64/arm/v7 platform list; local PECL installation checks cover amd64 only. The alternative `php/5.6` context remains available through CNB. Both 5.6 contexts include the PECL fix.

For PHP 8.2+, rebuild only images whose PEAR is older than 1.10.17. `Build PHP 8 Security Images` rebuilds the fixed batch `8.2.36`, `8.3.37`, `8.4.28`, `8.5.13`. After publication, pull the updated base image and rebuild the 1Panel runtime.

## PHP EOL source backports

PHP 5.6.40, 7.0.33, 7.1.33, 7.2.34 and 7.3.33 builds also apply SHA256-pinned local source backports, including the alternate `php/5.6` context. The third-party starting patches have been supplemented with applicable allocation-overflow, VM and request-state changes from PHP's minimal backport. The maintenance image tags are `5.6.41-fpm`, `7.0.34-fpm`, `7.1.34-fpm`, `7.2.35-fpm` and `7.3.34-fpm`; internal PHP versions retain the real baselines above. Use `checks/check-php-legacy-backport.py` for source checks and `checks/check-php-legacy-runtime.py IMAGE` for actual CLI/FPM regressions. These branches remain EOL; provenance, behavior changes and validation instructions are documented below.

PHP 7.4.33, 8.0.30 and 8.1.34 builds apply the official minimal source backports for CVE-2026-109618 / CVE-2026-109619 and rebuild PHP. These branches remain EOL; older patch levels in these series now fail explicitly. `1panel/php:7.4.34-fpm`, `8.0.31-fpm` and `8.1.35-fpm` are 1Panel maintenance image tags based on official PHP 7.4.33, 8.0.30 and 8.1.34 respectively; their internal PHP versions remain unchanged. See [implementation, compatibility changes and validation](php/EOL-BACKPORT.md).

## PHP 7.3 / 7.4

The `Build PHP 7 Image` workflow (`.github/workflows/php7-release.yml`) builds PHP 7.3 and 7.4 from `php/7`, independently of PHP 8. For example:

```bash
docker build --build-arg PHP_VERSION=7.4.33 -t 1panel/php:7.4.34-fpm php/7
```

The build prepares signed Debian archive sources for Buster and Bullseye before installing packages. Archive metadata expiration checks are disabled for these sources; package signature verification stays enabled. The base image includes `libzip4` and `unzip`, so the ZIP runtime library remains available when 1Panel rebuilds a runtime using persisted extension files. Installing the ZIP extension still uses the 1Panel extension installer.

## vLLM GB10 Dual Node

`1panel/vllm:0.25-optimized-for-2-gb10-ds-v4-flash` extends the pinned Anemll DSpark GX10 `0.1.1` image with the deployment patches and DSpark proposer used by the matching 1Panel App Store package. The `0.25` tag prefix identifies the vLLM version series; the base image's validated vLLM runtime version is `0.25.2.dev0+g752a3a504.d20260714`. It is published for `linux/arm64` only and requires two NVIDIA GB10 nodes, NVIDIA Container Toolkit, and a working RoCE/InfiniBand link.

## vLLM GB10 Four Node

`1panel/vllm:20261107-optimized-for-4-gb10-ds-v4.1-flash` mirrors `juilpark/spark-ds41f:1107-homelab-045eba05` for DeepSeek V4.1 Flash on four NVIDIA GB10 nodes, preserving the source image contents. The tag prefix `20261107` identifies the upstream release date; packaging revisions use `.1`, `.2`, etc. The image targets `linux/arm64` only and requires four NVIDIA GB10 nodes, NVIDIA Container Toolkit, and a working RoCEv2 switch network.

Publish the image by manually running `Sync vLLM GB10 Four Node Image` with `sourceImageVersion` and `imageVersion`. Inference compatibility must be verified on the target cluster.

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
