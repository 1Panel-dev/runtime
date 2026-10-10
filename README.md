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

## PHP 7.3 / 7.4

The `Build PHP 7 Image` workflow (`.github/workflows/php7-release.yml`) builds PHP 7.3 and 7.4 from `php/7`, independently of PHP 8. For example:

```bash
docker build --build-arg PHP_VERSION=7.4.33 -t 1panel/php:7.4.33-fpm php/7
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
