SHELL := $(shell command -v bash)
REPO_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
SCRIPTS := $(REPO_ROOT)/scripts
BIN_DIR   := $(REPO_ROOT)/bin
INSTALL_BIN := $(HOME)/bin

# The checkout ~/bin serves. A build anywhere else — a clone, a worktree, a
# scratch copy — builds without linking, so testing a copy cannot repoint
# ~/bin/status at it, to dangle once the copy is deleted. Compared as resolved
# paths, so a repo under a symlink still counts.
MIMAC_HOME := $(HOME)/MiMac
serves-home = [ "$$(cd "$(MIMAC_HOME)" 2>/dev/null && pwd -P)" = "$$(cd "$(REPO_ROOT)" && pwd -P)" ]

.PHONY: trim-services pull-prefs all install fix-exec setup brew post-install tools dotfiles defaults trackpad uninstall nuke update updates pull maintain check test tidy harden status doctor dock sync sync-commit sync-prune sync-clean sync-login-items setup-dry nuke-execute picker mimac-status build-tools manual help snapshot-prefs

# Put Homebrew on PATH for one recipe line, when it is installed and not on PATH
# already: homebrew_on_path in scripts/lib.sh. make all runs every step with the
# PATH it started with, and on a new Mac that holds no Homebrew, so build-tools
# failed with "Go is not installed" right after Phase 2 had installed Go.
brew-env = . "$(SCRIPTS)/lib.sh" && { homebrew_on_path || true; };

# Build a Go tool: $(call go-build,<binary>,<tool-dir>)
# brew-env on both lines that need go, since each recipe line is its own shell.
define go-build
	@$(brew-env) \
	if ! command -v go >/dev/null 2>&1; then \
		echo "error: Go is not installed. Install it with: brew install go"; \
		exit 1; \
	fi
	@printf '  \033[36m▸\033[0m Building $(1)…\n'
	@$(brew-env) \
	 VERSION=$$(git -C "$(REPO_ROOT)" describe --tags --always --dirty 2>/dev/null || echo dev); \
	 SHA=$$(git -C "$(REPO_ROOT)" rev-parse --short HEAD 2>/dev/null || echo unknown); \
	 cd "$(REPO_ROOT)/tools/$(2)" && \
	 go build -ldflags "-X main.Version=$$VERSION -X main.GitSHA=$$SHA" -o "$(BIN_DIR)/$(1)" .
	@chmod +x "$(BIN_DIR)/$(1)"
endef

# Link a built binary into ~/bin: $(call link-home-bin,<binary>,<link names>)
# Only from the checkout ~/bin serves (serves-home above).
define link-home-bin
	@if $(serves-home); then \
		mkdir -p "$(INSTALL_BIN)" && \
		for n in $(2); do ln -sf "$(BIN_DIR)/$(1)" "$(INSTALL_BIN)/$$n" || exit 1; done && \
		printf '  \033[32m✓\033[0m $(1) → $(patsubst %,~/bin/%,$(2))\n'; \
	else \
		printf '  \033[33m⚠\033[0m $(1) built, not linked: ~/bin serves $(MIMAC_HOME), not this checkout\n'; \
	fi
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
	@if [ ! -d "$(HOME)/.mimac/preferences/.git" ]; then \
		printf '  Preferences not restored — add your SSH key to GitHub, then run \033[36mmake pull-prefs\033[0m and \033[36mmake post-install\033[0m\n'; \
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
	@"$(SCRIPTS)/setup" $(ARGS)

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

# run_topgrade (lib.sh) ends the run by saying what topgrade's exit status
# means: when a step failed, that every step ran, and which ones failed. A run
# with one failed cask otherwise ended on "make: *** [update] Error 1" and
# nothing else, which reads as though it had stopped there.
update: ## Upgrade all packages (topgrade or brew), and say which steps failed
	@. "$(SCRIPTS)/lib.sh" && if command -v topgrade >/dev/null 2>&1; then run_topgrade; else brew update && brew upgrade; fi

updates: ## Install macOS updates for this version — never a major upgrade (ARGS=-n to preview)
	@"$(BIN_DIR)/macos-updates" $(ARGS)

# pull fast-forwards, then brings the install up to the commits it pulled. A
# plain fast-forward left the old Go binaries in ~/bin after a change to tools/,
# a new script off the PATH, and a new dotfile unlinked, each until the
# matching make target was run by hand — and check-updates' "yes" runs only
# this. Each step runs only when the pulled range touched what it serves:
#   tools/             make build-tools
#   scripts/ or bin/   fix-exec, then setup --only tools
#   dotfiles/          setup --only dotfiles
# Relinking only from the checkout ~/bin serves; anywhere else it is skipped.
# PULL_BUILD=0 skips the rebuild: maintain passes it, because it rebuilds after
# its package updates, which can bring a new Go.
pull: ## Fast-forward MiMac to origin, then rebuild and relink what the pulled commits changed
	@old=$$(git -C "$(REPO_ROOT)" rev-parse HEAD) || exit 1; \
	git -C "$(REPO_ROOT)" pull --ff-only || exit 1; \
	new=$$(git -C "$(REPO_ROOT)" rev-parse HEAD) || exit 1; \
	[ "$$old" != "$$new" ] || exit 0; \
	changed=$$(git -C "$(REPO_ROOT)" diff --name-only "$$old" "$$new"); \
	touched() { printf '%s\n' "$$changed" | grep -Eq "$$1"; }; \
	home=1; $(serves-home) || home=0; \
	rc=0; \
	if touched '^tools/'; then \
		if [ "$(PULL_BUILD)" = 0 ]; then \
			printf '  \033[2mtools/ changed; rebuild skipped (PULL_BUILD=0)\033[0m\n'; \
		else \
			$(MAKE) --no-print-directory -C "$(REPO_ROOT)" build-tools || rc=1; \
		fi; \
	fi; \
	if touched '^(scripts|bin|dotfiles)/' && [ "$$home" = 0 ]; then \
		printf '  \033[33m⚠\033[0m not relinked: ~/bin and the dotfiles serve $(MIMAC_HOME), not this checkout\n'; \
	else \
		if touched '^(scripts|bin)/'; then \
			"$(SCRIPTS)/fix-exec" >/dev/null && "$(SCRIPTS)/setup" --only tools || rc=1; \
		fi; \
		if touched '^dotfiles/'; then \
			"$(SCRIPTS)/setup" --only dotfiles || rc=1; \
		fi; \
	fi; \
	exit $$rc

