# Codex 执行指令：在生产服务器上部署一套与生产完全隔离的 sub2api 测试环境

> 交给 Codex 在**生产服务器**上执行。目标是用新版本 sub2api（main 分支 `70116315d` 或更新）起一套**测试环境**，给原生 iOS 管理端联调用，并验证数据库迁移能跑通。
>
> **最高优先级：不能影响生产的任何工作。** 下面第 1 节的红线，只要有一条可能被触碰，立即停下来，向用户报告，不要自作主张绕过。

## 0. 第二次执行须知（2026-10-22 第一次执行停在镜像构建，本版已据报告修订）

第一次执行的报告在 `sub2test-20261022/REPORT.md`。确认过的事实和本版的改动：

- **生产的真实容器**是 `linapi-sub2api-rolling-rpm-60s-20261015-green`（应用，蓝绿部署，回环端口 18136）、`linapi-sub2api-postgres`、`linapi-sub2api-redis`，不是文档旧版写的 `sub2api`。本版改为开工时用 `docker ps` 识别并记下“受保护容器清单”（第 1.0 节），之后所有检查都以这份清单为准。生产将来可能换成 blue / 其他名字，每次都要重新识别。
- **生产版本**是 `e5ab7e4f4`（旧镜像只按这个提交构建）。
- **18080 已被占用**，测试端口用 18081（或 18080–18099 里第一个空闲的）。
- **构建方式改了**：不要再起独立的 BuildKit 容器（第一次在它里面因 `mkdir /sys/fs/cgroup/buildkit: read-only file system` 失败），直接用宿主 Docker 守护进程自带的默认构建器（`docker build`，守护进程内置 BuildKit）。这台主机有 128 核、约 239 GiB 可用内存，构建不会挤占生产；不需要也不要为构建另配 cgroup、特权或改主机安全配置。
- **Dockerfile 用 `deploy/Dockerfile`**：仓库根目录的 `Dockerfile` 不打包 `/app/migration-preflight`，`deploy/Dockerfile` 打包了（构建上下文仍是仓库根目录）。第一次执行做的 `Dockerfile.test`（根 Dockerfile 加 preflight 的补丁副本）也可以用，二选一，报告里写明用的哪个。
- **清理第一次留下的构建器资源**（都属于 sub2test，可以删）：已停止的 `sub2test-builder` 容器、`sub2test-build-net` 网络、`sub2test_buildkit` 卷；`moby/buildkit` 镜像先用 `docker ps -a --filter ancestor=moby/buildkit` 确认没有其他容器在用，再删。
- **不要对生产执行 `docker exec`**（旧版第 5 节写过一个只读 exec，已删除，与红线冲突时以红线为准）。
- 第一次执行留下的 `/opt/sub2test/src`、`/opt/sub2test/old` 可以复用；先 `git -C /opt/sub2test/src fetch && git -C /opt/sub2test/src checkout <最新 main>`。

---

## 1. 红线（任何一步违反都必须中止并报告）

### 1.0 开工第一步：识别并记下受保护对象

```bash
docker ps --format '{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
docker network ls; docker volume ls
```

把**所有不以 `sub2test` 开头**的容器、网络、卷都视为生产或他人的资源，写进报告的“受保护清单”。其中 sub2api 应用容器（目前是 `linapi-sub2api-rolling-rpm-60s-*`，蓝绿部署可能是 green 或 blue）记为 `$PROD_APP`，它的回环端口记为 `$PROD_PORT`（`docker port $PROD_APP`）。下面所说的“生产容器”都指这份清单。

1. **不碰生产的容器、镜像、卷、网络、端口、配置和数据库。**
   - 不得对受保护清单里的任何容器执行 `stop`、`restart`、`rm`、`exec`、`update`、`compose up` / `down` / `pull`。只允许只读的 `docker ps`、`docker inspect`、`docker port`、`docker stats --no-stream`。
   - 不得修改生产的 compose 文件、`.env`、`config.yaml`、`data/` 目录，也不得运行 `deploy/upgrade-compose.sh`。
   - 不得连接生产数据库或生产 Redis，包括只读查询。测试环境的迁移验证只用测试库里自己造的数据。
   - 不得删除、改标签或覆盖生产正在使用的镜像（`docker inspect $PROD_APP --format '{{.Config.Image}}'` 查到的那个），也不得执行 `docker image prune`、`docker system prune`、`docker volume prune`、`docker network prune`、`docker builder prune`。
2. **测试环境一律用独立名字。**
   - compose 项目名固定为 `sub2test`。
   - 容器名、卷名、网络名都以 `sub2test` 开头。
   - 镜像标签用 `sub2api-test:<commit>`。
   - 所有 `docker compose` 命令都必须带 `-p sub2test -f <测试目录>/docker-compose.test.yml`，不能依赖默认值。
