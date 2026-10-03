// mimac-picker — interactive Brewfile package selector
// Two-pane Bubble Tea TUI: categories (left) | packages with descriptions (right)
// Outputs selected packages as "formula:name" or "cask:name" lines to stdout,
// and packages marked to ignore as "ignore-formula:name" or "ignore-cask:name".
package main

import (
	"bufio"
	"flag"
	"fmt"
	"os"
	"regexp"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	theme "mimac-theme"
)

// ── Types ─────────────────────────────────────────────────────────────────

type pkgKind string

const (
	formula pkgKind = "formula"
	cask    pkgKind = "cask"
)

type pkg struct {
	name      string
	kind      pkgKind
	line      string
	desc      string
	installed bool
	selected  bool
	// Marked for ~/.mimac/sync-ignore rather than the Brewfile. Mutually
	// exclusive with selected: "add this" and "never offer this again" are
	// opposite answers to the same question.
	ignored bool
}

type category struct {
	name string
	pkgs []*pkg
}

// ── Descriptions ──────────────────────────────────────────────────────────

var descriptions = map[string]string{
	// Formulae
	"bash":              "Modern shell (Bash 5.x) with improved features",
	"bash-completion@2": "Programmable tab completion for Bash 4.1+",
	"bat":               "cat clone with syntax highlighting and Git integration",
	"coreutils":         "GNU core utilities — enhanced versions of standard Unix tools",
	"dockutil":          "Command-line tool for managing Dock items",
	"fastfetch":         "Fast, customizable system information display",
	"gh":                "GitHub CLI — official command-line tool for GitHub",
	"git":               "Distributed version control system",
	"gnupg":             "GNU Privacy Guard — encryption and signing tool",
	"gum":               "Charm TUI toolkit — used as fallback package picker",
	"htop":              "Interactive process viewer and system monitor",
	"lsd":               "Modern ls replacement with colors and icons",
	"lzip":              "Lossless data compressor based on LZMA",
	"moreutils":         "Useful Unix utilities: sponge, vidir, ts, and more",
	"most":              "Powerful paging program (alternative to less)",
	"nano":              "Simple terminal text editor",
	"nanorc":            "Syntax highlighting configurations for nano",
	"ncdu":              "Disk usage analyzer with ncurses interface",
	"nethogs":           "Monitor network bandwidth usage per process",
	"nmap":              "Network exploration and security auditing tool",
	"node@22":           "Node.js 22 LTS JavaScript runtime",
	"openssh":           "OpenSSH client and server for secure remote access",
	"osx-cpu-temp":      "Display CPU temperature from the command line",
	"pwgen":             "Secure, memorable password generator",
	"speedtest-cli":     "Command-line interface for testing internet bandwidth",
	"tealdeer":          "Fast tldr client — simplified, practical man pages",
	"topgrade":          "Update everything at once across all package managers",
	"zip":               "Compression and file packaging utility",
	"zsh":               "Z shell — advanced interactive shell with many features",
	"openjdk":           "OpenJDK — open-source Java Development Kit",
	"pipx":              "Install and run Python apps in isolated environments",
	"pyenv":             "Python version manager",
	"python@3.12":       "Python 3.12 programming language interpreter",
	"ripgrep":           "Extremely fast regex search tool (rg)",
	"shellcheck":        "Static analysis and linting tool for shell scripts",
	"shfmt":             "Shell script formatter",
	"ffmpeg":            "Complete solution for audio/video recording and conversion",
	"go":                "Go programming language — required for building MiMac TUI tools",
	"sox":               "Sound eXchange — Swiss army knife for audio manipulation",
	"trash":             "Move files to macOS Trash instead of permanent deletion",
	"tree":              "Display directory structure as a tree diagram",
	"watch":             "Execute a command periodically and display the output",
	"wget":              "Network file downloader with retry and resume support",
	// Casks
	"4k-video-downloader+": "Download videos from YouTube and other platforms",
	"appcleaner":           "Completely uninstall apps and all their leftover files",
	"audio-hijack":         "Record and process audio from any application",
	"bitwarden":            "Open-source password manager",
	"brave-browser":        "Privacy-focused browser based on Chromium",
	"canva":                "Online design and visual content platform",
	"discord":              "Voice, video, and text chat for communities",
	"google-chrome":        "Google Chrome web browser",
	"handbrake":            "Open-source video transcoder",
	"iterm2":               "Feature-rich terminal emulator for macOS",
	"libreoffice":          "Free and open-source office suite",
	"loopback":             "Cable-free audio routing between apps on Mac",
	"mediainfo":            "Display technical information about media files",
	"minecraft":            "Minecraft game launcher",
	"notunes":              "Prevent Apple Music from launching on media key press",
	"obs":                  "Open Broadcaster Software for streaming and recording",
	"pearcleaner":          "Open-source app uninstaller for macOS",
	"scratch":              "Visual programming language for kids and beginners",
	"soundsource":          "System-wide per-application audio control for Mac",
	"steam":                "Steam PC gaming platform and library",
	"the-unarchiver":       "Archive extractor supporting many formats",
	"vlc":                  "Free, open-source media player for any format",
	"whatsapp":             "WhatsApp desktop messaging client",
	"zoom":                 "Video conferencing and online meetings",
}