maintain: ## Weekly upkeep: pull, relink, update packages + macOS, rebuild TUIs, snapshot prefs, doctor
	-@$(MAKE) --no-print-directory pull PULL_BUILD=0
	-@$(MAKE) --no-print-directory tools
	-@$(MAKE) --no-print-directory update
	-@$(MAKE) --no-print-directory updates
	-@$(MAKE) --no-print-directory build-tools
	-@$(MAKE) --no-print-directory snapshot-prefs
	@$(MAKE) --no-print-directory doctor

harden: ## Apply macOS security hardening
	@"$(SCRIPTS)/hardening.sh"

trim-services: ## Disable background launchd agents this Mac does not need (ARGS=-n to preview)
	@"$(SCRIPTS)/trim-services" $(ARGS)

status: ## Print the dashboard's panels as text: unrecorded work, upkeep, Time Machine, the installation
	@"$(SCRIPTS)/status"

doctor: ## Find what is broken or drifting on this Mac (ARGS=--fix to repair the safe items)
	@# doctor exits 1 when problems remain, for scripts that call ~/bin/doctor.
	@# Its summary already says so; letting make add "*** [doctor] Error 1"
	@# (and "Error 2" through ~/Makefile) made a report read like a crash.
	@"$(SCRIPTS)/doctor" $(ARGS) || true

check: ## Lint the repo (shellcheck, gofmt, go vet), then run go test and the tests in tests/
	@command -v shellcheck >/dev/null 2>&1 || { echo "error: shellcheck is not installed. Install it with: brew install shellcheck"; exit 1; }
	@printf '  \033[36m▸\033[0m shellcheck\n'
	@shellcheck $$(grep -lE '^#!.*(ba)?sh' $(SCRIPTS)/* $(BIN_DIR)/* $(BIN_DIR)/lib/*.sh $(REPO_ROOT)/assets/preferences/*.sh $(REPO_ROOT)/tests/*.sh 2>/dev/null)
	@for d in picker mimac-status theme; do \
		printf '  \033[36m▸\033[0m gofmt, go vet, go test tools/%s\n' "$$d"; \
		unformatted=$$(cd "$(REPO_ROOT)/tools/$$d" && gofmt -l .); \
		[ -z "$$unformatted" ] || { echo "not gofmt-clean in tools/$$d: $$unformatted"; exit 1; }; \
		(cd "$(REPO_ROOT)/tools/$$d" && go vet ./... && go test ./...) || exit 1; \
	done
	@$(MAKE) --no-print-directory test
	@printf '  \033[32m✓\033[0m all checks passed\n'

# Each test runs under a throwaway HOME, with stubs for anything that would
# reach the network, this Mac's settings or ~/bin. None needs sudo.
test: ## Run the tests in tests/ (make check runs them too)
	@rc=0; for t in "$(REPO_ROOT)"/tests/*.sh; do \
		printf '  \033[36m▸\033[0m tests/%s\n' "$${t##*/}"; \
		bash "$$t" || rc=1; \
	done; exit $$rc

tidy: ## Run go mod tidy in every tool directory (builds no longer do this)
	@for d in picker mimac-status theme; do \
		printf '  \033[36m▸\033[0m go mod tidy: tools/%s\n' "$$d"; \
		(cd "$(REPO_ROOT)/tools/$$d" && go mod tidy) || exit 1; \
	done

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

snapshot-prefs: ## Export app preferences and push them to mimac-prefs (ARGS=-n to preview)
	@"$(SCRIPTS)/snapshot-prefs" $(ARGS)

pull-prefs: ## Clone or update ~/.mimac/preferences from mimac-prefs
	@"$(SCRIPTS)/pull-prefs"

build-tools: ## Build all Go TUI binaries (requires Go)
	@printf '\n\033[1;34m══ Building TUI Tools\033[0m\n\n'
	@$(MAKE) --no-print-directory picker mimac-status

picker: ## Build the mimac-picker TUI binary
	$(call go-build,mimac-picker,picker)
	$(call link-home-bin,mimac-picker,mimac-picker)

mimac-status: ## Build the mimac-status health dashboard TUI binary
	$(call go-build,mimac-status,mimac-status)
	$(call link-home-bin,mimac-status,mimac-status status)

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
