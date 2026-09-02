SHELL := /bin/bash

.PHONY: check helpers download install run status

check:
	@bash -n scripts/*.sh
	@python3 -c 'compile(open("scripts/repair-codicon-font.py", encoding="utf-8").read(), "scripts/repair-codicon-font.py", "exec")'
	@if find . -path './.git' -prune -o -type f \
		\( -iname '*.exe' -o -iname '*.msi' \) -print -quit | grep -q .; then \
		echo '错误：仓库中不能提交微信开发者工具安装包' >&2; exit 1; \
	fi
	@if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then git diff --check; fi

helpers:
	@mkdir -p .local/bin
	@cc -O2 -Wall -Wextra -o .local/bin/x11-control tests/x11-control.c -lX11 -ldl

download: check
	@./scripts/download.sh

install: check
	@./scripts/install.sh

run: check
	@./scripts/run.sh

status:
	@./scripts/status.sh