// ── Brewfile parsing ──────────────────────────────────────────────────────

var (
	formulaRe = regexp.MustCompile(`^brew "([^"]+)"`)
	caskRe    = regexp.MustCompile(`^cask "([^"]+)"`)
)

// categoryName extracts a short, friendly name from a Brewfile comment line.
func categoryName(comment string) string {
	name := comment
	// "X - Y": use Y when ≤2 words (specific), otherwise use X (general)
	if idx := strings.LastIndex(name, " - "); idx != -1 {
		suffix := name[idx+3:]
		if len(strings.Fields(suffix)) <= 2 {
			name = suffix
		} else {
			name = name[:idx]
		}
	}
	// Strip "/ ..." or "& ..." qualifiers
	if idx := strings.Index(name, " / "); idx != -1 {
		name = name[:idx]
	}
	if idx := strings.Index(name, " & "); idx != -1 {
		name = name[:idx]
	}
	// "Casks" alone is not meaningful in context
	if strings.TrimSpace(name) == "Casks" {
		name = "Applications"
	}
	return strings.TrimSpace(name)
}

func parseBrewfile(
	path string,
	installedFormulae, installedCasks map[string]bool,
	skipFormulae, skipCasks bool,
) ([]category, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	var cats []category
	var curCat *category

	push := func(p *pkg) {
		if curCat == nil {
			cats = append(cats, category{name: "General"})
			curCat = &cats[len(cats)-1]
		}
		curCat.pkgs = append(curCat.pkgs, p)
	}

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := scanner.Text()
		trimmed := strings.TrimSpace(line)

		if strings.HasPrefix(trimmed, "#") {
			text := strings.TrimSpace(strings.TrimPrefix(trimmed, "#"))
			// Skip blank comments, "Taps", and commented-out mas lines
			if text == "" || text == "Taps" || strings.HasPrefix(text, "mas ") {
				continue
			}
			name := categoryName(text)
			if name == "" {
				continue
			}
			cats = append(cats, category{name: name})
			curCat = &cats[len(cats)-1]
			continue
		}

		if m := formulaRe.FindStringSubmatch(line); m != nil {
			if !skipFormulae {
				name := m[1]
				push(&pkg{
					name:      name,
					kind:      formula,
					line:      line,
					desc:      descriptions[name],
					installed: installedFormulae[name],
				})
			}
			continue
		}

		if m := caskRe.FindStringSubmatch(line); m != nil {
			if !skipCasks {
				name := m[1]
				push(&pkg{
					name:      name,
					kind:      cask,
					line:      line,
					desc:      descriptions[name],
					installed: installedCasks[name],
				})
			}
		}
	}

	// Drop empty categories
	out := cats[:0]
	for _, c := range cats {
		if len(c.pkgs) > 0 {
			out = append(out, c)
		}
	}
	return out, scanner.Err()
}

// ── Model ─────────────────────────────────────────────────────────────────

type model struct {
	cats      []category
	catIdx    int  // left-pane cursor
	pkgIdx    int  // right-pane cursor
	leftFocus bool // which pane has keyboard focus
	width     int
	height    int
	confirmed bool
	cancelled bool
	// ctrl+c only. An `i` mark is a decision already made, so quitting with q
	// or esc keeps the marks while dropping the pending additions; a hard
	// interrupt drops everything. Marking packages and then quitting is the
	// natural move when adding nothing, and mrk's picker once threw the marks
	// away on it, so the same packages came back the next run.
	aborted bool
	// noIgnore hides the ignore key, for brew-packages: Phase 2 installs from
	// the Brewfile and keeps no ignore list, so a mark there would have nowhere
	// to go. sync, which keeps ~/.mimac/sync-ignore, leaves it false.
	noIgnore bool
}

func newModel(cats []category) model {
	return model{cats: cats, leftFocus: true}
}

func (m model) Init() tea.Cmd { return nil }

