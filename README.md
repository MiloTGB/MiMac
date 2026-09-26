# MiMac — daily driver for this Mac

Personal, opinionated macOS setup tailored to my workflow and toolset: the dotfiles,
tools and settings this Mac runs on, plus the commands that keep it healthy.
Everything is idempotent — run any command as often as you like.

**[Full workflow manual →](https://milotgb.github.io/MiMac/)**

## Daily Use

| Command | When | What it does |
|---------|------|--------------|
| `make maintain` | Weekly | Pull MiMac, relink tools, update packages and macOS, rebuild the TUIs, then `doctor` |
| `make doctor` | When something feels off | Find what is broken or drifting — see below. `ARGS=--fix` repairs the safe items |
| `make update` | Any time | Upgrade every package (topgrade: Homebrew, casks, oh-my-zsh, pipx, gh extensions) |
| `make updates` | Any time | Install macOS updates for this version. **Never a major upgrade** — `ARGS=-n` to preview |
| `make sync` | After installing or removing apps | Pick which new Homebrew packages go into the Brewfile |
| `status` | Any time | Health dashboard TUI (`make status` for the plain-text version) |
| `syncall` | End of day | Commit and push every GitHub repo under `$HOME`, behind a secret scan |

All of these also work from `~` — `~/Makefile` forwards them to the repo.

### What `make doctor` checks

- **Links** — every dotfile linked, no dangling `~/bin` links, no repo command left unlinked
- **Shell startup** — insecure completion directories that make oh-my-zsh rebuild its cache
  on every new shell, and how long a new shell actually takes
- **Apple Silicon hygiene** — an Intel Homebrew left in `/usr/local`, commands on `PATH` whose
  interpreter is gone, apps that only run under Rosetta 2, a hostname naming another chip
- **Security** — Touch ID for `sudo`, firewall
- **MiMac tools** — TUI binaries older than their source, LaunchAgents out of date or failing
- **Homebrew** — `brew doctor`, and drift between the Brewfile and what is installed
- **The repo** — uncommitted work, commits not pushed, commits not pulled

`--fix` only touches what is yours and cannot lose data (the `PATH` line, completion-directory
permissions, old-hostname completion caches, `~/bin` links, stale TUI binaries). Everything else prints the command to run.

## Make Targets

| Target | Description |
|--------|-------------|
| `make maintain` | Weekly upkeep: pull, relink, update, macOS updates, rebuild TUIs, doctor |
| `make doctor` | Health check (`ARGS=--fix` to repair the safe items) |
| `make update` | Update via topgrade (or brew) |
| `make updates` | macOS updates for the installed version only (`ARGS=-n` to preview) |
| `make pull` | Fast-forward MiMac to origin |
| `make sync` | Snapshot installed Homebrew packages into the Brewfile |
| `make status` | Show installation status |
| `make snapshot-prefs` | Export app preferences to `~/.mimac/preferences` |
| `make trim-services` | Disable background launchd agents this Mac does not need (`ARGS=-n` to preview) |
| `make harden` | Security hardening (Touch ID sudo via `sudo_local`, screen lock, firewall) |
| `make build-tools` | Build the Go TUIs: `bf`, `mimac-picker`, `mimac-status` |
| `make check` | Lint the repo: shellcheck every script, `go vet` every TUI |
| `make tidy` | `go mod tidy` in every tool (builds no longer do this) |
| `make tools` / `make dotfiles` | Relink `~/bin` / dotfiles only |
| `make defaults` / `make trackpad` | Apply macOS defaults (with trackpad gestures) |
| `make dock` | Set up Dock with preferred apps |
| `make install` / `make brew` / `make post-install` | Setup phases 1–3 (see below) |
| `make uninstall` | Remove symlinks, optionally roll back defaults |
| `make manual` | Regenerate `docs/index.html` from `docs/manual.md` |
| `make help` | Show all available make commands |

## Setting Up a Mac

Three idempotent phases. Run them on a fresh Mac, or re-run any one to repair this one.

```bash
git clone https://github.com/MiloTGB/MiMac.git ~/MiMac
cd ~/MiMac
make install        # Phase 1: Xcode CLI tools, dotfiles, ~/bin, macOS defaults, login shell
make brew           # Phase 2: Homebrew, then pick formulae & casks from the Brewfile
make post-install   # Phase 3: app preferences, browser policies, login items, LaunchAgents
make dock
make doctor         # confirm everything landed
```

`make all` runs all three phases and builds the TUIs. Phase 1 needs no Homebrew.

Some things stay manual: Mac App Store apps (Final Cut Pro, iMovie, Keynote, Numbers,
Pages, Pixelmator Pro), FL Studio, Safari settings (sandboxed since Sequoia), and signing
in to 1Password/Bitwarden and cloud storage.

## Philosophy

- Every command is idempotent and safe to re-run.
- State lives in `~/.mimac`. Defaults, hardening and trim-services each write a rollback
  script there, and a re-run never overwrites the originals it recorded.
- Nothing installs a major macOS upgrade on its own — that is always done by hand.

`syncall` commits and pushes every GitHub repository under `$HOME`, and it stages with
`git add -A` — so every commit is gated behind a secret scan that refuses private keys,
credential assignments, bearer tokens and vendor API-key prefixes. A repository that fails
the scan is left staged and uncommitted; the sweep continues. See the
[manual](docs/manual.md#syncing-every-repository-syncall).

## Structure

```
MiMac/
├── Makefile            # All targets
├── Brewfile            # Homebrew packages
├── dotfiles/           # Symlinked to ~/
│   └── Makefile        # ~/Makefile — daily commands from anywhere
├── bin/                # Commands linked to ~/bin (macos-updates, audio-mode, zoom-mode, …)
├── assets/             # App configs, browser policies
│   ├── browsers/
│   ├── launchagents/   # Scheduled jobs installed by Phase 3
│   ├── preferences/
│   └── topgrade.toml
├── tools/              # Go/Bubble Tea TUIs: bf, picker, mimac-status (+ shared theme)
├── docs/
│   ├── manual.md       # Workflow manual source
│   └── assets/         # CSS for generated HTML
└── scripts/
    ├── lib.sh          # Shared helpers
    ├── doctor          # Health check
    ├── setup           # Phase 1
    ├── brew-packages   # Phase 2
    ├── post-install    # Phase 3
    ├── sync            # Brewfile sync
    ├── check-updates   # Weekly "MiMac has new commits" prompt (non-blocking)
    ├── defaults.sh     # macOS defaults
    ├── hardening.sh    # Security hardening
    └── ...             # status, syncall, trim-services, snapshot-prefs, uninstall, etc.
```

## License

MIT — milothegalaxyboy
