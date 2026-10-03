MIMAC := $(HOME)/MiMac

# ~/Makefile, linked from ~/MiMac/dotfiles: MiMac's make targets from the home
# directory. The rules below are the ones `make help` lists under "From ~/";
# any other target goes to ~/MiMac's Makefile by the .DEFAULT rule at the end,
# so every target there works from here — `make check`, `make sync-clean`,
# `make trim-services` and the rest used to say "No rule to make target".

.PHONY: status doctor update updates maintain pull sync snapshot-prefs build-tools manual help

help: ## Show available make commands
	@echo ""
	@echo "  \033[1mFrom ~/\033[0m"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| grep -v '^help:' \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "  \033[1mFrom ~/MiMac/\033[0m"
	@$(MAKE) -C $(MIMAC) help --no-print-directory 2>/dev/null
	@echo ""

# Daily use first — this is the list `make help` shows from ~/.

maintain: ## Weekly upkeep: pull, relink, update packages + macOS, rebuild TUIs, snapshot prefs, doctor
	@$(MAKE) -C $(MIMAC) maintain --no-print-directory

doctor: ## Find what is broken or drifting on this Mac (ARGS=--fix to repair the safe items)
	@$(MAKE) -C $(MIMAC) doctor ARGS="$(ARGS)" --no-print-directory

update: ## Upgrade all packages (topgrade)
	@$(MAKE) -C $(MIMAC) update --no-print-directory

updates: ## Install macOS updates for this version — never a major upgrade (ARGS=-n to preview)
	@$(MAKE) -C $(MIMAC) updates ARGS="$(ARGS)" --no-print-directory

status: ## Show installation status
	@$(MAKE) -C $(MIMAC) status --no-print-directory

sync: ## Sync installed Homebrew packages into the Brewfile  (ARGS=-c to commit, ARGS=-n for dry run)
	@$(MAKE) -C $(MIMAC) sync ARGS="$(ARGS)" --no-print-directory

pull: ## Fast-forward MiMac to origin
	@$(MAKE) -C $(MIMAC) pull --no-print-directory

snapshot-prefs: ## Export app preferences and push them to mimac-prefs (ARGS=-n to preview)
	@$(MAKE) -C $(MIMAC) snapshot-prefs ARGS="$(ARGS)" --no-print-directory

build-tools: ## Rebuild the Go TUIs (mimac-picker, mimac-status)
	@$(MAKE) -C $(MIMAC) build-tools --no-print-directory

manual: ## Regenerate docs/index.html from docs/manual.md
	@$(MAKE) -C $(MIMAC) manual --no-print-directory

# Every other target, to ~/MiMac. ARGS, like any variable given on the command
# line, reaches the inner make by itself; it is spelt out here as the rules
# above spell it. A target with no rule anywhere fails there, with ~/MiMac's
# "No rule to make target".
.DEFAULT:
	@$(MAKE) -C $(MIMAC) $@ ARGS="$(ARGS)" --no-print-directory
