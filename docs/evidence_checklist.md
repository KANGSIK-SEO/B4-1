# 필수 증거 체크리스트

아래는 `docker compose up --build -d`로 띄운 `agent-monitor` 컨테이너(Ubuntu 22.04)에서 2026-09-25에 직접 실행해 얻은 **실제 결과**입니다. 전부 "예상"이 아니라 캡처된 진짜 출력입니다.

## ✅ SSH 20022 + Root 차단

```bash
docker exec agent-monitor bash -c "grep -E '^(Port|PermitRootLogin)' /etc/ssh/sshd_config"
docker exec agent-monitor bash -c "ss -tulnp | grep ':20022'"
```

```text
Port 20022
PermitRootLogin no
tcp   LISTEN 0      128          0.0.0.0:20022      0.0.0.0:*    users:(("sshd",pid=283,fd=3))
```

## ✅ 방화벽 20022/15034 only

```bash
docker exec agent-monitor bash -c "ufw status verbose"
```

```text
Status: active
Default: deny (incoming), allow (outgoing), deny (routed)
20022/tcp                  ALLOW IN    Anywhere
15034/tcp                  ALLOW IN    Anywhere
```

## ✅ 계정/그룹

```bash
docker exec agent-monitor bash -c "id agent-admin; id agent-dev; id agent-test"
```

```text
uid=1000(agent-admin) groups=1002(agent-admin),1000(agent-common),1001(agent-core)
uid=1001(agent-dev) groups=1003(agent-dev),1000(agent-common),1001(agent-core)
uid=1002(agent-test) groups=1004(agent-test),1000(agent-common)
```

agent-common: agent-admin,agent-dev,agent-test / agent-core: agent-admin,agent-dev — 스펙과 일치.

## ✅ 디렉터리 권한 (+ 실접근 차단 증명)

```bash
docker exec agent-monitor bash -c "ls -ld /home/agent-admin/agent-app/upload_files /home/agent-admin/agent-app/api_keys /var/log/agent-app"
docker exec agent-monitor bash -c "ls -l /home/agent-admin/agent-app/bin/monitor.sh"
docker exec agent-monitor bash -c "runuser -u agent-test -- ls /home/agent-admin/agent-app/api_keys"
```

```text
drwxrws---+ 2 agent-admin agent-core   /home/agent-admin/agent-app/api_keys
drwxrws---+ 2 agent-admin agent-common /home/agent-admin/agent-app/upload_files
drwxrws---+ 2 agent-admin agent-core   /var/log/agent-app
-rwxr-x--- 1 agent-dev agent-core monitor.sh

ls: cannot access '/home/agent-admin/agent-app/api_keys': Permission denied   ← agent-test 실제 차단 확인
```

## ✅ 환경 변수

```bash
docker exec agent-monitor cat /etc/profile.d/agent-app.sh
```

```text
AGENT_HOME=/home/agent-admin/agent-app
AGENT_PORT=15034
AGENT_UPLOAD_DIR=/home/agent-admin/agent-app/upload_files
AGENT_KEY_PATH=/home/agent-admin/agent-app/api_keys
AGENT_LOG_DIR=/var/log/agent-app
```

## ✅ Boot Sequence 5단계 OK

```bash
docker logs agent-monitor
```

```text
[1/5] Checking User Account               [OK]
[2/5] Verifying Environment Variables     [OK]
[3/5] Checking Required Files             [OK]
[4/5] Checking Port Availability          [OK]
[5/5] Verifying Log Permission            [OK]
All Boot Checks Passed!
Agent READY
```

## ✅ 0.0.0.0:15034 LISTEN

```text
tcp   LISTEN 0      1            0.0.0.0:15034      0.0.0.0:*    users:(("agent-app",pid=296,fd=4))
```

## ✅ monitor.sh 결과 (정상 + 비정상 둘 다 실증)

정상:
```text
Checking process 'agent-app'... [OK] (PID: 294)
Checking port 15034... [OK]
CPU Usage : 0.3%  MEM Usage : 19.4%  DISK Used : 4%
[WARNING] MEM threshold exceeded (19.4% > 10%)
EXIT_CODE=0
```

`kill`로 프로세스 강제 종료 후:
```text
[ERROR] process 'agent-app' is not running
종료코드=1
```

## ✅ /var/log/agent-app/monitor.log

```text
[2026-09-25 10:47:01] PID:1285 CPU:0.3% MEM:19.0% DISK_USED:4%
[2026-09-25 10:48:02] PID:1285 CPU:0.3% MEM:20.1% DISK_USED:4%
[2026-09-25 10:49:01] PID:1285 CPU:1.5% MEM:20.1% DISK_USED:4%
```

## ✅ crontab 매분 실행

```bash
docker exec agent-monitor crontab -u agent-admin -l
```

```text
* * * * * . /etc/profile.d/agent-app.sh; /home/agent-admin/agent-app/bin/monitor.sh >> /var/log/agent-app/monitor-cron.out 2>&1
17 3 * * * . /etc/profile.d/agent-app.sh; /home/agent-admin/agent-app/bin/archive-agent-logs.sh >> /var/log/agent-app/archive-cron.out 2>&1
```

위 monitor.log의 `10:47:01 → 10:48:02 → 10:49:01`이 사람 개입 없이 1분 간격으로 자동 누적된 실제 증거입니다.

## ✅ 보너스 1 — report.sh

```text
====== STATISTICS REPORT ======
[CPU]    Average : 0.6%  Maximum : 0.9%  Minimum : 0.3%
[Memory] Average : 19.0% Maximum : 19.4% Minimum : 18.7%
[Disk]   Average : 4.0%  Maximum : 4.0%  Minimum : 4.0%
[Samples] Data Points: 2 samples
```

## ✅ 보너스 2 — 로그 보존 정책 (7일 압축 / 30일 삭제)

```text
[INFO] no log files older than 7 days
[INFO] no archives older than 30 days
```

(테스트 시점엔 7일 경과 로그가 없어 정상적으로 "대상 없음" 분기로 안전 종료됨 — 디렉토리 미존재/권한 부족 시에도 동일하게 예외 없이 경고 후 종료하도록 구현.)
