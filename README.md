# B4-1: 시스템 관제 자동화 스크립트

Ubuntu 22.04 컨테이너(Docker) 위에서 SSH 보안, 방화벽, 계정/그룹/ACL, 실행 환경 변수, 관제 스크립트, cron 등록을 전부 자동화한 제출물입니다. `docs/requirements_report.md`, `docs/evidence_checklist.md`는 실제로 이 리포를 띄워 캡처한 결과입니다(예상값 아님).

## 구성

```text
.
├── Dockerfile
├── docker-compose.yml
├── app/
│   ├── agent-app-linux-x86
│   └── agent-app-linux-arm64
├── scripts/
│   ├── entrypoint.sh          # 컨테이너 기동 시 전체 설정 자동화
│   ├── monitor.sh             # 제출용 관제 스크립트
│   ├── report.sh              # 보너스1: 통계 리포트
│   └── archive-agent-logs.sh  # 보너스2: 로그 보존 정책(7일 압축/30일 삭제)
├── docs/
│   ├── requirements_report.md
│   ├── evidence_checklist.md
│   └── shelltool_report.md
└── shelltool/                 # 선택 확장 (아래 참고)
```

## 실행

```bash
docker compose up --build -d
```

`entrypoint.sh`가 컨테이너 부팅과 동시에 자동으로 수행하는 것:
- 계정 3개(`agent-admin`, `agent-dev`, `agent-test`), 그룹 2개(`agent-common`, `agent-core`) 생성
- SSH 포트 20022 전환 + Root 원격 로그인 차단
- UFW로 20022/15034 tcp만 허용
- `$AGENT_HOME` 하위 디렉토리 구성 + setgid + ACL 적용
- 환경변수 5종을 `/etc/profile.d/agent-app.sh`에 등록
- `agent-admin` crontab에 monitor.sh(매분) + archive-agent-logs.sh(매일 03:17) 등록
- agent-app 실행 (Boot Sequence 5단계 확인 가능)

## 컨테이너 안에서 확인하기

```bash
docker exec -it agent-monitor bash
```

주요 검증 명령 (`docs/evidence_checklist.md`에 실제 캡처값 있음):

```bash
grep -E '^(Port|PermitRootLogin)' /etc/ssh/sshd_config
ss -tulnp | grep -E ':(20022|15034)'
ufw status verbose
id agent-admin; id agent-dev; id agent-test
ls -ld /home/agent-admin/agent-app/upload_files /home/agent-admin/agent-app/api_keys /var/log/agent-app
cat /etc/profile.d/agent-app.sh
docker logs agent-monitor                # Boot Sequence / Agent READY 확인

runuser -u agent-admin -- bash -lc 'source /etc/profile.d/agent-app.sh; /home/agent-admin/agent-app/bin/monitor.sh'
tail -f /var/log/agent-app/monitor.log
crontab -u agent-admin -l
```

## 알아둘 점: AGENT_KEY_PATH는 파일이 아니라 디렉토리

제공된 `agent-app` 바이너리는 `AGENT_KEY_PATH`를 "키 파일 경로"가 아니라 "키가 들어있는 디렉토리"로 검증합니다. 그래서 `AGENT_KEY_PATH=/home/agent-admin/agent-app/api_keys`(디렉토리)로 지정하고, 그 안에 과제 명세용 `t_secret.key`와 앱이 실제로 확인하는 `secret.key`를 같은 내용(`agent_api_key_test`)으로 함께 생성합니다. 자세한 경위는 `docs/requirements_report.md` 5번 항목 참고.

## 보너스

```bash
runuser -u agent-admin -- bash -lc 'source /etc/profile.d/agent-app.sh; /home/agent-admin/agent-app/bin/report.sh'
runuser -u agent-admin -- bash -lc 'source /etc/profile.d/agent-app.sh; /home/agent-admin/agent-app/bin/archive-agent-logs.sh'
```

- `report.sh`: monitor.log의 CPU/MEM/DISK 평균·최대·최소 요약
- `archive-agent-logs.sh`: 7일 경과 로그 압축(`/var/log/monitor/agent-app/archive/`), 30일 경과 아카이브 삭제, 대상 없음/권한 부족/디렉토리 미존재 시 예외 없이 안전 종료

## Docker 이미지 저장/공유

```bash
docker save agent-monitor-ubuntu:22.04 -o agent-monitor-ubuntu.tar
docker load -i agent-monitor-ubuntu.tar
docker run --privileged --name agent-monitor -p 20022:20022 -p 15034:15034 agent-monitor-ubuntu:22.04
```

## ShellTool 확장 (선택)

`shelltool/` 폴더는 필수 제출물을 대체하지 않는 선택 확장입니다. LangChain `ShellTool`로 `ps`, `ss`, `tail`, `monitor.sh`를 대신 실행해 쉘 명령에 익숙하지 않은 사용자가 상태 확인 과정을 따라갈 수 있게 했습니다.

```bash
python3 -m venv .venv
. .venv/bin/activate
pip install -r shelltool/requirements.txt

. /etc/profile.d/agent-app.sh
python3 shelltool/shelltool_demo.py
```

상세 설명은 `docs/shelltool_report.md`를 확인합니다.
