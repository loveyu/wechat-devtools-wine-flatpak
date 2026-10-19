SHELL := /bin/bash

.PHONY: check helpers download install install-user-integration prepare-sample run status \
	build-deepin-runner migrate-to-deepin stop test-portal \
	build-staging-runner staging-download staging-install staging-prepare-sample \
	staging-run staging-status staging-stop staging-test-portal

check:
	@bash -n scripts/*.sh
	@tests/configure-prefix.sh
	@tests/wechat-devtools-host-open.sh
	@tests/desktop-launch.sh
	@tests/install-user-integration.sh
	@tests/stop.sh
	@tests/deepin-runner.sh
	@python3 -c 'compile(open("scripts/repair-codicon-font.py", encoding="utf-8").read(), "scripts/repair-codicon-font.py", "exec")'
	@if find . -path './.git' -prune -o -type f \
		\( -iname '*.exe' -o -iname '*.msi' \) -print -quit | grep -q .; then \
		echo '错误：仓库中不能提交微信开发者工具安装包' >&2; exit 1; \
	fi
	@if grep -R -E -- '--filesystem=/data([/:;]|$$)' flatpak >/dev/null; then \
		echo '错误：/data 必须使用本机用户级 override，不能写入 Flatpak 清单' >&2; exit 1; \
	fi
	@if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then git diff --check; fi

helpers:
	@mkdir -p .local/bin
	@cc -O2 -Wall -Wextra -o .local/bin/x11-control tests/x11-control.c -lX11 -ldl

download: check
	@./scripts/download.sh

install: check
	@./scripts/install.sh
	@./scripts/install-user-integration.sh

install-user-integration: check
	@./scripts/install-user-integration.sh

prepare-sample:
	@./scripts/prepare-sample.sh

run: check
	@./scripts/run.sh

status:
	@./scripts/status.sh

build-deepin-runner: check
	@./scripts/build-deepin-runner.sh

migrate-to-deepin: check
	@./scripts/migrate-to-deepin.sh
	@./scripts/install-user-integration.sh

stop:
	@./scripts/stop.sh

test-portal: check
	@./scripts/test-portal-runner.sh

build-staging-runner: check
	@./scripts/with-staging-runner.sh ./scripts/build-staging-runner.sh

staging-download: check
	@./scripts/with-staging-runner.sh ./scripts/download.sh

staging-install: check
	@./scripts/with-staging-runner.sh ./scripts/install.sh
	@./scripts/install-user-integration.sh

staging-prepare-sample:
	@./scripts/with-staging-runner.sh ./scripts/prepare-sample.sh

staging-run: check
	@./scripts/with-staging-runner.sh ./scripts/run.sh

staging-status:
	@./scripts/with-staging-runner.sh ./scripts/status.sh

staging-stop:
	@./scripts/with-staging-runner.sh ./scripts/stop.sh

staging-test-portal: check
	@./scripts/with-staging-runner.sh ./scripts/test-portal-runner.sh
