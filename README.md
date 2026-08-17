# MiMac — macOS bootstrap

Personal, opinionated macOS bootstrap tailored to my workflow and toolset. Idempotent setup in three phases.

**[Full workflow manual →](https://milotgb.github.io/MiMac/)**

## Quick Start

```bash
git clone https://github.com/MiloTGB/MiMac.git ~/MiMac
cd ~/MiMac
make install
make brew
make post-install
make dock
```

## Phases

| Phase | Command | What it does |
|-------|---------|--------------|
| **1 — Setup** | `make install` | Xcode CLI tools, dotfile symlinks, tool linking, macOS defaults, login shell |
| **2 — Brew** | `make brew` | Installs Homebrew, then interactively selects formulae & casks from `Brewfile` |
| **3 — Post-install** | `make post-install` | App preferences, browser policies, login items |

Run `make all` to execute all three phases at once. Phases are independent — run any subset, in any order, as many times as you want.

## Make Targets

| Target | Description |
|--------|-------------|
| `make install` / `make setup` | Phase 1 (setup) |
| `make brew` | Phase 2 (Homebrew) |
| `make post-install` | Phase 3 (app config) |
| `make all` | All three phases |
| `make sync` | Snapshot installed Homebrew packages into the Brewfile |
| `make snapshot-prefs` | Export app preferences |
| `make tools` | Link scripts into `~/bin` only |
| `make dotfiles` | Symlink dotfiles only |
| `make defaults` | Apply macOS defaults only |
| `make trackpad` | Apply defaults including trackpad gestures |
| `make dock` | Set up Dock with preferred apps |
| `make harden` | Security hardening (Touch ID sudo, firewall) |
| `make status` | Show installation status |
| `make doctor` | Check `~/bin` is on PATH; `make doctor --fix` adds it to `.zshrc` |
| `make update` | Update via topgrade (or brew) |
| `make updates` | Install macOS software updates |
| `make picker` | Build the mimac-picker TUI binary |
| `make manual` | Regenerate `docs/index.html` from `docs/manual.md` |
| `make uninstall` | Remove symlinks, optionally rollback defaults |
| `make fix-exec` | Fix executable permissions on scripts |
| `make help` | Show all available make commands |

## Migrating to a New Machine

### Step 1: Snapshot Your Current Machine

Before leaving your old machine, capture its current state using the `snapshot` tool (lives at `~/bin/snapshot`, not in the repo):

```bash
snapshot
cd ~/MiMac
git push
```

This updates the Brewfile, Dock layout, and app preferences to match what's actually installed. Review the diff before pushing — it's your chance to drop anything you don't want to carry forward.

### Step 2: Set Up the New Machine

On the fresh Mac:

```bash
# Install Xcode Command Line Tools (if not already present)
xcode-select --install

# Clone and run Phase 1 (dotfiles, tools, defaults)
git clone https://github.com/MiloTGB/MiMac.git ~/MiMac
cd ~/MiMac
make install
```

Phase 1 doesn't need Homebrew — it links dotfiles, sets macOS defaults, and configures your shell.

### Step 3: Install Homebrew Packages

```bash
make brew
```

This installs Homebrew if needed, then walks you through an interactive selection of formulae and casks from the Brewfile. Already-installed packages are skipped automatically.

### Step 4: Configure Apps

```bash
make post-install
make dock
```

Post-install applies app preferences (iTerm2, Audio Hijack, browser policies) and sets up login items. `make dock` populates the Dock with your preferred app layout.

### Step 5: Manual Steps

Some things can't be automated:

- **Mac App Store apps** — Final Cut Pro, iMovie, Keynote, Numbers, Pages, Pixelmator Pro (sign in to the App Store and redownload)
- **Manual installers** — FL Studio, FL Cloud Plugins
- **Safari settings** — sandboxed on macOS Sequoia+, configure in Safari → Settings
- **1Password / Bitwarden** — sign in and sync
- **Cloud storage** — sign in to iCloud, Google Drive, Dropbox, etc.

## Philosophy

Setup is split into phases so you can:

- Run Phase 1 on a fresh Mac before Homebrew is even available
- Selectively install only the Homebrew packages you want (Phase 2 is interactive)
- Re-run any phase independently without side effects

State lives in `~/.mimac`. Rollback scripts are generated automatically for defaults changes.

## Structure

```
MiMac/
├── Makefile            # All targets
├── Brewfile            # Homebrew packages
├── dotfiles/           # Symlinked to ~/
│   └── Makefile        # ~/Makefile proxy for sync/prefs/picker/manual
├── bin/                # Extra scripts linked to ~/bin
├── assets/             # App configs, browser policies
│   ├── browsers/
│   ├── preferences/
│   └── topgrade.toml
├── tools/
│   └── picker/         # mimac-picker TUI (Go/Bubble Tea)
├── docs/
│   ├── manual.md       # Workflow manual source
│   └── assets/         # CSS for generated HTML
└── scripts/
    ├── lib.sh          # Shared helpers
    ├── install         # Unified entrypoint (dispatches to phases)
    ├── setup           # Phase 1
    ├── brew-packages   # Phase 2
    ├── post-install    # Phase 3
    ├── sync            # Brewfile sync
    ├── snapshot-prefs  # Export app preferences
    ├── dock-setup      # Dock layout
    ├── status          # Installation status
    ├── defaults.sh     # macOS defaults
    ├── hardening.sh    # Security hardening
    ├── uninstall       # Conservative uninstaller
    └── ...             # doctor, syncall, check-updates, etc.
```

## License

MIT — milothegalaxyboy
