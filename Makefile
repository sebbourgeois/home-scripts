SHELL := bash

.PHONY: help sync-readme

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' Makefile | awk -F':|##' '{printf "  %-18s %s\n",$$1,$$3}' | sort

sync-readme: ## Rebuild root README Available Scripts section
	bash scripts/sync_readme.sh

