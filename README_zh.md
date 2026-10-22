[English](README.md) | [中文](README_zh.md)

# 1Panel Runtime Images

本仓库用于构建和发布 1Panel 使用的运行时镜像。

当前仓库主要维护以下镜像：

- `1panel/comfyui`
- `1panel/deepseek-harness`
- `1panel/hermes-agent`
- `1panel/openclaw`
- `1panel/vllm-gb10-dspark`
- `1panel/node`
- `1panel/php`
- `1panel/java`

## 镜像说明

- `1panel/comfyui`：面向 NVIDIA GPU、严格基于上游稳定 Release 构建的 ComfyUI 运行环境镜像
- `1panel/deepseek-harness`：由 1Panel 维护的 DeepSeek Harness 镜像，提供 HTTPS 访问和运行数据持久化
- `1panel/hermes-agent`：1Panel 维护的 Hermes Agent 运行环境镜像，内置消息通道相关依赖
- `1panel/openclaw`：基于 OpenClaw 官方源码构建的运行环境镜像，包含面向 1Panel 场景的定制
- `1panel/vllm-gb10-dspark`：用于在两台 NVIDIA GB10 节点上部署 DeepSeek V4 Flash 的 ARM64 vLLM 运行环境镜像
- `1panel/node`：Node.js 运行环境镜像
- `1panel/php`：多个版本的 PHP-FPM 运行环境镜像
- `1panel/java`：基于 Eclipse Temurin 的 Java JDK 运行环境镜像

## PHP 8 安全版本

`Build PHP 8 Security Images` 从固定上游提交的 Dockerfile 构建 PHP 8.2.35、8.3.36、8.4.27 和 8.5.12，不依赖尚未发布的官方基础镜像标签。详见[源码来源和构建说明](php/8/upstream/README.md)。

## PHP 扩展下载

