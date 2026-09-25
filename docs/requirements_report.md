# 요구사항 수행 내역서

Docker(Ubuntu 22.04 컨테이너, `agent-monitor`)로 재현한 환경에서 2026-09-25에 직접 실행하여 얻은 실제 결과입니다. "예상값"이 아니라 전부 `docker exec agent-monitor ...`로 캡처한 진짜 출력입니다.

## 0. 환경 구성

```bash
docker compose up --build -d
```

`scripts/entrypoint.sh`가 컨테이너 기동 시 계정/그룹 생성, SSH/방화벽 설정, 디렉토리/권한/ACL 구성, 환경변수 등록, cron 등록, 앱 실행을 전부 자동으로 수행합니다.

## 1. SSH 보안 설정

검증 명령:

```bash
grep -E '^(Port|PermitRootLogin)' /etc/ssh/sshd_config
ss -tulnp | grep -E ':(20022)'
```

실제 결과:

```text
Port 20022
PermitRootLogin no

tcp   LISTEN 0      128          0.0.0.0:20022      0.0.0.0:*    users:(("sshd",pid=283,fd=3))
tcp   LISTEN 0      128             [::]:20022         [::]:*    users:(("sshd",pid=283,fd=4))
```

SSH 기본 포트 22 대신 20022를 사용해 무작위 스캔/자동 공격 노출을 줄이고, `PermitRootLogin no`로 root 계정의 원격 직접 로그인을 차단해 계정 추적성과 최소 권한 원칙을 강화합니다.

## 2. 방화벽 설정

검증 명령:

```bash
ufw status verbose
```

실제 결과:

```text
Status: active
Logging: on (low)
Default: deny (incoming), allow (outgoing), deny (routed)

To                         Action      From
--                         ------      ----
20022/tcp                  ALLOW IN    Anywhere
15034/tcp                  ALLOW IN    Anywhere
20022/tcp (v6)             ALLOW IN    Anywhere (v6)
15034/tcp (v6)             ALLOW IN    Anywhere (v6)
```

기본 정책이 `deny incoming`이고, 그 위에 SSH/앱 포트 2개만 예외로 허용해 "필요한 포트만 허용"을 만족합니다.

## 3. 계정/그룹/ACL

검증 명령:

```bash
id agent-admin; id agent-dev; id agent-test
getent group agent-common
getent group agent-core
```

실제 결과:

```text
uid=1000(agent-admin) gid=1002(agent-admin) groups=1002(agent-admin),1000(agent-common),1001(agent-core)
uid=1001(agent-dev) gid=1003(agent-dev) groups=1003(agent-dev),1000(agent-common),1001(agent-core)
uid=1002(agent-test) gid=1004(agent-test) groups=1004(agent-test),1000(agent-common)
agent-common:x:1000:agent-admin,agent-dev,agent-test
agent-core:x:1001:agent-admin,agent-dev
```

`agent-test`는 `agent-core`에 속하지 않아 API 키/로그 디렉토리에는 접근할 수 없고, 공용 업로드 디렉토리(`agent-common`)만 접근 가능합니다. 아래 5번에서 실제로 차단되는 것을 증명했습니다.

## 4. 디렉토리/권한/ACL 실접근 테스트

검증 명령:

```bash
ls -ld /home/agent-admin/agent-app/upload_files /home/agent-admin/agent-app/api_keys /var/log/agent-app
ls -l /home/agent-admin/agent-app/api_keys/t_secret.key /home/agent-admin/agent-app/bin/monitor.sh
getfacl -p /home/agent-admin/agent-app/upload_files /home/agent-admin/agent-app/api_keys /var/log/agent-app
```

실제 결과:

