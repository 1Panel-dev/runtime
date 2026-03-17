[English](README.md) | [中文](README_zh.md)

# 1Panel Runtime Images

本仓库用于构建和发布 1Panel 使用的运行时镜像。

当前仓库主要维护以下镜像：

- `1panel/openclaw`
- `1panel/node`
- `1panel/php`

## OpenClaw

`1panel/openclaw` 基于 OpenClaw 官方源码构建，并做了少量面向 1Panel 场景的定制。

主要特点：

1. 跟随 OpenClaw 官方版本发布节奏，按 tag 拉取上游源码进行构建
2. 默认集成 `Caddy`，用于为 OpenClaw 提供 HTTPS 反向代理能力
3. 增加 `openclaw` 命令，便于在容器中直接使用 OpenClaw 启动入口

## 安全性

`1panel/openclaw` 的一个重点是安全性。

- 默认通过集成的 `Caddy` 提供 HTTPS 访问入口，避免直接以明文 HTTP 暴露 Web 界面
- 在满足 1Panel 需求的前提下，尽量保持与 OpenClaw 上游 Docker 行为接近

## 其他镜像

- `1panel/node`：Node.js 运行环境镜像
- `1panel/php`：多个版本的 PHP-FPM 运行环境镜像