PHP 5.6、PHP 7 和 PHP 8 镜像在编译 PHP 后安装固定版本、校验 SHA256 的 PEAR 1.10.18。独立的 5.6/7.0–7.2 构建目录先离线升级固定版本并校验 SHA256 的 Archive_Tar 1.4.14，以满足其依赖。PHP 5.6 通过 `SSL_CERT_FILE` 使用系统 CA 证书包，保留证书校验。其中包含上游的 [HTTP 分块响应修复](https://github.com/pear/pear-core/pull/152)，避免 PECL 元数据解析报 `does not have REST info xml available`。通过 curl 下载后离线升级，避免旧版 PEAR 下载器无法下载自身更新。

构建镜像后运行 `bash tests/check-php-pecl.sh IMAGE`，在临时容器中下载、编译、加载 APCu 并检查缓存读写。PHP 5.6 自动选择 APCu 4.0.11，此检查需要联网。运行 `python3 tests/check-php-pecl-source.py` 可离线检查全部七个构建目录及发布入口。

## 重新发布 PHP 镜像

先提交并推送修复，在 Actions 中选择包含修复的分支。已发布镜像和运行中的容器不会自动获得 Dockerfile 修改。

| Action | 参数 | 发布的 `1panel/php` 标签 |
| --- | --- | --- |
| Build PHP 5 Image | `php56Version=5.6.41` | `5.6.41-fpm`（amd64） |
| Build PHP 7 Legacy Images | 无参数，一次构建三个版本 | `7.0.34-fpm`、`7.1.34-fpm`、`7.2.35-fpm` |
| Build PHP 7 Image | `buildPhp74=true`、`php74Version=7.4.33`、`php74ImageVersion=7.4.34`、`buildPhp73=true`、`php73Version=7.3.33`、`php73ImageVersion=7.3.34` | `7.4.34-fpm`、`7.3.34-fpm` |
| Build PHP 8 Image | 分别运行两次：`phpVersion=8.0.30`、`8.1.34` | `8.0.31-fpm`、`8.1.35-fpm` |

旧 PHP 7 Action 使用已有 Dockerfile，保留此前工作流的 amd64/arm64/arm/v7 平台列表；本地 PECL 安装验证仅覆盖 amd64。备用 `php/5.6` 构建目录仍可通过 CNB 选择，两个 5.6 目录均包含 PECL 修复。

PHP 8.2+ 仅在镜像内 PEAR 低于 1.10.17 时需要为本问题重打。`Build PHP 8 Security Images` 会重建固定的 `8.2.35`、`8.3.36`、`8.4.27`、`8.5.12` 四个版本。发布后重新拉取基础镜像，再重建 1Panel 运行环境。

## PHP EOL 源码回补

PHP 5.6.40、7.0.33、7.1.33、7.2.34 和 7.3.33 的构建也会应用固定 SHA256 的本地源码回补。补丁以第三方回补为起点，并补齐官方最小回补中适用于各旧分支的分配溢出、VM 和请求状态清理等改动；备用 `php/5.6` 入口同样覆盖。维护版镜像标签分别为 `5.6.41-fpm`、`7.0.34-fpm`、`7.1.34-fpm`、`7.2.35-fpm`、`7.3.34-fpm`，内部 PHP 版本仍保留上述真实基线。源码校验使用 `tests/check-php-legacy-backport.py`，实际 CLI/FPM 回归使用 `tests/check-php-legacy-runtime.py IMAGE`。这些旧分支仍为 EOL，详细来源、行为变化和验证方式见下方说明。

PHP 7.4.33、8.0.30 和 8.1.34 构建会应用官方针对 CVE-2026-109618 / CVE-2026-109619 的最小源码回补并重新编译 PHP。这些分支仍为 EOL，同系列更早的补丁版本现在会明确失败。`1panel/php:7.4.34-fpm`、`8.0.31-fpm` 和 `8.1.35-fpm` 为 1Panel 维护版镜像标签，分别基于官方 PHP 7.4.33、8.0.30、8.1.34 加上述回补，内部 PHP 版本保持原值。详见[实现、兼容性变化和验证说明](php/EOL-BACKPORT.md)。

## PHP 7.3 / 7.4

`Build PHP 7 Image` 工作流（`.github/workflows/php7-release.yml`）从 `php/7` 构建 PHP 7.3 和 7.4，与 PHP 8 分开维护。例如：

```bash
docker build --build-arg PHP_VERSION=7.4.33 -t 1panel/php:7.4.34-fpm php/7
```

构建时先将 Buster 和 Bullseye 的软件源切换到 Debian 官方签名归档，再安装依赖；仅对这些归档源关闭元数据过期检查，保留软件包签名校验。基础镜像内置 `libzip4` 和 `unzip`，因此 1Panel 重建运行环境并加载已保存的扩展文件时，ZIP 运行库仍然可用。ZIP 扩展本身仍通过 1Panel 的扩展安装脚本安装。

## vLLM GB10 DSpark

`1panel/vllm-gb10-dspark:0.1.1` 基于固定的 Anemll DSpark GX10 `0.1.1` 镜像，加入对应 1Panel 应用商店版本使用的部署补丁和 DSpark proposer。该镜像仅发布 `linux/arm64`，要求两台 NVIDIA GB10 节点、NVIDIA Container Toolkit 和可用的 RoCE/InfiniBand 链路。

## ComfyUI

ComfyUI 镜像支持 `linux/amd64` 和 `linux/arm64` NVIDIA 主机，两种架构均内置相同版本并锁定的 PyTorch 2.13.0 CUDA 13.0 依赖。GPU 模式要求宿主机安装兼容的 NVIDIA 驱动（当前 CUDA 依赖在 Linux 上要求 580.65.06 或更新版本）和 NVIDIA Container Toolkit。每个上游稳定 Release 都会以同一个多架构镜像发布同名标签和去掉 `v` 前缀的兼容标签（例如 `1panel/comfyui:v0.33.1` 与 `1panel/comfyui:0.33.1`），Docker 会自动选择与宿主机匹配的架构。

使用 Docker 启动容器：

```bash
docker run -d \
  --name comfyui \
  --gpus all \
  -p 8188:8188 \
  -v comfyui-data:/data \
  1panel/comfyui:v0.33.1
```

该示例对外提供 `8188` 端口，将持久化数据保存在 `comfyui-data` 卷中，并申请宿主机上的全部 NVIDIA GPU。需要时可直接修改命令中的镜像标签、宿主机端口或卷名。

模型、自定义节点、输入输出、用户配置以及运行时安装的 Python 包都会保存在 `/data`。镜像已安装 ComfyUI-Manager 依赖，如需启用，可在命令末尾追加 `--enable-manager`。

如需在纯 CPU 主机运行，请移除 `--gpus all`，并在镜像名称后追加 `--cpu`。两种架构都可使用 CPU 模式，但运行速度会明显降低。

amd64 CUDA 镜像主要面向 RTX 20 系列及更新显卡；arm64 镜像面向 NVIDIA 服务器/SBSA CUDA 平台，不能据此认为所有 ARM 设备或 Jetson 型号都受支持，Jetson 需要按 NVIDIA 的 JetPack 专用 PyTorch 路线部署。
