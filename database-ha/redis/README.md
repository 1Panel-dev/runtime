# Redis 主从镜像

基于 Docker Official Image 的 Debian 版本，由 1Panel 维护当前应用高可用安装包需要的启动接口。支持 Redis 6.2、7.4 和 8.10，默认使用 `redis:7.4.12-bookworm`，构建目标为 `linux/amd64` 和 `linux/arm64`。不下载 Bitnami 二进制包，也不包含其完整脚本库。

## 当前支持版本

当前支持的具体数据库版本如下，与[版本清单](../versions.json)保持一致：

| 支持系列 | 具体数据库版本 | 镜像标签 | 上游基础镜像 |
| --- | --- | --- | --- |
| 6.2 | **6.2.24** | `1panel/redis-cluster:6.2` | `redis:6.2.24-bookworm` |
| 7.4 | **7.4.12** | `1panel/redis-cluster:7.4` | `redis:7.4.12-bookworm` |
| 8.10 | **8.10.3** | `1panel/redis-cluster:8.10` | `redis:8.10.3-trixie` |

按 2026-11-16 核对的[官方安全支持政策](https://github.com/redis/redis/security)，6.2 处于延长安全支持期，7.4 和 8.10 仍受支持，8.0 已标为不支持，因此不再构建原安装包中的 8.0 系列。[版本周期页面](https://redis.io/docs/latest/operate/oss_and_stack/install/version-mgmt/)与安全政策对 8.0 的状态存在冲突，此处以当前安全补丁支持状态作为筛选依据，不推断其准确 EOL 日期。

在仓库根目录构建：

```bash
docker build --build-arg REDIS_VERSION=6.2.24 -t 1panel/redis-cluster:6.2 database-ha/redis
IMAGE=1panel/redis-cluster:6.2 bash checks/check-redis-cluster.sh
docker build --build-arg REDIS_VERSION=7.4.12 -t 1panel/redis-cluster:7.4 database-ha/redis
IMAGE=1panel/redis-cluster:7.4 bash checks/check-redis-cluster.sh
docker build --build-arg REDIS_VERSION=8.10.3 --build-arg REDIS_VARIANT=trixie -t 1panel/redis-cluster:8.10 database-ha/redis
IMAGE=1panel/redis-cluster:8.10 bash checks/check-redis-cluster.sh
```

`REDIS_VERSION` 用于选择受支持系列的补丁版本，默认 `7.4.12`；`REDIS_VARIANT` 用于选择上游 Debian 发行版，默认 `bookworm`。6.2 和 7.4 使用 Debian 12 Bookworm，8.10 使用 Debian 13 Trixie；官方没有 `8.10.3-bookworm` 标签，因此构建 8.10 时需要同时指定两个参数。发行版差异影响基础系统和依赖包，运行时的环境变量、目录和 UID/GID 约定保持一致。

运行时使用 `1001:1001`，宿主机挂载目录需要按现有应用包初始化脚本设置该所有者。

| 环境变量 | 用途 |
| --- | --- |
| `REDIS_REPLICATION_MODE` | `master` 或 `slave`，默认 `master`；其他值启动失败 |
| `REDIS_PASSWORD` | 本节点密码，必填 |
| `REDIS_MASTER_HOST` | 主节点地址，从节点必填 |
| `REDIS_MASTER_PORT_NUMBER` | 从节点连接的主节点端口，默认 `6379` |
| `REDIS_MASTER_PASSWORD` | 主节点密码，从节点必填，可与本节点密码不同 |
| `REDIS_EXTRA_FLAGS` | 追加的 Redis 启动参数 |

保留的挂载路径：

- 数据：`/bitnami/redis/data`
- 外部配置：`/opt/bitnami/redis/mounted-etc/redis.conf`
- 日志：`/opt/bitnami/redis/logs`

配置优先级与当前 Bitnami 安装包保持一致：存在外部配置时，将其复制为运行配置，跳过密码、复制关系和持久化默认配置的注入；不存在外部配置时，启用 AOF、关闭定时 RDB 快照，按环境变量生成认证和主从关系。日志默认输出到标准输出，挂载的日志目录可供外部配置中的 `logfile` 使用。

外部配置之后依次应用 `REDIS_EXTRA_FLAGS`、命令行参数，后者优先级更高。当前应用包主节点挂载的配置为 `appendonly no`，从节点未挂载配置，默认 `appendonly yes`，该差异保留。外部配置中的 `dir`、端口和其他参数由配置文件决定。

`REDIS_EXTRA_FLAGS` 沿用原脚本按空白分词的行为，不执行 Shell 表达式，也不解释其中的 Shell 引号。针对当前应用包的 `--requirepass ${REDIS_PASSWORD}`，入口将整段密码作为单个参数处理，可保留空格、引号、反斜杠、美元符号等字符。其他带空白的参数值请通过配置文件或容器命令参数数组传入。

本镜像只提供固定主从复制，不提供 Sentinel 自动选主、Redis Cluster 分片或主节点故障后的自动切换。替换镜像不会改变现有复制拓扑。升级应先在数据副本上验证同版本换镜像，再验证同系列补丁升级；不要直接复用跨大版本升级后写入的数据进行降级。6.2 使用单文件 AOF，7.4 和 8.10 使用多文件 AOF；配置文件和数据需要与目标系列匹配，不能将含 `appenddirname` 等新配置的 7.4、8.10 配置直接套给 6.2。

验证脚本使用唯一名称创建容器、网络和数据卷，测试不同密码、非默认端口、连续写入、主节点重启持久化、从节点离线 AOF 恢复和重新连接，并根据镜像的 `REDIS_VERSION` 检查对应的单文件或多文件 AOF。复制就绪和重连通过轮询从库中的新值确认；脚本还通过 `CLIENT PAUSE WRITE` 制造受控复制延迟，先确认旧值仍可读取，再等待新值，避免将不同连接上的 `WAIT` 当作同步屏障。脚本仅清理本次创建的资源，不等同于旧 Bitnami 数据升级或真实多主机部署验证。

8.10.3 已在本地 ARM64 原生和 AMD64 QEMU 环境通过基础主从、密码、持久化与重连测试。另在 ARM64 使用当前应用包 `8.0-master` 的原始配置和新生成的测试数据，验证了 8.10.3 启动、读写、`SAVE` 和 RDB 重启恢复；该结果仅说明配置兼容，不代表旧 8.0 数据迁移已验证。

6.2.24 另已在本地 ARM64 使用当前应用包 `6.2-master` 的原始配置验证启动、写入、RDB 保存和重启恢复；在该配置上通过命令行显式开启 AOF 后，单文件 `appendonly.aof` 的异常退出恢复也已通过。这不等同于旧 Bitnami 6.2 数据迁移验证。

另已在本地 ARM64 验证 `bitnamilegacy/redis:7.4`（Redis 7.4.3）到本镜像 7.4.12 的单主节点迁移：使用当前应用包 `7.4-master` 的原始配置和测试生成的 RDB，旧值读取、新值写入、`SAVE` 和重启恢复均通过。数据目录按现有初始化脚本设置为 `1001:1001`；测试使用 `volume-nocopy` 保留目录权限，避免 Docker 将旧镜像的目录权限复制到空数据卷。这不覆盖旧 AOF、多节点存量迁移或其他历史权限、配置组合；迁移前需要核对目录对 UID `1001` 可写，本镜像不会自动修改已有数据的所有者。

Redis 及上游镜像的许可证随基础镜像保留，发布前应按所选 Redis 版本核对其许可证要求。