```text
drwxrws---+ 2 agent-admin agent-core   4096 Sep 25 10:14 /home/agent-admin/agent-app/api_keys
drwxrws---+ 2 agent-admin agent-common 4096 Sep 25 10:14 /home/agent-admin/agent-app/upload_files
drwxrws---+ 2 agent-admin agent-core   4096 Sep 25 10:15 /var/log/agent-app

-rw-rw---- 1 agent-admin agent-core   19 Sep 25 10:14 api_keys/t_secret.key
-rwxr-x--- 1 agent-dev   agent-core 3321 Sep 25 10:14 bin/monitor.sh
```

setgid(2770)로 디렉토리 안에 새로 생기는 파일도 자동으로 같은 그룹을 물려받도록 했고, `getfacl`로 `default:group:agent-core:rwx` / `default:group:agent-common:rwx` 기본 ACL이 걸려있는 것도 확인했습니다.

**실접근 차단 증명** (agent-test는 agent-core 그룹이 아니므로):

```bash
runuser -u agent-test -- ls /home/agent-admin/agent-app/api_keys
```

```text
ls: cannot access '/home/agent-admin/agent-app/api_keys': Permission denied
```

## 5. 환경 변수

검증 명령:

```bash
cat /etc/profile.d/agent-app.sh
runuser -u agent-dev -- bash -lc 'echo $AGENT_HOME $AGENT_PORT $AGENT_UPLOAD_DIR $AGENT_KEY_PATH $AGENT_LOG_DIR'
```

실제 결과:

```text
export AGENT_HOME=/home/agent-admin/agent-app
export AGENT_PORT=15034
export AGENT_UPLOAD_DIR=/home/agent-admin/agent-app/upload_files
export AGENT_KEY_PATH=/home/agent-admin/agent-app/api_keys
export AGENT_LOG_DIR=/var/log/agent-app

/home/agent-admin/agent-app 15034 /home/agent-admin/agent-app/upload_files /home/agent-admin/agent-app/api_keys /var/log/agent-app
```

**중요 트러블슈팅 메모**: 제공된 `agent-app` 바이너리는 `AGENT_KEY_PATH`를 "키 파일 경로"가 아니라 "키 디렉토리 경로"로 검증합니다. 과제 명세는 `.../api_keys/t_secret.key`(파일)를 요구하지만, 실제 바이너리는 그 디렉토리 안의 `secret.key` 파일 내용을 확인합니다. 그래서 `AGENT_KEY_PATH=.../api_keys`(디렉토리)로 지정하고, 안에 명세용 `t_secret.key`와 앱 검증용 `secret.key`를 동일한 내용(`agent_api_key_test`)으로 함께 생성해 두 요구사항을 모두 만족시켰습니다.

## 6. 애플리케이션 실행 확인 (Boot Sequence)

실제 컨테이너 기동 로그:

```text
>>> Starting Agent Boot Sequence...
[1/5] Checking User Account               [OK]
   ... Running as service user 'agent-admin' (uid=1000)
[2/5] Verifying Environment Variables     [OK]
   ... All required Envs correct
[3/5] Checking Required Files             [OK]
   ... Verified 'secret.key' with correct key string.
[4/5] Checking Port Availability          [OK]
   ... Port 15034 is available.
[5/5] Verifying Log Permission            [OK]
   ... Log directory is writable: /var/log/agent-app
------------------------------------------------------------
All Boot Checks Passed!
Agent READY
```

포트 리슨 확인:

```text
tcp   LISTEN 0      1            0.0.0.0:15034      0.0.0.0:*    users:(("agent-app",pid=296,fd=4))
```

## 7. monitor.sh

- 경로: `/home/agent-admin/agent-app/bin/monitor.sh`
- 소유자/그룹/권한: `agent-dev:agent-core`, `0750` (실측 확인됨)
- Health Check: 프로세스(`agent-app`) 존재 + 포트 15034 LISTEN, 비정상 시 `[ERROR]` + `exit 1`
- 방화벽 상태: 비활성 시 `[WARNING]`만 출력, 스크립트는 계속 진행 (비종료)
- 수집: CPU/MEM/DISK 사용률, 임계값 CPU>20%, MEM>10%, DISK>80% 초과 시 `[WARNING]`

