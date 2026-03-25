[English](README.md) | [中文](README_zh.md)

# 1Panel Runtime Images

This repository contains runtime images used by 1Panel.

Current images in this repository:

- `1panel/openclaw`
- `1panel/node`
- `1panel/php`

## OpenClaw

`1panel/openclaw` is built from the official OpenClaw source with a small set of 1Panel-oriented customizations.

Key points:

1. It follows official OpenClaw releases and builds from upstream tags
2. It stays close to the upstream OpenClaw Docker build flow while adding a small set of 1Panel-specific runtime dependencies
3. It includes `clawhub`, `skillhub`, and a curated default `OPENCLAW_DOCKER_APT_PACKAGES` set for common media and scripting workflows

## Security

Security is one of the main considerations for `1panel/openclaw`.

- The image stays as close as practical to the upstream OpenClaw Docker behavior while keeping only the customizations needed by 1Panel
- It avoids bundling an extra reverse-proxy process inside the image, which keeps the runtime surface smaller and simpler

## Other Images

- `1panel/node`: Node.js runtime image
- `1panel/php`: PHP-FPM runtime images for multiple versions