3. **测试环境不对公网开放。**
   - 只绑定 `127.0.0.1`，端口从 18080–18099 里选第一个空闲的（`ss -ltn` 确认；第一次执行时 18080 已被占用，用的是 18081），在报告里写明。
   - 不改生产的反向代理（Caddy、Nginx）、防火墙或 DNS。
   - App 联调通过 SSH 隧道访问（见第 6 节）。
4. **测试环境不能对外产生真实副作用。**
   - 不配置 SMTP，告警邮件不能发出去。
   - 不配置 APNs 私钥。
   - 推送出站开关保持默认关闭。
   - 不导入任何生产上游账号或凭据，测试用的上游 Key 只用明显虚构的值。
   - 关闭自动更新：sub2api 的在线更新只在有人手动触发时执行，没有后台自动更新。不要在 Web 里点“检查更新 / 更新并重启”，也不要设置 `UPDATE_GITHUB_TOKEN`。
5. **资源有上限，不能挤占生产。**
   - 测试的 PostgreSQL 用小参数：`max_connections=50`、`shared_buffers=128MB`、`maintenance_work_mem=64MB`。
   - 给三个测试容器都设 CPU 和内存上限，例如 app `cpus: 1.0`、`mem_limit: 1g`，postgres `cpus: 1.0`、`mem_limit: 1g`，redis `cpus: 0.5`、`mem_limit: 256m`。
   - 开始之前先看主机资源：`free -h`、`df -h`、`nproc`、`docker stats --no-stream`。可用内存不足 3GB 或磁盘可用不足 15GB 时，停下来报告。
   - 镜像构建用宿主 Docker 守护进程的默认构建器即可（见第 0 节），客户端命令用 `nice -n 19 ionice -c3` 运行。构建期间每 2 分钟看一次生产健康（第 6 条）。
6. **每一步之后确认生产仍然健康。**
   - 执行 `docker inspect $PROD_APP --format '{{.State.Status}} {{.State.Health.Status}} {{.State.StartedAt}} {{.RestartCount}}'`，结果应为 `running healthy`，启动时间和重启次数与开工时一致；生产 postgres、redis 容器同样检查。
   - 执行 `curl -fsS http://127.0.0.1:$PROD_PORT/health`，期望 200 `{"status":"ok"}`。
   - 如果生产出现任何异常，立即停止测试环境（`docker compose -p sub2test ... stop`），然后报告。

---

## 2. 准备

```bash
# 2.1 记录生产现状（只读），写进报告留作对照
docker ps --format '{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
docker inspect $PROD_APP --format '{{.Config.Image}} {{.Image}}'   # $PROD_APP 见第 1.0 节
docker volume ls; docker network ls
free -h; df -h; nproc

# 2.2 测试目录（与生产部署目录完全分开）
export T=/opt/sub2test
sudo mkdir -p $T && sudo chown "$USER" $T && cd $T
```

如果服务器上已经有 sub2 仓库，不要在生产部署用的那份仓库里切换分支或拉取代码，另外克隆一份：

```bash
git clone https://github.com/chengzixqq/sub2api.git $T/src
cd $T/src && git checkout main && git log --oneline -1   # 记下提交号，应为 70116315d 或更新
```

---

## 3. 构建测试镜像（低优先级，不覆盖任何已有标签）

```bash
cd $T/src
COMMIT=$(git rev-parse --short HEAD)
# 宿主守护进程的默认构建器；deploy/Dockerfile 会打包 /app/migration-preflight
DOCKER_BUILDKIT=1 nice -n 19 ionice -c3 docker build -t sub2api-test:$COMMIT -f deploy/Dockerfile .
docker image inspect sub2api-test:$COMMIT --format '{{.Id}}'
docker run --rm --entrypoint /app/migration-preflight sub2api-test:$COMMIT --help >/dev/null 2>&1 && echo preflight-packaged
```

- 不要用 `deploy/build_image.sh`，它会打 `sub2api:latest` 标签，可能和生产重名。
- 不要起独立的 BuildKit 容器、不要为构建授予特权或改主机 cgroup / AppArmor / sysctl。
- 构建失败时把完整错误贴进报告，然后停下。

---

## 4. 测试用 compose 文件

把下面内容写到 `$T/docker-compose.test.yml`。这份文件和生产的 compose 毫无关系：容器名、卷、网络都是 `sub2test` 前缀，只绑定 127.0.0.1。