func (m model) currentPkgs() []*pkg {
	if m.catIdx >= len(m.cats) {
		return nil
	}
	return m.cats[m.catIdx].pkgs
}

func (m model) totalSelected() int {
	n := 0
	for _, c := range m.cats {
		for _, p := range c.pkgs {
			if p.selected {
				n++
			}
		}
	}
	return n
}

func (m model) totalIgnored() int {
	n := 0
	for _, c := range m.cats {
		for _, p := range c.pkgs {
			if p.ignored {
				n++
			}
		}
	}
	return n
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height

	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c":
			m.aborted = true
			m.cancelled = true
			return m, tea.Quit
		case "q":
			m.cancelled = true
			return m, tea.Quit
		case "esc":
			if !m.leftFocus {
				m.leftFocus = true
			} else {
				m.cancelled = true
				return m, tea.Quit
			}
		case "enter":
			m.confirmed = true
			return m, tea.Quit

		case "tab", "shift+tab":
			m.leftFocus = !m.leftFocus
		case "left", "h":
			m.leftFocus = true
		case "right", "l":
			m.leftFocus = false

		case "up", "k":
			if m.leftFocus {
				if m.catIdx > 0 {
					m.catIdx--
					m.pkgIdx = 0
				}
			} else {
				if m.pkgIdx > 0 {
					m.pkgIdx--
				}
			}
		case "down", "j":
			if m.leftFocus {
				if m.catIdx < len(m.cats)-1 {
					m.catIdx++
					m.pkgIdx = 0
				}
			} else {
				pkgs := m.currentPkgs()
				if m.pkgIdx < len(pkgs)-1 {
					m.pkgIdx++
				}
			}

		case " ":
			if !m.leftFocus {
				pkgs := m.currentPkgs()
				if m.pkgIdx < len(pkgs) {
					p := pkgs[m.pkgIdx]
					if !p.installed {
						p.selected = !p.selected
						if p.selected {
							p.ignored = false
						}
						if m.pkgIdx < len(pkgs)-1 {
							m.pkgIdx++
						}
					}
				}
			}

		case "i":
			if !m.leftFocus && !m.noIgnore {
				pkgs := m.currentPkgs()
				if m.pkgIdx < len(pkgs) {
					p := pkgs[m.pkgIdx]
					if !p.installed {
						p.ignored = !p.ignored
						if p.ignored {
							p.selected = false
						}
						if m.pkgIdx < len(pkgs)-1 {
							m.pkgIdx++
						}
					}
				}
			}

		case "a":
			if !m.leftFocus {
				pkgs := m.currentPkgs()
				// Toggle: if all uninstalled are selected -> deselect all; else select all
				allOn := true
				for _, p := range pkgs {
					if !p.installed && !p.selected {
						allOn = false
						break
					}
				}
				for _, p := range pkgs {
					if !p.installed {
						p.selected = !allOn
						if p.selected {
							p.ignored = false
						}
					}
				}
			}
		}
	}
	return m, nil
}

// ── Styles ────────────────────────────────────────────────────────────────

var (
	styleCount     = lipgloss.NewStyle().Bold(true).Foreground(theme.ColAccent)
	styleCatActive = lipgloss.NewStyle().Bold(true).Foreground(theme.ColHighlight)
	styleCatNorm   = lipgloss.NewStyle().Foreground(theme.ColNormal)
	styleBadgeDim  = lipgloss.NewStyle().Foreground(theme.ColSubtle)
	styleInstalled = lipgloss.NewStyle().Foreground(theme.ColDim)
	stylePkgSel    = lipgloss.NewStyle().Foreground(theme.ColGreen)
	stylePkgIgn    = lipgloss.NewStyle().Foreground(theme.ColAmber)
	stylePkgCurs   = lipgloss.NewStyle().Bold(true).Foreground(theme.ColHighlight)
	styleDescDim   = lipgloss.NewStyle().Foreground(theme.ColSubtle)
)

// ── View ──────────────────────────────────────────────────────────────────

func (m model) View() string {
	if m.width == 0 {
		return "Initializing…"
	}

	const leftInner = 22
	rightInner := m.width - leftInner - 4
	if rightInner < 10 {
		rightInner = 10
	}
	paneH := m.height - 4
	if paneH < 1 {
		paneH = 1
	}

	header := m.viewHeader()
	left := m.viewLeft(leftInner, paneH)
	right := m.viewRight(rightInner, paneH)
	footer := m.viewFooter()

	panes := lipgloss.JoinHorizontal(lipgloss.Top, left, right)
	return lipgloss.JoinVertical(lipgloss.Left, header, panes, footer)
}

