SHELL := $(shell command -v bash)
REPO_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
SCRIPTS := $(REPO_ROOT)/scripts
BIN_DIR   := $(REPO_ROOT)/bin

.PHONY: trim-services all install fix-exec setup brew post-install tools dotfiles defaults trackpad uninstall nuke update updates harden status doctor dock sync sync-commit sync-prune sync-clean sync-login-items setup-dry nuke-execute picker bf mimac-status build-tools manual help snapshot-prefs

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

all: fix-exec setup brew post-install build-tools ## Full install: setup + brew + post-install + TUI binaries
	@printf '\n'
	@printf '\033[1;32m  ✔  MiMac installed successfully.\033[0m\n'
	@printf '\n'
	@printf '  Run \033[43;1;30m exec zsh \033[0m to reload your shell.\n'
	@if [ ! -d "$(HOME)/.mimac/preferences" ]; then \
		printf '  Preferences not restored — snapshot them with \033[36mmake snapshot-prefs\033[0m\n'; \
	fi
	@printf '\n'

fix-exec: ## Make scripts and bin files executable
	@echo "Making scripts and bin executables..."
	@# lib.sh is excluded deliberately — it is a sourced library, not a command,
	@# and its own header says so. This must stay in step with scripts/fix-exec,
	@# which carries the same exclusion: setup, brew and post-install all depend
	@# on this target, so without it the executable bit comes back on every run.
	@find $(SCRIPTS) -type f -maxdepth 1 -not -name "*.md" -not -name "lib.sh" -exec chmod +x {} + 2>/dev/null || true
	@find $(BIN_DIR) -type f -maxdepth 1 -not -name "*.md" -not -name "lib.sh" -exec chmod +x {} + 2>/dev/null || true

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

trim-services: ## Disable background launchd agents this Mac does not need (ARGS=-n to preview)
	@"$(SCRIPTS)/trim-services" $(ARGS)

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

sync-login-items: ## Sync system login items into post-install
	@"$(SCRIPTS)/sync-login-items"

snapshot-prefs: ## Export app preferences
	@"$(SCRIPTS)/snapshot-prefs"

build-tools: ## Build all Go TUI binaries (requires Go)
	@printf '\n\033[1;34m══ Building TUI Tools\033[0m\n\n'
	@$(MAKE) --no-print-directory picker bf mimac-status

picker: ## Build the mimac-picker TUI binary
	$(call go-build,mimac-picker,picker)
	@mkdir -p "$(HOME)/bin"
	@ln -sf "$(BIN_DIR)/mimac-picker" "$(HOME)/bin/mimac-picker"
	@printf '  \033[32m✓\033[0m mimac-picker → ~/bin/mimac-picker\n'

bf: ## Build the bf Brewfile manager TUI binary
	$(call go-build,bf,bf)
	@mkdir -p "$(HOME)/bin"
	@ln -sf "$(BIN_DIR)/bf" "$(HOME)/bin/bf"
	@printf '  \033[32m✓\033[0m bf → ~/bin/bf\n'

mimac-status: ## Build the mimac-status health dashboard TUI binary
	$(call go-build,mimac-status,mimac-status)
	@mkdir -p "$(HOME)/bin"
	@ln -sf "$(BIN_DIR)/mimac-status" "$(HOME)/bin/mimac-status"
	@ln -sf "$(BIN_DIR)/mimac-status" "$(HOME)/bin/status"
	@printf '  \033[32m✓\033[0m mimac-status → ~/bin/mimac-status\n'

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
