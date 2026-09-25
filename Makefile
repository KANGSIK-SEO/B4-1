SHELL := /usr/bin/env bash

.DEFAULT_GOAL := help

.PHONY: help check up down shell monitor report archive cron logs evidence

help: ## 사용 가능한 과제 명령을 표시한다
	@echo "B4-1 시스템 관제 자동화 (Docker 기반)"
	@echo
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z_-]+:.*## / {printf "  make %-13s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

check: ## 제출 파일과 Bash 문법을 안전하게 검사한다
	@test -f app/agent-app-linux-x86
	@test -f docs/requirements_report.md
	@test -f docs/evidence_checklist.md
	@bash -n scripts/entrypoint.sh
	@bash -n scripts/monitor.sh
	@bash -n scripts/report.sh
	@bash -n scripts/archive-agent-logs.sh
	@echo "[OK] 제출 파일 및 Bash 문법 검사 완료"

up: ## 컨테이너를 빌드하고 백그라운드로 기동한다
	docker compose up --build -d

down: ## 컨테이너를 종료한다
	docker compose down

shell: ## 컨테이너 안 Ubuntu 셸로 들어간다
	docker exec -it agent-monitor bash

monitor: ## 컨테이너 안에서 agent-admin 권한으로 monitor.sh를 1회 실행한다
	docker exec -u agent-admin agent-monitor bash -lc 'source /etc/profile.d/agent-app.sh; /home/agent-admin/agent-app/bin/monitor.sh'

report: ## 컨테이너 안에서 보너스 report.sh를 실행한다
	docker exec -u agent-admin agent-monitor bash -lc 'source /etc/profile.d/agent-app.sh; /home/agent-admin/agent-app/bin/report.sh'

archive: ## 컨테이너 안에서 보너스 로그 보존 스크립트를 실행한다
	docker exec -u agent-admin agent-monitor bash -lc 'source /etc/profile.d/agent-app.sh; /home/agent-admin/agent-app/bin/archive-agent-logs.sh'

cron: ## agent-admin의 crontab 등록 내역을 확인한다
	docker exec agent-monitor crontab -u agent-admin -l

logs: ## monitor.log 최근 내용을 표시한다
	docker exec agent-monitor tail -n 20 /var/log/agent-app/monitor.log

evidence: ## 제출 증거 자료 체크리스트 문서를 표시한다
	@sed -n '1,320p' docs/evidence_checklist.md