```yaml
name: sub2test
services:
  app:
    image: ${SUB2TEST_IMAGE:?set SUB2TEST_IMAGE}
    container_name: sub2test-app
    restart: "no"
    ports:
      - "127.0.0.1:${SUB2TEST_PORT:-18080}:8080"
    volumes:
      - sub2test_app_data:/app/data
    environment:
      - AUTO_SETUP=true
      - SERVER_HOST=0.0.0.0
      - SERVER_PORT=8080
      - SERVER_MODE=release
      - RUN_MODE=standard
      - DATABASE_HOST=postgres
      - DATABASE_PORT=5432
      - DATABASE_USER=sub2test
      - DATABASE_PASSWORD=${SUB2TEST_DB_PASSWORD:?}
      - DATABASE_DBNAME=sub2test
      - DATABASE_SSLMODE=disable
      - REDIS_HOST=redis
      - REDIS_PORT=6379
      - REDIS_PASSWORD=${SUB2TEST_REDIS_PASSWORD:?}
      - REDIS_DB=0
      - ADMIN_EMAIL=${SUB2TEST_ADMIN_EMAIL:?}
      - ADMIN_PASSWORD=${SUB2TEST_ADMIN_PASSWORD:?}
      - JWT_SECRET=${SUB2TEST_JWT_SECRET:?}
      - TOTP_ENCRYPTION_KEY=${SUB2TEST_TOTP_KEY:?}
      - TZ=Asia/Shanghai
    depends_on:
      postgres: { condition: service_healthy }
      redis: { condition: service_healthy }
    networks: [sub2test-net]
    cpus: 1.0
    mem_limit: 1g
  postgres:
    image: postgres:18-alpine
    container_name: sub2test-postgres
    restart: "no"
    command: postgres -c max_connections=50 -c shared_buffers=128MB -c maintenance_work_mem=64MB
    environment:
      - PGDATA=/var/lib/postgresql/data
      - POSTGRES_USER=sub2test
      - POSTGRES_PASSWORD=${SUB2TEST_DB_PASSWORD:?}
      - POSTGRES_DB=sub2test
      - TZ=Asia/Shanghai
    volumes:
      - sub2test_pg:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U sub2test -d sub2test"]
      interval: 5s
      retries: 30
    networks: [sub2test-net]
    cpus: 1.0
    mem_limit: 1g
  redis:
    image: redis:8-alpine
    container_name: sub2test-redis
    restart: "no"
    command: ["redis-server", "--appendonly", "yes", "--requirepass", "${SUB2TEST_REDIS_PASSWORD:?}"]
    environment:
      - REDISCLI_AUTH=${SUB2TEST_REDIS_PASSWORD:?}
    volumes:
      - sub2test_redis:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      retries: 30
    networks: [sub2test-net]
    cpus: 0.5
    mem_limit: 256m
volumes:
  sub2test_app_data:
  sub2test_pg:
  sub2test_redis:
networks:
  sub2test-net:
    driver: bridge
```

写之前先核对：`docker-compose.yml` 里 app 服务实际读取的环境变量名（`AUTO_SETUP`、`DATABASE_*`、`REDIS_*`、`ADMIN_*`、`JWT_SECRET`、`TOTP_ENCRYPTION_KEY` 等），以源码仓库 `deploy/docker-compose.yml` 和 `deploy/.env.example` 为准。名字对不上就按源码改，并在报告里注明。

`$T/.env.test`（权限 600，不提交、不外发）：

```bash
cat > $T/.env.test <<EOF
SUB2TEST_IMAGE=sub2api-test:$COMMIT
SUB2TEST_PORT=18081   # 第 1 节第 3 条选出的空闲端口
SUB2TEST_DB_PASSWORD=$(openssl rand -hex 16)
SUB2TEST_REDIS_PASSWORD=$(openssl rand -hex 16)
SUB2TEST_JWT_SECRET=$(openssl rand -hex 32)
SUB2TEST_TOTP_KEY=$(openssl rand -hex 32)
SUB2TEST_ADMIN_EMAIL=admin@sub2test.local
SUB2TEST_ADMIN_PASSWORD=$(openssl rand -base64 18 | tr -d '/+=')
EOF
chmod 600 $T/.env.test
```

统一用这个别名，保证每条命令都带项目名和文件：

```bash
alias dct='docker compose -p sub2test --env-file /opt/sub2test/.env.test -f /opt/sub2test/docker-compose.test.yml'
dct config >/dev/null && echo compose-ok
```

---

## 5. 迁移验证（只用造的数据，不碰生产）

目的：证明从**当前生产版本**升级到新版本时，迁移 247–257 能在已有数据的库上顺利执行，不报错，数据不丢。