**정상 실행 결과**:

```text
====== SYSTEM MONITOR RESULT ======

[HEALTH CHECK]
Checking process 'agent-app'... [OK] (PID: 294)
Checking port 15034... [OK]
[OK] UFW active

[RESOURCE MONITORING]
CPU Usage : 0.3%
MEM Usage : 19.4%
DISK Used  : 4%
[WARNING] MEM threshold exceeded (19.4% > 10%)

[INFO] Log appended: /var/log/agent-app/monitor.log
EXIT_CODE=0
```

**비정상(프로세스 강제 종료 후) 실행 결과** — 헬스체크 실패를 실제로 재현:

```bash
kill 294   # agent-app 프로세스 강제 종료
runuser -u agent-admin -- bash -lc 'source /etc/profile.d/agent-app.sh; /home/agent-admin/agent-app/bin/monitor.sh; echo "종료코드=$?"'
```

```text
[ERROR] process 'agent-app' is not running
종료코드=1
```

이후 앱을 재기동하면 다시 `[OK]`/`exit 0`으로 정상 복귀하는 것도 확인했습니다.

## 8. monitor.log 누적 + cron 자동 실행

crontab 등록 확인:

```bash
crontab -u agent-admin -l
```

```text
* * * * * . /etc/profile.d/agent-app.sh; /home/agent-admin/agent-app/bin/monitor.sh >> /var/log/agent-app/monitor-cron.out 2>&1
17 3 * * * . /etc/profile.d/agent-app.sh; /home/agent-admin/agent-app/bin/archive-agent-logs.sh >> /var/log/agent-app/archive-cron.out 2>&1
```

1분 간격 자동 증가 실증 (사람이 실행하지 않고 cron만으로 3연속 자동 기록됨):

```text
[2026-09-25 10:47:01] PID:1285 CPU:0.3% MEM:19.0% DISK_USED:4%
[2026-09-25 10:48:02] PID:1285 CPU:0.3% MEM:20.1% DISK_USED:4%
[2026-09-25 10:49:01] PID:1285 CPU:1.5% MEM:20.1% DISK_USED:4%
```

`agent-admin`은 `agent-core` 그룹에 속해 있어 `/var/log/agent-app/monitor.log`(그룹 agent-core, 2770)에 기록할 수 있습니다.

## 9. 보너스 1 — report.sh

```bash
runuser -u agent-admin -- bash -lc 'source /etc/profile.d/agent-app.sh; /home/agent-admin/agent-app/bin/report.sh'
```

실제 결과:

```text
====== STATISTICS REPORT ======
[CPU]
Average : 0.6%
Maximum : 0.9% at 2026-09-25 10:15:02
Minimum : 0.3% at 2026-09-25 10:15:19
[Memory]
Average : 19.0%
Maximum : 19.4% at 2026-09-25 10:15:19
Minimum : 18.7% at 2026-09-25 10:15:02
[Disk]
Average : 4.0%
Maximum : 4.0% at 2026-09-25 10:15:02
Minimum : 4.0% at 2026-09-25 10:15:02
[Samples]
Data Points: 2 samples
```

## 10. 보너스 2 — 로그 보존 정책(archive-agent-logs.sh)

```bash
runuser -u agent-admin -- bash -lc 'source /etc/profile.d/agent-app.sh; /home/agent-admin/agent-app/bin/archive-agent-logs.sh'
```

실제 결과:

```text
[INFO] no log files older than 7 days
[INFO] no archives older than 30 days
```

7일 경과 `.log`는 `gzip` 압축 후 `/var/log/monitor/agent-app/archive/`로 이동, 30일 경과 `.gz`는 삭제합니다. 대상 디렉토리 미존재/권한 부족/대상 파일 0개 상황에서도 예외를 던지지 않고 `[WARNING]`/`[INFO]`로 안전하게 종료하도록 구현했습니다 (테스트 시점엔 7일 경과 로그가 아직 없어 "no log files" 분기가 실행됨).
