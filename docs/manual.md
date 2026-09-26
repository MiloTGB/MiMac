---
title: "MiMac — Daily Driver Manual"
subtitle: "Using, maintaining and repairing this Mac's setup"
date: "[github.com/MiloTGB/MiMac](https://github.com/MiloTGB/MiMac)"
---

# Overview

**MiMac** is a personal, opinionated macOS setup tailored to my workflow and toolset. It
holds this Mac's shell environment, dotfiles, macOS preferences, Homebrew packages, app
settings and login items — and the commands that keep all of that healthy day to day.

| Location | Purpose |
|---|---|
| `~/MiMac/` | This repo ([MiloTGB/MiMac](https://github.com/MiloTGB/MiMac)). Dotfiles are symlinked from here, so editing the repo edits the live config |
| `~/bin/` | MiMac's commands, symlinked from `scripts/` and `bin/` |
| `~/.mimac/` | Local state: rollback scripts, dotfile backups, app-preference snapshots |

Every command is idempotent: run it as often as you like, and re-running one is how you
repair what it set up.

> **Adapting for your own use:** This project is built around a specific setup. If you fork
> it, swap in your own dotfiles, and review the app lists in `scripts/post-install` and
> `scripts/snapshot-prefs` to match your environment.

---

# Daily Use & Maintenance

| Command | When | What it does |
|---|---|---|
| `make maintain` | Weekly | The whole routine below, in order, then `doctor` |
| `make doctor` | When something feels off | Find what is broken or drifting. `ARGS=--fix` repairs the safe items |
| `make update` | Any time | Upgrade every package via topgrade |
| `make updates` | Any time | macOS updates for this version only — never a major upgrade |
| `make sync` | After installing or removing apps | Record new Homebrew packages in the Brewfile |
| `status` | Any time | Health dashboard TUI; `make status` prints the plain-text version |
| `syncall` | End of day | Commit and push every GitHub repo under `$HOME`, behind a secret scan |

Every one of these works from `~/` as well — `~/Makefile` forwards them to the repo.

## The Weekly Routine (`make maintain`)

```bash
make maintain
```

Runs, in order, carrying on past a step that fails so that `doctor` always gets the last word:

1. `make pull` — fast-forward MiMac to origin (`git pull --ff-only`; a diverged repo is left alone)
2. `make tools` — link any new commands into `~/bin`, and remove links to ones that were deleted
3. `make update` — topgrade
4. `make updates` — macOS updates for the installed version
5. `make build-tools` — rebuild the Go TUIs (about a second on Apple Silicon)
6. `make doctor`

## Health Check (`make doctor`)

`make status` says what is installed; `make doctor` says what is broken. Each check exists
because the problem it looks for was found on a real machine, doing damage nobody had noticed.

```bash
make doctor              # Report; exits 1 if anything needs attention
make doctor ARGS=--fix   # Repair the safe items, then report the rest
```

| Area | What it looks for |
|---|---|
| PATH | `~/bin` on `PATH` |
| Links | Every dotfile linked; no dangling `~/bin` links; no repo command left unlinked |
| Shell startup | Group- or world-writable completion directories, and how long a new shell takes |
| Apple Silicon | Intel Homebrew in `/usr/local`; commands on `PATH` whose interpreter is gone; apps with no arm64 build; a hostname naming another chip |
| Security | Touch ID for `sudo`; firewall |
| MiMac tools | TUI binaries older than their source; LaunchAgents out of date, unloaded or failing |
| Homebrew | `brew doctor`; drift between the Brewfile and what is installed, both directions |
| The repo | Uncommitted work, commits not pushed, commits not pulled |

**What `--fix` touches:** only what is inside `$HOME` or owned by you and cannot lose data —
the `PATH` line, permissions on completion directories you own, completion caches left by an old hostname, dangling and missing `~/bin`
links, and stale TUI binaries. Everything else — removing an old Intel Homebrew, renaming the
Mac, deleting leftover commands in `/usr/local/bin` — prints the command and leaves the
decision to you.

**Why shell startup is a check.** oh-my-zsh runs `compinit -i`, which silently drops any
completion directory `compaudit` calls insecure. The completion cache then never matches the
directories on disk, so it is rebuilt on every new shell. On the machine this was found on — a
group-writable `/usr/local/share/zsh` carried over from an Intel Mac — every new terminal took
0.35 s instead of 0.07 s.

## Package Updates (`make update`)

Runs topgrade with `assets/topgrade.toml` (linked to `~/.config/topgrade.toml` by Phase 3):
Homebrew formulae, every cask including self-updating ones (`greedy_cask`), oh-my-zsh, pipx,
tldr pages, `gh` extensions, and a pull of this repo. Steps it deliberately skips:

| Step | Why |
|---|---|
| `system` | macOS updates go through `make updates`, which never installs a major upgrade |
| `claude_code_plugins` | Runs `claude plugin marketplace update`, which grabs the terminal and gets suspended by `SIGTTOU` — freezing the whole topgrade run |
| `claude_code` | Claude Code updates itself |
| `node`, `pnpm` | Not used on this Mac |

## macOS Updates (`make updates`)

```bash
make updates ARGS=-n   # Preview: what would install, what is left alone
make updates           # Install
```

`bin/macos-updates` lists what Apple offers and installs, by label, only the updates for the
installed major version: point releases, security updates, Safari, Command Line Tools. It
names each major upgrade (macOS 15 → 26, say) and leaves it alone; do those by hand in
System Settings when you are ready.

This replaced `softwareupdate -ia`, which installs *everything* Apple lists — and Apple lists
the next major macOS among them, marked Recommended. In mrk, the project MiMac forked from,
that command started an unrequested 26 GB OS download that kept going after the command
exited. If the list cannot be parsed, nothing is installed.

## Update Notices (`check-updates`)

Runs from `.zshrc`, at most once a week. When the repo has new commits on origin it asks
*"MiMac updates available. Pull them now?"* and runs `make pull`. It never blocks shell
startup on the network: it compares against the last fetched state and refreshes it with a
background `git fetch` for next time.

## Linting the Repo (`make check`)

```bash
make check    # shellcheck every script, go vet every TUI
make tidy     # go mod tidy in every tool — builds no longer do this themselves
```

---

# Day-to-Day Workflow

## Keeping the Brewfile Current (`make sync`)

Whenever you install a new Homebrew package, run `make sync` to record it in the Brewfile.
`make doctor` lists drift in both directions if you forget.

```bash
make sync             # Interactive — opens mimac-picker TUI to select packages
make sync ARGS=-n     # Dry run — show what would be added, make no changes
make sync ARGS=-c     # Auto-commit the Brewfile after updating
make sync-prune       # Preview Brewfile entries that are no longer installed
make sync-clean       # Remove them and commit
```

**How sync works:**

1. Reads the Brewfile to build a list of already-tracked packages
2. Runs `brew leaves` (top-level formulae) and `brew list --cask` to see what's installed
3. Computes the diff — packages installed but not yet in the Brewfile
4. Opens **mimac-picker** TUI: use `Space` to select packages, `Enter` to confirm, `q` to quit
5. For each selected formula, prompts via `gum` to choose which Brewfile section to add it to
6. Casks are auto-assigned to the existing cask section
7. Inserts each entry alphabetically within its section

> **Note:** The mimac-picker binary lives at `bin/mimac-picker` (gitignored, platform-specific).
> If it's missing, rebuild it with `make build-tools`.

## Keeping App Preferences Current (`make snapshot-prefs`)

After configuring an app, run `make snapshot-prefs` to capture its preferences.

```bash
make snapshot-prefs
```

1. Exports the preference plist for each managed app (iTerm2, Loopback, SoundSource, Audio Hijack) using `defaults export`
2. Copies Loopback and SoundSource Application Support files
3. Saves everything to `~/.mimac/preferences/`, where Phase 3 imports it from

## Syncing Every Repository (`syncall`)

`syncall` walks `$HOME` (to `SYNCALL_MAX_DEPTH`, default 7), finds every git repository
whose remotes include GitHub, auto-commits anything dirty and pushes it.

```bash
syncall              # Sweep and push
syncall --dry-run    # Preview: list what would be committed and pushed
```

**Every commit is gated behind a secret scan.** `syncall` stages with `git add -A`, which
picks up untracked files as well as modified ones — so without a gate, a key or token
dropped into any repository under `$HOME` would be committed and pushed to a public remote
without anyone reading it. The scan runs between the `add` and the `commit`, over the
staged set, because the staged set is precisely what is about to be published.

The scanner (`scan_for_secrets` in `scripts/lib.sh`) looks for:

| Kind | Examples |
|---|---|
| Private key material | `-----BEGIN … PRIVATE KEY-----` |
| Credential assignments | `api_key`, `secret_key`, `access_token`, `client_secret`, `password`, `passphrase` followed by 12+ characters |
| Bearer tokens | `Bearer <20+ chars>` |
| Vendor prefixes (case-sensitive) | `sk-` / `sk-ant-`, `ghp_`, `github_pat_`, `AKIA…`, `xox[baprs]-`, `AIza…` |
| Plist key/value pairs | A suggestive `<key>` name with a substantial `<string>` value |

Two details worth knowing. Vendor prefixes are matched **case-sensitively** on purpose —
folded to case-insensitive, `AIza…` matches ordinary base64 in `<data>` blobs and the gate
becomes noise you learn to dismiss. And binary plists are converted to XML in a temp copy
before scanning, because `bplist00` files are not greppable and would otherwise report
clean; the stored file is never modified.

When the scan flags something, `syncall` leaves that repository **staged but uncommitted**
and moves on to the next one — it does not abort the sweep. Inspect the staged files, then
either remove the offending file or re-run and confirm at the prompt. With
`NONINTERACTIVE=1` there is no prompt and the commit is always refused.

## Trimming Background Services (`make trim-services`)

Opt-in, and deliberately **not** part of `make all`. Turning a service off is a decision
about what this machine is for, and each one costs something different.

```bash
make trim-services ARGS=-n   # Preview — change nothing
make trim-services           # Apply
bash ~/.mimac/services-rollback.sh   # Undo everything
```

These are launchd jobs, not `defaults` keys, so they do not belong in `defaults.sh`. The
tool for turning one off permanently is `launchctl disable`, which writes to launchd's
override database rather than to the job's plist — and that is what makes the Apple ones
possible at all: their plists live under `/System/Library/LaunchAgents` where SIP forbids
edits, but the override database is writable and survives a reboot.

| Service | What it is | Cost of disabling |
|---|---|---|
| `com.google.GoogleUpdater.wake` | Google Chrome updater | Wakes hourly. The Brewfile carries `google-chrome` as greedy, so brew already upgrades Chrome. **Chrome reinstalls this agent when it next launches** — re-run after a Chrome update |
| `com.apple.photoanalysisd` | Photos face and scene analysis | Ends People albums, Memories and Visual Look Up. The heaviest item here, and the only one with a real feature cost |
| `com.apple.mediaanalysisd` | Media analysis (Visual Look Up) | Same family as `photoanalysisd` |

Every disable is appended to `~/.mimac/services-rollback.sh`, in the same shape as the
defaults and hardening rollbacks.

One honest limitation in the output: SIP refuses `launchctl bootout` on a running Apple
agent, so for those the override lands but the process keeps running until the next login.
The script says *"disabled — takes effect at next login"* in that case rather than claiming
it stopped something it did not.

## Security Hardening (`make harden`)

Opt-in. Each step records the previous state in `~/.mimac/hardening-rollback.sh` before
changing anything, and a re-run never overwrites what the first run recorded.

| Step | How |
|---|---|
| Touch ID for `sudo` | Adds `pam_tid.so` to `/etc/pam.d/sudo_local` — the file Apple's own template calls the "local config file which survives system update". Editing `/etc/pam.d/sudo` instead, as MiMac once did, is undone by every macOS update |
| Password immediately on wake | `sysadminctl -screenLock immediate`, which asks for your login password. The old `com.apple.screensaver` keys are no longer read by macOS |
| Firewall | Global firewall and stealth mode on |

## Updating This Manual (`make manual`)

The manual source lives in the repo at `docs/manual.md`. After editing it, regenerate the HTML and commit:

```bash
# Edit the source
$EDITOR ~/MiMac/docs/manual.md

# Regenerate the site HTML (requires pandoc)
make manual

# Commit and push both files
cd ~/MiMac
git add docs/manual.md docs/index.html
git commit -m "docs: update manual"
git push
```

> **Note:** Only edit `docs/manual.md` — never edit `docs/index.html` directly, as it is overwritten by `make manual`.

---

# How It Works — The Three Phases

The phases build this Mac's setup from scratch, and re-running any one repairs what it owns.

## Phase 1 — Setup (`make install`)

Script: `scripts/setup`

- Installs Xcode Command Line Tools if not present
- Links everything in `dotfiles/` into `$HOME` as symlinks (backing up any real file first)
- Links `scripts/` and `bin/` into `~/bin`, and removes `~/bin` links whose target was deleted
- Applies macOS system preferences via `scripts/defaults.sh`, recording a rollback script at `~/.mimac/defaults-rollback.sh`
- Sets Zsh as the login shell

**Managed dotfiles:**

| File | Purpose |
|---|---|
| `.aliases` | Shell aliases and functions |
| `.gitconfig` | Git configuration |
| `.hushlogin` | Suppresses "Last login" terminal message |
| `.zprofile` | Zsh login shell profile (Homebrew environment) |
| `.zshenv` | Zsh environment variables |
| `.zshrc` | Zsh interactive shell config |
| `Makefile` | MiMac's daily commands, available from `~/` |

**Running part of Phase 1:**

```
make dotfiles                 # Link dotfiles only
make tools                    # Link scripts/bin into ~/bin only
make defaults                 # Apply macOS defaults only
make trackpad                 # Apply defaults including trackpad settings
make setup-dry                # Preview Phase 1 without applying
```

## Phase 2 — Homebrew (`make brew`)

Script: `scripts/brew-packages`

- Installs Homebrew if not present
- Reads the Brewfile, skips what is already installed
- Lets you pick which of the rest to install, with the mimac-picker TUI or `gum`

## Phase 3 — Post-Install (`make post-install`)

Script: `scripts/post-install`

Configures installed apps. Run after Phase 2, and again after installing an app it manages.

- **Configs:** Links topgrade, `gh` and htop configs into `~/.config`
- **Fonts:** Copies `assets/fonts/` into `~/Library/Fonts`
- **Browsers:** Applies Chrome/Brave managed policies; opens extension install URLs on request
- **Companion app:** Installs Barkeep from its GitHub releases if missing
- **App defaults:** Applies `defaults write` settings for Audio Hijack and Rogue Amoeba update settings
- **Plist imports:** Imports snapshots from `~/.mimac/preferences/`; skips any app that already has a preferences file (non-destructive)
- **App Support restore:** Restores Loopback and SoundSource configuration files (non-destructive)
- **Login items:** Registers noTunes, SoundSource and Loopback
- **LaunchAgents:** Installs and loads the scheduled maintenance jobs (see below)

**Managed app preferences:** iTerm2, Audio Hijack, Loopback (+ App Support files),
SoundSource (+ App Support files).

**Scheduled maintenance (LaunchAgents):**

Agents are copied from `assets/launchagents/` into `~/Library/LaunchAgents` and loaded
immediately. Phase 3 unloads before it loads, because launchd keys a job by its `Label`
rather than by the file — a bare `load` against an already-loaded label fails and silently
keeps the previous definition, so an edited schedule would not take effect until logout.
`make doctor` flags an installed agent that differs from the repo copy.

| Label | Runs | What it does |
|---|---|---|
| `com.user.clear_app_caches` | Daily at 03:00, and at login | Runs `~/bin/clear-app-caches`, clearing the Discord cache directories (Chrome's cache is left alone) |

`make uninstall` unloads and deletes these agents, and `nuke-mimac` unloads and trashes
them. Both have to: the agent invokes a `~/bin` symlink that each of them removes, so
leaving the job registered would schedule a daily run against a path that no longer exists.
`nuke-mimac` handles them before it touches `~/bin`, and also runs
`~/.mimac/services-rollback.sh` if `trim-services` has written one.

Because `clear-app-caches` runs unattended here, it refuses to do anything when `HOME` is
unset or is not a directory — without that guard every `rm -rf "$HOME/Library/…"` in it
would become an absolute path outside the home directory.

---

# Setting Up or Rebuilding a Mac

Needs macOS 15 or later and an internet connection.

```bash
git clone https://github.com/MiloTGB/MiMac.git ~/MiMac
cd ~/MiMac
make install        # Phase 1 — then open a new terminal (or exec zsh)
make brew           # Phase 2 — the long one
make post-install   # Phase 3
make build-tools    # mimac-picker (needed by make sync), bf, mimac-status
make dock
make doctor         # Confirm everything landed; ARGS=--fix for the safe repairs
```

`make all` runs Phases 1–3 and `build-tools` in one go. Phase 3 switches the repo's remote
from HTTPS to SSH once `ssh -T git@github.com` succeeds.

**Coming from another Mac with Migration Assistant?** Run `make doctor` first. Migration
carries over things that do not belong on Apple Silicon — an Intel Homebrew in `/usr/local`,
scripts pointing at interpreters that no longer exist, a hostname naming the old chip — and
doctor lists each one with the command that removes it.

**Still manual:** Mac App Store apps (Final Cut Pro, iMovie, Keynote, Numbers, Pages,
Pixelmator Pro), FL Studio and FL Cloud Plugins, Safari settings (sandboxed since Sequoia),
and signing in to 1Password/Bitwarden and cloud storage.

---

# Command Reference

## From Anywhere (`~/Makefile`)

`~/Makefile` is linked by Phase 1. `make help` from `~/` lists these first, then everything
from `~/MiMac/`.

| Command | Description |
|---|---|
| `make maintain` | Weekly upkeep: pull, relink, update, macOS updates, rebuild TUIs, doctor |
| `make doctor` | Health check (`ARGS=--fix` to repair the safe items) |
| `make update` | Upgrade all packages (topgrade) |
| `make updates` | macOS updates for this version only (`ARGS=-n` to preview) |
| `make status` | Show installation status |
| `make sync` | Sync installed Homebrew packages into the Brewfile (`ARGS=-c` commit, `ARGS=-n` dry run) |
| `make pull` | Fast-forward MiMac to origin |
| `make snapshot-prefs` | Export app preferences |
| `make build-tools` | Rebuild the Go TUIs |
| `make manual` | Regenerate `docs/index.html` |

## From `~/MiMac/`

Everything above, plus:

| Command | Description |
|---|---|
| `make all` | Full install: Phases 1–3 + TUI binaries |
| `make install` / `make setup` | Phase 1: shell, dotfiles, macOS defaults |
| `make brew` | Phase 2: Homebrew packages and casks |
| `make post-install` | Phase 3: app configs, login items, LaunchAgents |
| `make dotfiles` / `make tools` | Relink dotfiles / `~/bin` only |
| `make defaults` / `make trackpad` | Apply macOS defaults (with trackpad settings) |
| `make dock` | Populate the Dock |
| `make harden` | Security hardening |
| `make trim-services` | Disable background launchd agents this Mac does not need (`ARGS=-n` to preview) |
| `make sync-prune` / `make sync-clean` | Preview / remove Brewfile entries no longer installed |
| `make sync-login-items` | Sync system login items into post-install |
| `make check` | shellcheck every script, `go vet` every TUI |
| `make tidy` | `go mod tidy` in every tool |
| `make uninstall` | Remove symlinks and undo setup |
| `make nuke` / `make nuke-execute` | Preview / perform complete MiMac removal |
| `make fix-exec` | Make all scripts and bin files executable |
| `make help` | Show all available commands |

## Standalone Commands (`~/bin`)

Symlinked into `~/bin` by Phase 1.

| Command | Purpose |
|---|---|
| `status` | Health dashboard TUI (`mimac-status`) |
| `doctor` | Same as `make doctor` |
| `macos-updates` | Same as `make updates` |
| `syncall` | Commit and push every GitHub repository under `$HOME`, behind the secret scan — see [Syncing Every Repository](#syncing-every-repository-syncall). `--dry-run` previews |
| `check-updates` | Weekly "MiMac has new commits" prompt; runs from `.zshrc` |
| `clear-app-caches` | Clears the Discord cache directories. Also runs from a LaunchAgent daily at 03:00 |
| `trim-services` | Same as `make trim-services` |
| `hide_tm.sh` | Hides Time Machine volumes from the Finder sidebar. Volume names as arguments, or set `TM_VOLUMES` |
| `audio-mode` / `zoom-mode` | Pause sync clients and distractions for recording sessions or calls |
| `bf` | Brewfile manager TUI |

> `scripts/lib.sh` and `bin/lib/common.sh` are sourced libraries, not commands. They are
> tracked non-executable, and `fix-exec` skips `lib.sh` so the bit is not re-added.

---

# What `make status` Checks

- **Dotfiles** — Which files are symlinked into `~/` and which are missing
- **Tools** — Which scripts/bin symlinks are live in `~/bin` and which are broken
- **macOS Defaults** — Whether defaults have been applied (rollback script present)
- **Backups** — Number of dotfile backups in `~/.mimac/backups/`
- **Shell** — Current login shell (should be Zsh)
- **PATH** — Whether `~/bin` is on the PATH
- **Homebrew** — Version installed
- **Brewfile packages** — Each formula and cask: installed or missing

For problems rather than inventory, use `make doctor`.

---

# State Files

MiMac writes runtime state to `~/.mimac/` and `~/.cache/mimac/`:

| File / Directory | Purpose |
|---|---|
| `~/.mimac/preferences/` | Local snapshot of app plists + App Support files |
| `~/.mimac/backups/` | Timestamped backups of dotfiles that were replaced during setup |
| `~/.mimac/defaults-rollback.sh` | Undo every `defaults write` MiMac made |
| `~/.mimac/hardening-rollback.sh` | Undo security hardening |
| `~/.mimac/services-rollback.sh` | Re-enable services turned off by `trim-services` |
| `~/.mimac/install.log` | Log of the setup phases |
| `~/.cache/mimac/last-update-check` | When `check-updates` last looked |

Each rollback script records the state *before* MiMac's first change, and re-runs never
overwrite it. To undo macOS defaults:

```bash
bash ~/.mimac/defaults-rollback.sh
```

---

# Troubleshooting

| Problem | Solution |
|---|---|
| Something is off and you are not sure what | `make doctor` — then `make doctor ARGS=--fix` for the safe repairs |
| New terminals open slowly | `make doctor` checks the usual cause (insecure completion directories) and times a new shell |
| `make setup` fails at Xcode CLT | Run `xcode-select --install`, wait for the GUI install dialog to complete, then re-run |
| Dotfile conflict ("file exists" warning) | Backup auto-created in `~/.mimac/backups/`; resolve manually then re-run |
| A command in `~/bin` stopped working after `make pull` | `make tools` relinks and removes dead links (`make maintain` does this for you) |
| `make updates` says it is not installing a macOS version | By design — major upgrades are done by hand in System Settings |
| topgrade appears to hang | Check `~/.config/topgrade.toml` still links to `assets/topgrade.toml`, which disables the step that suspends it |
| post-install skips plist imports | No snapshot in `~/.mimac/preferences` yet — run `make snapshot-prefs` on a configured Mac |
| mimac-picker not rendering | Rebuild: `make build-tools` |
| `~/bin` not on PATH | `make doctor ARGS=--fix` adds it to `.zshrc` |
| Brewfile entry shows missing | Package name may differ from formula name; check with `brew info <pkg>` |
| `make sync` exits with "nothing to add" | All installed packages are already in the Brewfile — nothing to do |
| `make snapshot-prefs` fails for an app | App is not installed or `defaults export` failed; check the app is running |
| post-install login item already exists | Safe to ignore — `add_login_item` checks before adding |
