# 数据库高可用镜像

本目录统一维护 1Panel 高可用使用的 MySQL、PostgreSQL、Redis 主从镜像。数据库引擎来自 Docker Official Images，入口负责兼容现有安装包的环境变量、挂载目录和 `1001:1001` 权限。

```text
database-ha/
├── mysql/
├── postgresql/
├── redis/
└── versions.json
```

主从复制与持久化校验脚本统一维护在仓库根目录的 [checks/](../checks/README.md)。

## 版本与标签

发布版本号与当前安装包保持一致：MySQL、Redis 使用主次版本号，PostgreSQL 使用主版本号。安装包中的 `master`、`slave` 是节点角色，同系列的主从节点使用相同镜像。

| 数据库 | 支持系列 | 固定上游镜像 | 发布标签 |
| --- | --- | --- | --- |
| MySQL | 8.4 | `mysql:8.4.13` | `1panel/mysql-cluster:8.4` |
| PostgreSQL | 15 | `postgres:15.20-bookworm` | `1panel/postgresql-cluster:15` |
| PostgreSQL | 16 | `postgres:16.16-bookworm` | `1panel/postgresql-cluster:16` |
| PostgreSQL | 17 | `postgres:17.12-bookworm` | `1panel/postgresql-cluster:17` |
| PostgreSQL | 18 | `postgres:18.7-bookworm` | `1panel/postgresql-cluster:18` |
| Redis | 6.2 | `redis:6.2.24-bookworm` | `1panel/redis-cluster:6.2` |
| Redis | 7.4 | `redis:7.4.12-bookworm` | `1panel/redis-cluster:7.4` |
| Redis | 8.10 | `redis:8.10.3-trixie` | `1panel/redis-cluster:8.10` |

[versions.json](versions.json) 是构建工作流的版本映射来源。同系列发布新补丁时，更新对应映射，通过主从运行验证后重新发布该系列标签；数据库补丁版本同时记录在镜像标签元数据 `org.opencontainers.image.version` 中。

## 版本维护范围

截至 2026-11-16，按当前 1Panel 高可用已支持的系列核对上游维护状态，并增加 PostgreSQL 18、Redis 8.10：

- MySQL 保留 8.4。5.7 已在 2023 年停止开发；8.0 已在 2026 年 4 月达到 EOL，均不纳入构建列表。[官方 EOL 公告](https://www.mysql.com/support/eol-notice.html)、[8.0 发布说明](https://dev.mysql.com/doc/relnotes/mysql/8.0/en/)
- PostgreSQL 保留 15、16、17，增加 18。13 已结束维护；14 已在 2026-11-12 发布最终版本并宣布 EOL。[官方版本策略](https://www.postgresql.org/support/versioning/)、[14 EOL 公告与当前补丁发布](https://www.postgresql.org/about/news/postgresql-187-1712-1616-1520-1425-and-19-rc-2-released-3442/)
- Redis 保留 6.2、7.4，增加当前稳定系列 8.10。6.2 仍处于上游延长安全支持；8.0 在当前官方安全政策中已列为不支持，故不纳入构建列表。官方版本周期页面对 8.0 的日期与安全支持表存在差异，本目录以当前安全补丁支持状态为准。[官方安全政策](https://github.com/redis/redis/security)、[官方版本周期](https://redis.io/docs/latest/operate/oss_and_stack/install/version-mgmt/)

以上是本目录的镜像维护范围，未修改应用商店已有安装包。历史镜像仍能下载，不作为继续维护该系列的依据。

## 构建与验证

在 runtime 仓库根目录执行：

```bash
docker build --build-arg MYSQL_VERSION=8.4.13 -t 1panel/mysql-cluster:8.4 database-ha/mysql
bash checks/check-mysql-cluster.sh 1panel/mysql-cluster:8.4

docker build --build-arg POSTGRESQL_VERSION=18.7 -t 1panel/postgresql-cluster:18 database-ha/postgresql
bash checks/check-postgresql-cluster.sh 1panel/postgresql-cluster:18

docker build --build-arg REDIS_VERSION=6.2.24 -t 1panel/redis-cluster:6.2 database-ha/redis
bash checks/check-redis-cluster.sh 1panel/redis-cluster:6.2

docker build --build-arg REDIS_VERSION=8.10.3 --build-arg REDIS_VARIANT=trixie -t 1panel/redis-cluster:8.10 database-ha/redis
bash checks/check-redis-cluster.sh 1panel/redis-cluster:8.10
```

其他系列按版本表传入固定补丁版本。Redis 6.2、7.4 使用默认 Bookworm 底座；8.10 使用 Trixie 底座，构建时需同时传入 `REDIS_VARIANT=trixie`，工作流会自动选择。详细接口及迁移限制分别见 [MySQL](mysql/README.md)、[PostgreSQL](postgresql/README.md)、[Redis](redis/README.md)。

`Build Database Replication Images` 从版本映射生成原生 amd64、arm64 构建及测试矩阵。`database=all`、`version=all` 构建全部八个系列；选择单一数据库后，可以指定该数据库的系列号。已排除的系列和未登记的版本会被拒绝。

手动运行默认只构建测试。启用 `publish` 后，全部选中任务通过才合并对应系列的多架构 manifest；发布复用仓库现有 Docker Hub Secrets。工作流尚未执行不代表远程镜像已经发布。

## 数据与升级

本目录保持现有主从复制拓扑，不包含自动选主、读写代理或 Redis Cluster 分片。持久化数据不能因更换系列标签而跨主版本直接复用；例如 PostgreSQL 17 切换至 18，仍需备份恢复或经过验证的 `pg_upgrade` 流程。Redis 6.2 的单文件 AOF 与 7.4、8.10 的多文件 AOF 也需分别验证，新增 8.10 镜像不代表已验证从旧主版本直接迁移。

测试脚本只清理本次创建的临时容器、网络和数据卷。全新主从部署、同系列补丁升级、旧 Bitnami 单主数据迁移和已有完整集群迁移分别记录验证范围，不能相互替代。
