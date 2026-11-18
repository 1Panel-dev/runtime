# PostgreSQL 主从复制镜像

基于 Docker Official Image `postgres:<版本>-bookworm`，在官方初始化脚本上适配 1Panel PostgreSQL 集群安装包。数据库及系统软件包来自官方镜像，不使用 Bitnami 镜像或其二进制下载服务。构建参数 `POSTGRESQL_VERSION` 默认为 `18.7`，面向 `linux/amd64` 和 `linux/arm64`。

## 当前支持版本

当前支持的具体数据库版本如下，与[版本清单](../versions.json)保持一致：

| 支持系列 | 具体数据库版本 | 完整版本标签 | 系列兼容别名 | 上游基础镜像 |
| --- | --- | --- | --- | --- |
| 15 | **15.20** | `1panel/postgresql-cluster:15.20` | `1panel/postgresql-cluster:15` | `postgres:15.20-bookworm` |
| 16 | **16.16** | `1panel/postgresql-cluster:16.16` | `1panel/postgresql-cluster:16` | `postgres:16.16-bookworm` |
| 17 | **17.12** | `1panel/postgresql-cluster:17.12` | `1panel/postgresql-cluster:17` | `postgres:17.12-bookworm` |
| 18 | **18.7** | `1panel/postgresql-cluster:18.7` | `1panel/postgresql-cluster:18` | `postgres:18.7-bookworm` |

发布完整版本标签并保留指向各系列最近发布补丁的兼容别名。相同数据库版本重建时沿用完整版本标签，不添加 `r` 修订后缀，digest 可能变化；需要固定具体构建时使用 digest。

配套新应用包使用完整补丁版本加 `-master`、`-slave` 后缀，例如 `17.12-master`、`17.12-slave`，通过 `supportVersion: 2.6` 声明最低支持 1Panel v2.6。旧包保持历史镜像，存量迁移单独处理；该门槛不代表面板已完成旧新镜像的普通升级隔离或混合节点校验。

