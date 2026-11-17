# 镜像校验

`checks/` 是镜像维护者的统一校验目录，用于在修改 Dockerfile、入口脚本、源码补丁、版本或发布配置后，确认相关约定和运行行为仍然符合预期。目前覆盖 Java、PHP，以及 MySQL、PostgreSQL、Redis 主从镜像。

## 在仓库中的职责

| 位置 | 负责内容 |
| --- | --- |
| 各镜像目录 | 保存 Dockerfile、入口脚本及运行配置，实现镜像的构建和启动 |
| `checks/` | 提供可独立执行的校验脚本，验证源码、构建配置和已构建镜像的行为 |
| `.github/workflows/`、`.cnb.yml` | 编排构建和发布任务；已接入校验的任务在相应步骤调用检查脚本 |

校验脚本由维护者或 CI 执行，不参与 1Panel 用户的应用启动流程。脚本本身不构建或推送镜像；容器运行校验使用传入的镜像创建临时环境。

## 校验的三个层次

| 类型 | 主要确认什么 | 执行条件 |
| --- | --- | --- |
| 源码与配置检查 | Dockerfile、入口、版本限制、镜像标签和发布工作流是否保持一致 | 仓库源码、Shell 或 Python，无需 Docker |
| 源码补丁验证 | 源码包和补丁校验值是否正确、补丁能否应用、重复应用或输入被篡改时是否拒绝 | 本地源码包、补丁、Python 和 patch，无需 Docker |
| 容器运行回归 | 客户端能否连接、扩展能否工作、主从能否同步、重启后数据与权限是否正确 | Docker 和目标版本、目标架构的已构建镜像 |

## 脚本用途

| 脚本 | 校验内容 | 运行要求 |
| --- | --- | --- |
| [check-java-runtime.sh](check-java-runtime.sh) | Java Dockerfile、入口、发布工作流及文档的静态一致性 | Bash、仓库源码 |
| [check-php-pecl-source.py](check-php-pecl-source.py) | PHP PECL 初始化、Shell 语法及发布入口 | Python 3、Shell、仓库源码 |
| [check-php-eol-backport.py](check-php-eol-backport.py) | PHP 回补脚本、版本限制、工作流构建上下文与镜像标签 | Python 3、Shell；可传入源码及补丁目录追加校验 |
| [check-php-legacy-backport.py](check-php-legacy-backport.py) | 旧 PHP 源码包校验、补丁应用与构建失败处理 | Python 3、Shell、patch；可传入 PHP 7.3.33 源码包 |
| [check-php-pecl.sh](check-php-pecl.sh) | 容器内下载、编译、加载 APCu 并验证缓存读写 | Bash、Docker、已构建的 PHP 镜像、网络 |
| [check-php-legacy-runtime.py](check-php-legacy-runtime.py) | PHP CLI、FastCGI、OOM 恢复、扩展及上传行为 | Python 3、Docker、已构建的 PHP 镜像 |
| [check-mysql-cluster.sh](check-mysql-cluster.sh) | MySQL 默认客户端、备份恢复、全量与增量复制、只读及重启恢复 | Bash、Docker、已构建的 MySQL 主从镜像 |
| [check-postgresql-cluster.sh](check-postgresql-cluster.sh) | PostgreSQL 流复制、历史认证规则保留、配置、目录权限及数据版本保护 | Bash、Docker、已构建的 PostgreSQL 主从镜像 |
| [check-redis-cluster.sh](check-redis-cluster.sh) | Redis 主从复制、复制延迟等待、配置优先级、密码及 RDB/AOF 恢复 | Bash、Docker、已构建的 Redis 主从镜像 |

## 何时执行

| 修改内容 | 对应检查 |
| --- | --- |
| Java Dockerfile、入口或发布配置 | `check-java-runtime.sh` |
| PHP PEAR/PECL 初始化或扩展安装配置 | 先运行 `check-php-pecl-source.py`，构建后运行 `check-php-pecl.sh` |
| PHP 源码补丁、回补脚本、版本限制或维护标签 | 按版本范围运行两个 backport 源码检查，构建后运行 `check-php-legacy-runtime.py` |
| 数据库基础版本、初始化、认证、复制或持久化逻辑 | 构建受影响的版本和架构，运行对应的 `check-*-cluster.sh` |