1. **确定生产版本**：第一次执行已确认生产是 `e5ab7e4f4`。只用 `docker inspect $PROD_APP` 的镜像标签与镜像标签上的 label 核对，不要 `docker exec` 进生产容器。
2. **用旧版本起测试库**：用 `$T/old`（检出 `e5ab7e4f4`）构建 `sub2api-test-old:e5ab7e4f4`（同第 3 节的命令，旧版用哪个 Dockerfile 都行，旧镜像不需要 preflight）；把 `.env.test` 里的 `SUB2TEST_IMAGE` 换成旧镜像，执行 `dct up -d`，等健康检查通过。
3. **造数据**：只调用测试环境的接口，地址是 `http://127.0.0.1:<测试端口>`，管理员账号密码见 `.env.test`。数据要覆盖新迁移涉及的表：
   - 若干用户（含余额）；
   - 2 个分组；
   - 5 个账号，Key 用虚构值，例如 `sk-test-...`，其中包括 error 状态和停用状态；
   - 兑换码（生成、兑换各若干条）；
   - 管理员余额调整；
   - 1 条告警规则；
   - 若干 API Key。

   用量和日志数据可以直接写 SQL 插入测试库，只能用 `dct exec postgres psql -U sub2test -d sub2test`。记下各表的行数。
4. **升级**：
   - 先跑迁移预检。不要带 `--require-no-pending`，预期结果是只有 pending，没有 missing、extra 或 checksum 不一致：

     ```bash
     SUB2TEST_IMAGE=sub2api-test:$COMMIT dct run --rm --no-deps -T --entrypoint /app/migration-preflight app
     ```

   - 然后把 `SUB2TEST_IMAGE` 换回新镜像，执行 `dct up -d app`，并记录迁移耗时（看 app 日志里迁移开始和结束的时间）。
5. **核对**：
   - 应用健康。
   - `schema_migrations` 里 247–257 都已应用。
   - 第 3 步记下的各表行数没有减少。
   - 新列和新索引都存在：`\d accounts`、`\d admin_user_adjustments`、`\d redeem_codes`。
   - 老数据在新版本里能正常读取：用户列表、账号列表、兑换码列表、余额历史都返回 200。
6. **再验一次全新安装**：执行 `dct down -v`（只删 sub2test 的卷），用新镜像从零启动一次，确认全新库也能完成全部迁移。

---

## 6. 新版本功能冒烟（测试环境上）

- `GET /health` 返回 200。
- `POST /api/v1/auth/login`（带 `client{type:"ios",device_id}` 和 `X-Device-ID`）登录成功，然后 `GET /api/v1/admin/me` 返回 capabilities 列表。
- 抽查新接口，每个都要 200 或符合预期：
  - `dashboard/home`
  - `dashboard/rates`
  - `accounts?include_counts=1`
  - `accounts/runtime/batch`
  - `meta/catalog`
  - `ops/alert-events/counts`
  - `users/:id/balance-history`
  - `redeem-codes/stats`
  - `push/devices`（列表）
  - `auth/sessions`
- 错误路径：用过期 token 访问返回 401 `TOKEN_EXPIRED`；`PUT /admin/users/:id` 带 `balance` 返回 400。
- 在测试的 PostgreSQL 里确认两条 P95/P99 延迟告警规则存在。测试环境不配邮件，所以就算触发也不会发信。
- **给 App 联调用的访问方式**：在开发机（Mac）上执行 `ssh -N -L 18080:127.0.0.1:<测试端口> <服务器>`，然后让模拟器里的 App 连 `http://127.0.0.1:18080`。不要开放公网端口。真机不能用开发机的回环地址，真机联调另行安排。

---

## 7. 交付与报告

完成后输出一份报告（中文），内容包括：

1. 测试环境的地址：服务器上的 `127.0.0.1:18080`，以及 SSH 隧道命令。
2. 管理员账号。密码不要写进报告，只说明在 `/opt/sub2test/.env.test` 里。
3. 镜像标签与提交号，包括旧版本和新版本。
4. 迁移验证结果：模拟的旧版本、每个迁移的耗时、各表行数对比、全新安装是否成功。
5. 冒烟结果：逐条列出“通过 / 失败 + 响应”。
6. **生产健康对照**：开始前、每一步之后、结束时的生产容器状态和 `/health` 结果，证明生产没有受影响。
7. 资源占用：`docker stats --no-stream` 中 sub2test 三个容器的数据。
8. 遇到的任何问题和你的处理方式。凡是触碰过红线边缘的操作，都要单独列出来。

**不要做的事**：
- 不要宣布“可以上生产”。
- 不要对生产做任何升级、迁移或预检。
- 生产部署要等开发方另行通知，并以 `DEPLOY-NOTES.md` 为准。

---

## 8. 测试环境的维护与清理

- 更新到新提交：重新执行第 3 步构建新标签，改 `.env.test` 的 `SUB2TEST_IMAGE`，然后 `dct up -d app`。
- 暂停：`dct stop`。
- 彻底清理：`dct down -v`，再执行 `docker image rm sub2api-test:<标签> sub2api-test-old:<标签>`，最后 `rm -rf /opt/sub2test`。只删 sub2test 自己的东西。
