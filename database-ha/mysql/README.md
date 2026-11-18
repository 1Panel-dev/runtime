# MySQL 主从镜像

基于官方 `mysql:8.4.13`，由 1Panel 维护初始化与复制入口，兼容当前应用商店 MySQL 8.4 主从包使用的环境变量和挂载路径。入口为自行实现，并非 Bitnami 源码分支，不下载 Bitnami 的二进制包。

## 当前支持版本

当前支持的具体数据库版本如下，与[版本清单](../versions.json)保持一致：

| 支持系列 | 具体数据库版本 | 完整版本标签 | 系列兼容别名 | 上游基础镜像 |
| --- | --- | --- | --- | --- |
| 8.4 | **8.4.13** | `1panel/mysql-cluster:8.4.13` | `1panel/mysql-cluster:8.4` | `mysql:8.4.13` |

上游构建版本固定为 `MYSQL_VERSION=8.4.13`，发布完整版本标签并保留指向该系列最近发布补丁的兼容别名。相同数据库版本重建时沿用完整版本标签，不添加 `r` 修订后缀，digest 可能变化；需要固定具体构建时使用 digest。

配套新应用包为 `8.4.13-master`、`8.4.13-slave`，通过 `supportVersion: 2.6` 声明最低支持 1Panel v2.6。旧包保持历史镜像，存量迁移单独处理；该门槛不代表面板已完成旧新镜像的普通升级隔离或混合节点校验。

```bash
docker build --build-arg MYSQL_VERSION=8.4.13 -t 1panel/mysql-cluster:8.4.13 database-ha/mysql
bash checks/check-mysql-cluster.sh 1panel/mysql-cluster:8.4.13
```

目标架构为 `linux/amd64` 和 `linux/arm64`，容器默认使用 UID/GID `1001:1001`。宿主机数据目录需由该用户拥有，与当前应用商店初始化脚本一致。

## 配置

| 环境变量 | 用途 |
| --- | --- |
| `MYSQL_REPLICATION_MODE` | 必填，`master` 或 `slave` |
| `MYSQL_ROOT_PASSWORD` | 必填，主库 root 密码；未执行全量导入时也用于从库 |
| `MYSQL_REPLICATION_USER`、`MYSQL_REPLICATION_PASSWORD` | 必填，复制用户与密码 |
| `MYSQL_MASTER_HOST` | 从库必填，主库地址 |
| `MYSQL_MASTER_PORT_NUMBER` | 主库端口，默认 `3306` |
| `MYSQL_MASTER_ROOT_USER` | 执行初始备份的主库用户，默认 `root` |
| `MYSQL_MASTER_ROOT_PASSWORD` | 从库必填，初始备份账户密码 |
| `MYSQL_REPLICATION_SLAVE_DUMP` | `true` 时在从库首次初始化导入主库全量数据，默认 `false` |
| `MYSQL_AUTHENTICATION_PLUGIN` | `mysql_native_password` 或 `caching_sha2_password`，默认后者 |

`MYSQL_REPLICATION_SLAVE_DUMP=true` 导入包含账户的全库备份，从库 root 密码以主库备份中的账户为准；健康检查使用 `MYSQL_MASTER_ROOT_PASSWORD`，与当前应用商店默认 root 账户配置一致。使用自定义备份账户时，需确保导入后 root 密码与健康检查凭据一致。

保留的路径：

- 数据：`/bitnami/mysql/data`
- 配置：`/opt/bitnami/mysql/conf/my.cnf`，支持只读挂载
- 健康检查：`/opt/bitnami/scripts/mysql/healthcheck.sh`
- socket、PID：`/opt/bitnami/mysql/tmp/`
- 错误日志：`/opt/bitnami/mysql/logs/mysqld.log`，镜像内链接到 `/proc/1/fd/1`

官方客户端默认配置路径 `/etc/my.cnf` 关联到上述兼容配置文件，因此面板直接调用 `mysql`、`mysqladmin`、`mysqldump` 时也会使用正确的 socket；兼容配置仍支持只读挂载。

入口覆盖配置中的数据库程序目录、插件目录、数据目录、socket、PID、错误日志、复制日志与 server ID，以兼容现有 Bitnami 布局的配置文件。从库以 `read_only`、`super_read_only` 启动。选择 `mysql_native_password` 时会显式启用 MySQL 8.4 的该认证插件。

## 日志

