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
2. It integrates `Caddy` by default to provide HTTPS reverse proxy for OpenClaw
3. It adds an `openclaw` command for easier startup and in-container usage

## Security

Security is one of the main considerations for `1panel/openclaw`.

- HTTPS is provided through bundled `Caddy` instead of exposing the web UI directly over plain HTTP
- The image stays as close as practical to the upstream OpenClaw Docker behavior while keeping only the customizations needed by 1Panel

## Other Images

- `1panel/node`: Node.js runtime image
- `1panel/php`: PHP-FPM runtime images for multiple versions
