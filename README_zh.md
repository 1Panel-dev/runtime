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