## 执行方式

每个脚本独立执行，按修改范围选择。以下命令均在仓库根目录运行。

源码与构建配置检查默认离线执行：

```bash
bash checks/check-java-runtime.sh
python3 checks/check-php-pecl-source.py
python3 checks/check-php-eol-backport.py
python3 checks/check-php-legacy-backport.py
```

追加完整源码验证时，传入对应的本地输入：

```bash
python3 checks/check-php-legacy-backport.py /path/to/php-7.3.33.tar.xz
python3 checks/check-php-eol-backport.py /path/to/source-inputs
```

第二条命令所需的源码包、补丁文件名和版本范围见 [PHP 回补说明](../php/EOL-BACKPORT.md)。不传额外输入时，部分源码检查会跳过，具体范围以脚本输出为准。

容器运行校验在构建对应镜像后执行：

```bash
bash checks/check-php-pecl.sh PHP_IMAGE
python3 checks/check-php-legacy-runtime.py PHP_IMAGE
bash checks/check-mysql-cluster.sh 1panel/mysql-cluster:8.4.13
bash checks/check-postgresql-cluster.sh 1panel/postgresql-cluster:18.7
bash checks/check-redis-cluster.sh 1panel/redis-cluster:8.10.3
```

将 `PHP_IMAGE` 替换为待验证的 PHP 镜像名称。数据库示例使用完整版本标签，指向本地构建的待发布候选镜像；CI 传入的是同一候选的架构标签，例如 `1panel/redis-cluster:8.10.3-arm64`。校验不依赖镜像先行发布。数据库镜像构建方法与支持版本见 [database-ha](../database-ha/README.md)。

数据库校验使用唯一名称创建临时容器、网络和数据卷，结束时清理本次创建的资源。PHP 运行校验同样使用临时容器；PECL 校验会在容器中联网下载和编译扩展。

## 与 CI 和发布的关系

三个数据库校验脚本已接入 [Build Database Replication Images](../.github/workflows/database-cluster-release.yml)：

- 涉及数据库源码或数据库校验脚本的 PR，会触发对应工作流，从版本清单生成 amd64、arm64 构建及运行校验任务。
- 每个任务先构建 `<完整版本>-amd64` 或 `<完整版本>-arm64` 候选镜像，再将该镜像传给对应的 `check-*-cluster.sh`；该项校验失败会阻止该项镜像推送。
- PR 只构建和校验。手动运行时 `publish` 默认为 `false`；启用后才推送已验证的完整版本架构镜像，并在全部选中任务通过后，为完整版本标签和系列兼容别名发布多架构 manifest，不添加 `r` 修订后缀。同数据库版本重建会沿用标签，digest 可能变化；固定具体构建时使用 digest。

本目录中的 Java、PHP 校验脚本目前由维护者手动执行，尚未在现有发布工作流中调用。

## 如何理解检查结果

- 退出码 `0` 表示本次实际执行的检查项通过；非零表示失败，需要结合报错和容器日志定位。
- `SKIP` 表示该项未验证。例如没有提供 PHP 7.3.33 源码包时，其源码校验会跳过，不能据此认定该项通过。
- 源码检查通过后，仍需对构建出的镜像执行运行校验。容器检查的结论限定于本次镜像版本、架构和脚本覆盖的场景。
- 配套新数据库应用包最低支持 1Panel v2.6（`supportVersion: 2.6`），旧包保持历史镜像。镜像校验不验证面板的旧新镜像升级隔离或混合节点校验。
- 生产旧数据迁移、跨主版本升级和真实多机部署需要单独验证；一次临时环境检查不覆盖这些场景。

维护时沿用 `check-*` 命名，将共享校验集中放在本目录，并在本说明中补齐用途、输入和依赖。涉及仓库文件时，通过脚本自身位置定位仓库根目录，保持从不同工作目录执行的行为一致。
