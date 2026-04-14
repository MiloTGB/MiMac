SHELL := $(shell command -v bash)
REPO_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
SCRIPTS := scripts
BIN_DIR   := $(REPO_ROOT)/bin

.PHONY: all install fix-exec setup brew post-install tools dotfiles defaults trackpad uninstall nuke update updates harden status doctor dock sync sync-commit sync-prune sync-clean setup-dry nuke-execute picker bf mimac-status build-tools manual help snapshot-prefs pull-prefs

# Build a Go tool: $(call go-build,<binary>,<tool-dir>)
define go-build
	@if ! command -v go >/dev/null 2>&1; then \
		echo "error: Go is not installed. Install it with: brew install go"; \
		exit 1; \
	fi
	@printf '  \033[36m▸\033[0m Building $(1)…\n'
	@cd "$(REPO_ROOT)/tools/$(2)" && go mod tidy && go build -o "$(BIN_DIR)/$(1)" .
	@chmod +x "$(BIN_DIR)/$(1)"
endef

help: ## Show available make commands
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' \
		| sort

all: setup brew post-install build-tools ## Full install: setup + brew + post-install + TUI binaries

fix-exec: ## Make scripts and bin files executable
	@echo "Making scripts and bin executables..."
	@find $(SCRIPTS) -type f -maxdepth 1 -not -name "*.md" -exec chmod +x {} + 2>/dev/null || true
	@find $(BIN_DIR) -type f -maxdepth 1 -not -name "*.md" -exec chmod +x {} + 2>/dev/null || true

install: setup ## Run Phase 1 setup

setup: fix-exec ## Phase 1: shell, dotfiles, macOS defaults (use ARGS=--dry-run to preview)
	@"$(SCRIPTS)/setup"

setup-dry: fix-exec ## Preview setup changes without applying
	@"$(SCRIPTS)/setup" --dry-run

brew: fix-exec ## Phase 2: install Homebrew packages and casks
	@"$(SCRIPTS)/brew-packages"

post-install: fix-exec ## Phase 3: configure apps and login items
	@"$(SCRIPTS)/post-install"

tools: ## Install CLI tools only (skip dotfiles)
	@"$(SCRIPTS)/setup" --only tools

dotfiles: ## Link dotfiles only (skip tools)
	@"$(SCRIPTS)/setup" --only dotfiles

defaults: ## Apply macOS defaults
	@"$(SCRIPTS)/defaults.sh"

trackpad: ## Apply macOS defaults including trackpad settings
	@"$(SCRIPTS)/defaults.sh" --with-trackpad

uninstall: ## Remove symlinks and undo setup
	@"$(SCRIPTS)/uninstall"

nuke: ## Complete MiMac removal (dry-run preview, use nuke-execute to actually run)
	@"$(SCRIPTS)/nuke-mimac"

nuke-execute: ## DESTRUCTIVE: Execute complete MiMac removal (requires confirmation)
	@"$(SCRIPTS)/nuke-mimac" --execute

update: ## Upgrade all packages (topgrade or brew)
	@if command -v topgrade >/dev/null 2>&1; then topgrade; else brew update && brew upgrade; fi

updates: ## Run macOS software updates
	@softwareupdate -ia || true

harden: ## Apply macOS security hardening
	@"$(SCRIPTS)/hardening.sh"

status: ## Show installation status
	@"$(SCRIPTS)/status"

doctor: ## Run diagnostics
	@"$(SCRIPTS)/doctor"
	@brew doctor

dock: ## Populate Dock with preferred apps
	@"$(SCRIPTS)/dock-setup"

sync: ## Sync installed Homebrew packages into Brewfile (use ARGS="-c" to commit, ARGS="-p" to prune)
	@"$(SCRIPTS)/sync" $(ARGS)

sync-commit: ## Sync Brewfile and auto-commit changes
	@"$(SCRIPTS)/sync" -c

sync-prune: ## Preview stale packages to remove (dry-run)
	@"$(SCRIPTS)/sync" -p -n

sync-clean: ## Remove stale packages and commit
	@"$(SCRIPTS)/sync" -p -c

snapshot-prefs: ## Export app preferences and push to mimac-prefs
	@"$(SCRIPTS)/snapshot-prefs"

pull-prefs: ## Clone or pull app preferences from mimac-prefs
	@"$(SCRIPTS)/pull-prefs"

build-tools: ## Build all Go TUI binaries (requires Go)
	@printf '\n\033[1;34m══ Building TUI Tools\033[0m\n\n'
	@$(MAKE) --no-print-directory picker bf mimac-status

picker: ## Build the mimac-picker TUI binary
	$(call go-build,mimac-picker,picker)

bf: ## Build the bf Brewfile manager TUI binary
	$(call go-build,bf,bf)

mimac-status: ## Build the mimac-status health dashboard TUI binary
	$(call go-build,mimac-status,mimac-status)

manual: ## Regenerate docs/index.html from docs/manual.md (requires pandoc)
	@if ! command -v pandoc >/dev/null 2>&1; then \
		echo "error: pandoc is not installed. Install it with: brew install pandoc"; \
		exit 1; \
	fi
	@echo "Generating docs/index.html..."
	@pandoc "$(REPO_ROOT)/docs/manual.md" \
		--standalone --embed-resources \
		--resource-path "$(REPO_ROOT)/docs" \
		--toc --toc-depth=2 \
		--css "$(REPO_ROOT)/docs/assets/manual.css" \
		--highlight-style=zenburn \
		--output "$(REPO_ROOT)/docs/index.html" 2>/dev/null
	@python3 -c "\
f = open('$(REPO_ROOT)/docs/index.html', 'r+'); \
s = f.read(); \
s = s.replace('<nav id=\"TOC\" role=\"doc-toc\">', '<details id=\"toc-details\"><summary class=\"toc-summary\">Table of Contents</summary><nav id=\"TOC\" role=\"doc-toc\">', 1); \
s = s.replace('</nav>', '</nav></details>', 1); \
f.seek(0); f.write(s); f.truncate(); f.close()"
	@echo "Generated: docs/index.html"