支持范围以 2026-11-16 为准。PostgreSQL 13 已于 2025-11-13 结束维护；PostgreSQL 14 的 2026-11-12 最后一次发布公告已明确宣布结束维护，因此不再提供这两个系列。[官方版本维护策略](https://www.postgresql.org/support/versioning/)、[PostgreSQL 14 EOL 公告及当前补丁版本](https://www.postgresql.org/about/news/postgresql-187-1712-1616-1520-1425-and-19-rc-2-released-3442/)。

```bash
docker build -t 1panel/postgresql-cluster:18.7 database-ha/postgresql
docker build --build-arg POSTGRESQL_VERSION=17.12 -t 1panel/postgresql-cluster:17.12 database-ha/postgresql
```

支持单主、多从的异步流复制。首次启动从库通过 `pg_basebackup` 获取主库已有数据，之后持续接收 WAL。主从可以位于不同主机，通过主库可访问的地址和映射端口连接。该镜像不提供自动选主、故障转移或读写代理；从库长时间离线且所需 WAL 已被回收时，需要运维人员备份并重建从库。

## 环境变量

| 变量 | 用途 | 默认值 |
| --- | --- | --- |
| `POSTGRESQL_REPLICATION_MODE` | 节点角色，`master` 或 `slave` | `master` |
| `POSTGRESQL_PASSWORD` | 初始化 `postgres` 超级用户密码 | 新主库必填 |
| `POSTGRESQL_REPLICATION_USER` | 专用复制账号，不能为 `postgres` | 必填 |
| `POSTGRESQL_REPLICATION_PASSWORD` | 复制账号密码 | 必填 |
| `POSTGRESQL_MASTER_HOST` | 从库连接的主库地址 | 从库必填 |
| `POSTGRESQL_MASTER_PORT_NUMBER` | 从库连接的主库端口 | `5432` |
| `POSTGRESQL_PORT_NUMBER` | 当前节点内部监听端口 | `5432` |
| `POSTGRESQL_DATABASE` | 新主库初始化的数据库 | `postgres` |

以上包含现有 1Panel PostgreSQL 15–17 主从安装包使用的所有环境变量，并非 Bitnami 全部变量的完整实现，PostgreSQL 18 沿用相同接口。主库每次启动均确保复制账号存在并应用复制密码；已有数据库的超级用户密码不会随环境变量重置。复制地址、账号和密码不支持换行；引号、反斜杠、冒号、空格、美元符号等按 PostgreSQL 的 SQL、连接参数及密码文件规则转义。

## 数据与配置

- 数据卷挂载到 `/bitnami/postgresql`，实际数据库目录为 `/bitnami/postgresql/data`。
- PostgreSQL 18 同样沿用上述兼容目录；其官方基础镜像默认目录已改为 `/var/lib/postgresql/18/docker`，这里由入口脚本显式设置 `PGDATA`，仍须挂载 `/bitnami/postgresql`。
- 配置可以单独持久化到 `/bitnami/postgresql/conf`，沿用安装包的 `./data:/bitnami/postgresql/conf` 挂载方式。
- 运行用户和组为 `1001:1001`。绑定挂载的目录必须预先赋予该用户读写权限，现有安装包的 `scripts/init.sh` 已执行对应初始化。显式以 root 启动时仅在准备目录后切换至 postgres 用户运行数据库。
- 已有 `postgresql.conf` 和 `pg_hba.conf` 会保留。外部认证配置不存在时原样复制数据目录中的 `pg_hba.conf`，包括从库通过 `pg_basebackup` 获取的认证文件，不额外放宽普通登录的 IP 白名单。新主库初始化时生成允许远程 TCP `scram-sha-256` 密码认证的默认规则；两处认证文件都缺失时，默认规则还包含本地 socket `peer` 认证。这不会恢复旧镜像内部未持久化的自定义授权规则。主库仍会幂等追加允许密码认证的复制规则。主库自定义配置应保证 `listen_addresses`、`wal_level=replica` 和 `max_wal_senders` 支持远程复制。
- 数据目录、认证配置路径、本地 socket 路径和内部端口由入口脚本指定。复制密码存放于配置卷的 `replication.pgpass`，权限为 `0600`，不会放入连接命令参数。
- 支持官方镜像的 `/docker-entrypoint-initdb.d` 初始化目录，仅在新主库初始化时执行。

已有完整数据时直接重启，不重新初始化或克隆。没有 `PG_VERSION` 的非空数据目录会拒绝启动；克隆失败时仅移除本次创建的临时备份目录，不删除已有数据。已有主库目录不能直接当从库运行，已有从库也不能通过修改环境变量自动提升为主库。

## 日志

入口阶段日志采用 UTC 时间、级别和节点角色格式，例如 `2026-11-18T00:00:00Z [INFO] PostgreSQL cluster (master): ...`，写入标准错误，可通过 `docker logs <容器名>` 或面板容器日志查看。日志覆盖参数校验、新主库初始化、从库全量克隆、复制角色配置、已有数据启动，以及配置和认证文件的保留或生成。

从库克隆前后输出阶段消息，`pg_basebackup --verbose` 提供等待 checkpoint、接收 WAL 等原生进度；克隆失败会保留 PostgreSQL 的错误诊断并输出失败摘要，不增加自动重试或改变现有数据清理范围。入口阶段消息不输出密码、完整连接串、SQL 或启动命令。

默认配置下，PostgreSQL 引擎日志写入标准错误，容器日志可同时显示初始化和正常运行日志。入口不覆盖用户的 `log_destination`、`logging_collector` 等日志设置；自定义为文件、syslog 或其他目标时，应到对应目标查看引擎日志，容器日志中的入口阶段消息仍然保留。自定义 SQL 日志设置及初始化脚本的输出由使用者管理。

`Startup configuration complete` 仅表示入口配置步骤完成，不代表引擎已就绪、从库已开始流复制或数据已经追平。健康检查及主从复制状态需分别确认。

## 旧数据迁移边界

支持 PostgreSQL 15–18 各自主版本内的新建主从和本镜像数据的重复启动。已在 ARM64 隔离环境中验证 `bitnamilegacy/postgresql:17` 的 PostgreSQL 17.6 单主样本切换到本镜像 17.12：独立的数据卷和配置卷保持 `1001:1001` 权限，原表可读取，新数据可写入并在重启后保留。该样本缺失的配置及认证文件由本镜像生成默认值，旧镜像内部未持久化的自定义认证规则不会恢复。

以上是隔离单主样本验证，不代表所有生产集群均可直接替换镜像。扩展、不同 locale、Bitnami 专属配置路径以及已有从库的迁移仍需单独验证。正式迁移前应完整备份并在隔离环境演练；复杂配置可采用从旧主库逻辑备份、恢复到新主库后重新创建从库的方式。

不同主版本的数据不能直接复用，例如 PostgreSQL 17 数据不能直接挂到 `:18.7` 镜像。脚本检测到数据主版本与镜像不匹配会拒绝启动并保留数据；跨主版本需使用备份恢复或经过验证的 `pg_upgrade` 流程。新增 PostgreSQL 18 镜像不意味着已实现 17→18 的数据库迁移。

## 验证

```bash
IMAGE=1panel/postgresql-cluster:18.7 bash checks/check-postgresql-cluster.sh
```

验证脚本从镜像读取 `PG_MAJOR`，使用唯一名称的临时网络、容器和卷，覆盖新库远程 SCRAM 认证、已有数据及从库克隆认证文件的白名单允许与拒绝、两处认证文件缺失时的默认规则、持续复制、重复启动、独立配置卷、非默认端口、特殊字符密码、异主版本数据安全拒绝及失败时保留已有目录。日志校验按容器本次启动时间截取，检查启动阶段、最终启动之后的引擎 ready 日志、克隆失败摘要及配置密码未出现在日志中，避免历史日志或临时服务器日志造成误判。只清理本次创建的资源。
