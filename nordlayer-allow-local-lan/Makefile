SHELL := bash

SCRIPT := fix-nordlayer-local-lan.sh
INSTALL_BIN := /usr/local/bin/$(SCRIPT)
UNIT_SRC := systemd/fix-nordlayer-local-lan.service
UNIT_DST := /etc/systemd/system/fix-nordlayer-local-lan.service

# Optional: make run IFACE=wlp4s0
IFACE ?=

.PHONY: all help lint format run install install-service enable-service disable-service uninstall-service uninstall check

all: lint ## Default target: run linter

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' Makefile | awk -F':|##' '{printf "  %-22s %s\n",$$1,$$3}' | sort

lint: ## Lint shell scripts with shellcheck (if available)
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck $(SCRIPT); \
	else \
		echo "shellcheck not found; skipping lint"; \
	fi

format: ## Format shell scripts with shfmt (if available)
	@if command -v shfmt >/dev/null 2>&1; then \
		shfmt -w -i 2 -ci $(SCRIPT); \
	else \
		echo "shfmt not found; skipping format"; \
	fi

run: ## Run the script (sudo). Optional IFACE=wlp4s0
	sudo ./$(SCRIPT) $(IFACE)

install: ## Install the script into /usr/local/bin
	sudo install -m 0755 ./$(SCRIPT) $(INSTALL_BIN)

install-service: ## Install systemd unit and reload
	sudo install -m 0644 $(UNIT_SRC) $(UNIT_DST)
	sudo systemctl daemon-reload

enable-service: install install-service ## Enable and start the service
	sudo systemctl enable --now fix-nordlayer-local-lan.service

disable-service: ## Disable and stop the service
	sudo systemctl disable --now fix-nordlayer-local-lan.service || true

uninstall-service: disable-service ## Remove systemd unit and reload
	sudo rm -f $(UNIT_DST)
	sudo systemctl daemon-reload

uninstall: ## Remove installed script from /usr/local/bin
	sudo rm -f $(INSTALL_BIN)

check: ## Show current policy rules and lan table
	@ip rule list | grep -n 'lookup lan' || true
	@ip route show table lan || true