func (m model) viewHeader() string {
	title := theme.StyleTitle.Render("MiMac brew")
	selText := fmt.Sprintf("%d selected", m.totalSelected())
	if ign := m.totalIgnored(); ign > 0 {
		selText += fmt.Sprintf(" · %d ignored", ign)
	}
	sel := styleCount.Render(selText)
	gap := m.width - lipgloss.Width(title) - lipgloss.Width(sel)
	if gap < 1 {
		gap = 1
	}
	return title + strings.Repeat(" ", gap) + sel
}

// viewFooter truncates to the terminal width: a footer that wraps costs a body
// line, and lipgloss pads every line of the frame to the widest one.
func (m model) viewFooter() string {
	help := "↑↓/jk move · tab/hl pane · space add · i ignore · a all · enter ok · q quit (ignores kept)"
	if m.noIgnore {
		help = "↑↓/jk move · tab/hl pane · space toggle · a all · enter confirm · q quit"
	}
	if m.width > 0 {
		help = theme.Truncate(help, m.width)
	}
	return theme.StyleFooter.Render(help)
}

func (m model) viewLeft(inner, height int) string {
	var sb strings.Builder
	lines := 0

	start := 0
	if m.catIdx >= height {
		start = m.catIdx - height + 1
	}

	for i, cat := range m.cats {
		if i < start {
			continue
		}
		if lines >= height {
			break
		}

		selN := 0
		for _, p := range cat.pkgs {
			if p.selected {
				selN++
			}
		}
		total := len(cat.pkgs)

		badge := fmt.Sprintf("(%d)", total)
		if selN > 0 {
			badge = fmt.Sprintf("(%d/%d)", selN, total)
		}

		nameW := inner - len(badge) - 3
		if nameW < 1 {
			nameW = 1
		}
		name := cat.name
		if len(name) > nameW {
			name = name[:nameW-1] + "…"
		}
		pad := nameW - len(name)
		if pad < 0 {
			pad = 0
		}

		var line string
		isActive := i == m.catIdx
		if isActive {
			if m.leftFocus {
				line = styleCatActive.Render("▸ "+name) + strings.Repeat(" ", pad+1) + styleCount.Render(badge)
			} else {
				line = styleCatNorm.Render("▸ "+name) + strings.Repeat(" ", pad+1) + styleCatNorm.Render(badge)
			}
		} else {
			line = styleCatNorm.Render("  "+name) + strings.Repeat(" ", pad+1) + styleBadgeDim.Render(badge)
		}

		sb.WriteString(line + "\n")
		lines++
	}

	content := strings.TrimRight(sb.String(), "\n")
	pane := theme.StylePaneOff
	if m.leftFocus {
		pane = theme.StylePaneOn
	}
	return pane.Width(inner).Height(height).Render(content)
}

func (m model) viewRight(inner, height int) string {
	pkgs := m.currentPkgs()
	pane := theme.StylePaneOff
	if !m.leftFocus {
		pane = theme.StylePaneOn
	}

	if len(pkgs) == 0 {
		return pane.Width(inner).Height(height).Render(
			styleDescDim.Render("No packages"),
		)
	}

	start := 0
	if m.pkgIdx >= height {
		start = m.pkgIdx - height + 1
	}

	const nameW = 24
	descW := inner - nameW - 4
	if descW < 0 {
		descW = 0
	}

	var sb strings.Builder
	written := 0

	for i, p := range pkgs {
		if i < start {
			continue
		}
		if written >= height {
			break
		}

		indicator := "  "
		if p.installed {
			indicator = styleInstalled.Render("● ")
		} else if p.selected {
			indicator = stylePkgSel.Render("✓ ")
		} else if p.ignored {
			indicator = stylePkgIgn.Render("✗ ")
		}

		isCursor := i == m.pkgIdx && !m.leftFocus

		name := p.name
		if len(name) > nameW {
			name = name[:nameW-1] + "…"
		}
		pad := nameW - len(name)
		if pad < 0 {
			pad = 0
		}

		desc := p.desc
		if descW > 0 && len(desc) > descW {
			desc = desc[:descW-1] + "…"
		}

		var line string
		switch {
		case p.installed:
			line = indicator +
				styleInstalled.Render(name) + strings.Repeat(" ", pad+2) +
				styleInstalled.Render(desc)
		case isCursor && p.ignored:
			line = stylePkgCurs.Render("▸ ") +
				stylePkgCurs.Render(name) + strings.Repeat(" ", pad+2) +
				stylePkgIgn.Render(desc)
		case isCursor && p.selected:
			line = stylePkgCurs.Render("▸ ") +
				stylePkgCurs.Render(name) + strings.Repeat(" ", pad+2) +
				stylePkgSel.Render(desc)
		case isCursor:
			line = stylePkgCurs.Render("▸ ") +
				stylePkgCurs.Render(name) + strings.Repeat(" ", pad+2) +
				styleDescDim.Render(desc)
		case p.selected:
			line = indicator +
				stylePkgSel.Render(name) + strings.Repeat(" ", pad+2) +
				stylePkgSel.Render(desc)
		case p.ignored:
			line = indicator +
				stylePkgIgn.Render(name) + strings.Repeat(" ", pad+2) +
				stylePkgIgn.Render(desc)
		default:
			line = indicator +
				styleCatNorm.Render(name) + strings.Repeat(" ", pad+2) +
				styleDescDim.Render(desc)
		}

		sb.WriteString(line + "\n")
		written++
	}

	content := strings.TrimRight(sb.String(), "\n")
	return pane.Width(inner).Height(height).Render(content)
}

