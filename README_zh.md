[English](README.md) | [中文](README_zh.md)

# 1Panel Runtime Images

本仓库用于构建和发布 1Panel 使用的运行时镜像。

当前仓库主要维护以下镜像：

- `1panel/hermes-agent`
- `1panel/openclaw`
- `1panel/node`
- `1panel/php`
- `1panel/java`

## 镜像说明

- `1panel/hermes-agent`：1Panel 维护的 Hermes Agent 运行环境镜像，内置消息通道相关依赖
- `1panel/openclaw`：基于 OpenClaw 官方源码构建的运行环境镜像，包含面向 1Panel 场景的定制
- `1panel/node`：Node.js 运行环境镜像
- `1panel/php`：多个版本的 PHP-FPM 运行环境镜像
- `1panel/java`：基于 Eclipse Temurin 的 Java JDK 运行环境镜像
