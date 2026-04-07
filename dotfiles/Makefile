MIMAC := $(HOME)/MiMac

.PHONY: status sync snapshot-prefs pull-prefs picker manual help

help: ## Show available make commands
	@echo ""
	@echo "  \033[1mFrom ~/\033[0m"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| grep -v '^help:' \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' \
		| sort
	@echo ""
	@echo "  \033[1mFrom ~/MiMac/\033[0m"
	@$(MAKE) -C $(MIMAC) help --no-print-directory 2>/dev/null
	@echo ""

status: ## Show installation status
	@$(MAKE) -C $(MIMAC) status --no-print-directory

sync: ## Sync installed Homebrew packages into the Brewfile  (pass ARGS=-c to commit, ARGS=-n for dry run)
	@$(MAKE) -C $(MIMAC) sync ARGS="$(ARGS)"

snapshot-prefs: ## Export app preferences and push to mimac-prefs
	@$(MAKE) -C $(MIMAC) snapshot-prefs

pull-prefs: ## Clone or pull app preferences from mimac-prefs
	@$(MAKE) -C $(MIMAC) pull-prefs

picker: ## Build the mimac-picker TUI binary
	@$(MAKE) -C $(MIMAC) picker

manual: ## Regenerate docs/index.html from docs/manual.md
	@$(MAKE) -C $(MIMAC) manual