// ── Main ──────────────────────────────────────────────────────────────────

// emitLines renders the picker's decisions as "type:name" lines. Ignored
// packages take an "ignore-" prefixed type rather than a third field, so the
// caller's `IFS=: read -r a b` split keeps working unchanged.
//
// cancelled means the user left with q or esc: the pending additions are
// dropped, and the ignore marks kept. A ctrl+c abort exits before this.
func emitLines(cats []category, cancelled bool) []string {
	var out []string
	for _, cat := range cats {
		for _, p := range cat.pkgs {
			switch {
			case p.selected && !cancelled:
				out = append(out, fmt.Sprintf("%s:%s", p.kind, p.name))
			case p.ignored:
				out = append(out, fmt.Sprintf("ignore-%s:%s", p.kind, p.name))
			}
		}
	}
	return out
}

// exitStatus is the picker's status as its callers read it. With the ignore key
// hidden (brew-packages), q and esc are a cancel, status 1, as they always
// were: there is no mark to keep. With it shown (sync), they keep the marks,
// status 0. ctrl+c is status 1 either way.
func exitStatus(m model) int {
	if m.aborted || (m.cancelled && m.noIgnore) {
		return 1
	}
	return 0
}

func main() {
	brewfilePath := flag.String("brewfile", "Brewfile", "Path to Brewfile")
	installedFormulaeStr := flag.String("installed-formulae", "", "Comma-separated installed formulae")
	installedCasksStr := flag.String("installed-casks", "", "Comma-separated installed casks")
	skipFormulae := flag.Bool("skip-formulae", false, "Exclude formulae from picker")
	skipCasks := flag.Bool("skip-casks", false, "Exclude casks from picker")
	noIgnore := flag.Bool("no-ignore", false, "Hide the ignore key (brew-packages, which keeps no ignore list)")
	flag.Parse()

	installedFormulae := map[string]bool{}
	installedCasks := map[string]bool{}
	for _, s := range strings.Split(*installedFormulaeStr, ",") {
		if s = strings.TrimSpace(s); s != "" {
			installedFormulae[s] = true
		}
	}
	for _, s := range strings.Split(*installedCasksStr, ",") {
		if s = strings.TrimSpace(s); s != "" {
			installedCasks[s] = true
		}
	}

	cats, err := parseBrewfile(*brewfilePath, installedFormulae, installedCasks, *skipFormulae, *skipCasks)
	if err != nil {
		fmt.Fprintf(os.Stderr, "mimac-picker: %v\n", err)
		os.Exit(1)
	}
	if len(cats) == 0 {
		fmt.Fprintln(os.Stderr, "mimac-picker: no packages found in Brewfile")
		os.Exit(1)
	}

	// Open /dev/tty explicitly so the TUI renders correctly even when
	// stdout is captured by a shell subshell ($(...)).
	tty, err := os.OpenFile("/dev/tty", os.O_RDWR, 0)
	if err != nil {
		fmt.Fprintf(os.Stderr, "mimac-picker: cannot open terminal: %v\n", err)
		os.Exit(1)
	}
	defer tty.Close()

	m := newModel(cats)
	m.noIgnore = *noIgnore
	p := tea.NewProgram(m, tea.WithAltScreen(), tea.WithInput(tty), tea.WithOutput(tty))
	final, err := p.Run()
	if err != nil {
		fmt.Fprintf(os.Stderr, "mimac-picker: %v\n", err)
		os.Exit(1)
	}

	result := final.(model)
	if rc := exitStatus(result); rc != 0 {
		os.Exit(rc)
	}
	for _, line := range emitLines(result.cats, result.cancelled) {
		fmt.Println(line)
	}
}