MySQL 引擎错误日志通过上述链接写入 PID 1 的标准输出，初始化和正常运行期间都可以通过 `docker logs <容器名>` 或面板容器日志查看。日志文件路径保留用于兼容配置，不再是镜像内独立累积的普通文件。

入口同时输出新库初始化、已有数据启动、等待主库、全量备份与导入、复制配置等阶段的进度。等待主库期间按间隔报告重试进度；阶段与重试消息不输出密码或完整认证命令。

初始化配置完成表示入口已完成当前节点的初始化和配置步骤，不代表复制 IO、SQL 线程均已运行或数据已经追平。健康检查仅验证本地 SQL 连接；复制状态仍需通过面板主从状态或 `SHOW REPLICA STATUS\G` 检查，包括 `Replica_IO_Running`、`Replica_SQL_Running` 及对应错误字段。

## 初始化与重启

首次启动主库时创建 root 与复制账户。从库全量初始化通过 `mysqldump --single-transaction --source-data=2` 获取数据与对应 binlog 位点，导入后配置复制，从该位点继续接收增量。主库已有数据时也使用该流程。

已有数据目录重启时保留复制状态，不重新导入。server ID 与节点角色随数据保存，容器重建后不变；更换主从角色会拒绝启动。首次接入不带本镜像角色标记的旧数据时，通过现有复制通道检查所选角色，不会为已有数据重新配置复制。

初始化开始前会写入 `.1panel-initializing` 标记；中断后拒绝自动继续，避免将未完整导入的从库作为正常节点运行。检查错误后，仅对该新建且未投入使用的从库数据目录清空重建，不要清理主库或已投产的数据。

## 范围

当前只支持 MySQL 8.4 主从复制，不包含自动选主、故障切换或代理，不承诺兼容全部 Bitnami 环境变量或自定义初始化脚本，也不提供跨大版本升级。

按 2026-11-16 的上游维护状态，原应用包中的 MySQL 5.7、8.0 已排除：MySQL 官方公告记录 5.7 自 2023-10-25、8.0 自 2026-04-21 转入 Sustaining Support；[8.0 发布说明](https://dev.mysql.com/doc/relnotes/mysql/8.0/en/)明确该系列随最终版本 8.0.46 在 2026 年 4 月达到 EOL。参见 [MySQL 官方 EOL 公告](https://www.mysql.com/support/eol-notice.html)。

MySQL 8.4 仍在维护，[8.4.13 发布说明](https://dev.mysql.com/doc/relnotes/mysql/8.4/en/news-8-4-13.html)列出了 2026-10-20 的更新与安全修复；[Docker 官方镜像发布清单](https://github.com/docker-library/official-images/blob/master/library/mysql)提供 8.4 的 AMD64、ARM64 镜像，当前维护构建不包含 5.7、8.0。

健康检查验证本地 SQL 连接，复制链路状态需要另行检查。旧配置如果包含 MySQL 8.4 已移除的 `default_authentication_plugin`，启动会失败；迁移前应从配置中移除该选项，镜像不会修改宿主机挂载的配置文件。

全量导入面向 InnoDB。备份期间不要执行 DDL；非事务表的快照一致性需要停写或另行设计备份。复制使用文件与位点，不自动配置 GTID 或 TLS。主从密码、网络与备份账户权限应按实际部署配置。

替换现有 `bitnamilegacy/mysql:8.4` 前，应在数据副本上验证账户、配置、复制状态与备份恢复。测试脚本验证默认客户端查询、备份恢复和复制状态，以及非空主库新增从库、增量追平、只读约束、原生密码认证、容器重建与主库重启；脚本仅清理自己创建的容器、网络和卷。

已完成 ARM64、AMD64 镜像构建，并通过两种架构的上述完整容器测试。ARM64 为本机原生运行，AMD64 在 ARM64 主机上通过仿真运行。

已在 ARM64 验证旧 `bitnamilegacy/mysql:8.4`（实际 8.4.5）单主数据迁移到本镜像 8.4.13：使用应用商店原配置与 `1001:1001` 数据目录权限，旧数据读取、新写入及重启持久化通过。旧镜像生成测试数据时省略了会触发其自身已移除配置项错误的 `MYSQL_AUTHENTICATION_PLUGIN`，切换本镜像后重新启用该变量。此结果不代表旧从库迁移、GTID 或其他自定义账户配置已经验证。
