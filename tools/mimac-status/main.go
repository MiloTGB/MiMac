// mimac-status — the daily dashboard: what is unrecorded, what has fallen
// behind, Time Machine, and the installation, folded into one panel.
// Two-pane Bubble Tea TUI: panels (left) | detail (right); --plain prints the
// same panels as text, for scripts/status and make status. Ported from
// mrk-status (sevmorris/mrk), which replaced its installation-only dashboard
// with these panels on 2026-09-30.
package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	theme "mimac-theme"
)

// Version and GitSHA are set at build time through -ldflags (make build-tools).
var (
	Version = "dev"
	GitSHA  = "unknown"
)

// ── Severity ──────────────────────────────────────────────────────────────

type severity int

const (
	sevOK   severity = iota // ✓
	sevInfo                 // ·
	sevWarn                 // ⚠
	sevErr                  // ✗
)

func (s severity) icon() string {
	switch s {
	case sevOK:
		return "✓"
	case sevWarn:
		return "⚠"
	case sevErr:
		return "✗"
	default:
		return "·"
	}
}

// ── Data ──────────────────────────────────────────────────────────────────

type statusLine struct {
	sev  severity
	text string
	fix  string // this line's own fix, shown beside it, or ""
}

type group struct {
	name  string
	sev   severity
	lines []statusLine
	fix   string // shell command to run, or ""
}

func sl(sev severity, text string) statusLine { return statusLine{sev: sev, text: text} }

func worst(lines []statusLine) severity {
	s := sevOK
	for _, l := range lines {
		if l.sev > s {
			s = l.sev
		}
	}
	return s
}

// ── Installation checks ───────────────────────────────────────────────────

// isDotfile is lib.sh's mimac_is_dotfile: a regular file, never a directory or
// a link, and not documentation, an example or .DS_Store. Claude Code creates
// dotfiles/.claude/ for a session started there; it is not a dotfile.
func isDotfile(e os.DirEntry) bool {
	n := e.Name()
	return e.Type().IsRegular() && n != ".DS_Store" &&
		!strings.HasSuffix(n, ".example") && !strings.HasPrefix(n, "README") && !strings.HasSuffix(n, ".md")
}

func checkDotfiles(repoRoot, home string) group {
	dotDir := filepath.Join(repoRoot, "dotfiles")
	entries, err := os.ReadDir(dotDir)
	if err != nil {
		return group{"Dotfiles", sevWarn,
			[]statusLine{sl(sevWarn, "dotfiles/ not found")}, "make dotfiles"}
	}

	var lines []statusLine
	linked, missing := 0, 0
	for _, e := range entries {
		if !isDotfile(e) {
			continue
		}
		n := e.Name()
		src := filepath.Join(dotDir, n)
		dst := filepath.Join(home, n)
		if t, err := os.Readlink(dst); err == nil && t == src {
			linked++
			lines = append(lines, sl(sevOK, n))
		} else {
			missing++
			if _, err2 := os.Lstat(dst); err2 == nil {
				lines = append(lines, sl(sevWarn, n+" (something else is there — make dotfiles backs it up and links it)"))
			} else {
				lines = append(lines, sl(sevWarn, n+" (not linked — run make dotfiles)"))
			}
		}
	}

	// make dotfiles, the phase that links them, and not make setup: that runs
	// every phase, the macOS defaults with their Finder and Dock restart among
	// them, to link one file.
	fix := ""
	if missing > 0 {
		fix = "make dotfiles"
	}
	summary := fmt.Sprintf("%d linked", linked)
	if missing > 0 {
		summary += fmt.Sprintf(", %d not linked", missing)
	}
	all := append([]statusLine{sl(sevInfo, summary)}, lines...)
	sev := worst(lines)
	if len(lines) == 0 {
		sev = sevInfo
	}
	return group{"Dotfiles", sev, all, fix}
}

// checkTools counts the ~/bin links into the checkout, and the ones whose
// target is gone: a script deleted or renamed upstream. make tools (setup
// --only tools) prunes exactly those and links what is new.
func checkTools(repoRoot, binDir string) group {
	entries, err := os.ReadDir(binDir)
	if err != nil {
		return group{"Tools", sevWarn,
			[]statusLine{sl(sevWarn, binDir+" not found")}, "make tools"}
	}

	var lines []statusLine
	linked, broken := 0, 0
	for _, e := range entries {
		if e.Type()&os.ModeSymlink == 0 {
			continue
		}
		full := filepath.Join(binDir, e.Name())
		target, err := os.Readlink(full)
		if err != nil || !strings.HasPrefix(target, repoRoot+"/") {
			continue
		}
		if _, err := os.Stat(target); err == nil {
			linked++
		} else {
			broken++
			lines = append(lines, sl(sevWarn, e.Name()+" (broken → "+target+")"))
		}
	}

	fix := ""
	if broken > 0 {
		fix = "make tools"
	}
	summary := fmt.Sprintf("%d linked", linked)
	if broken > 0 {
		summary += fmt.Sprintf(", %d broken", broken)
	}
	all := append([]statusLine{sl(sevInfo, summary)}, lines...)
	sev := sevOK
	if broken > 0 {
		sev = sevWarn
	}
	return group{"Tools", sev, all, fix}
}

// countLines counts PATH's lines that match pattern. A read that fails part
// way is an error, not a short count.
func countLines(path, pattern string) (int, error) {
	re := regexp.MustCompile(pattern)
	f, err := os.Open(path)
	if err != nil {
		return 0, err
	}
	defer f.Close()
	n := 0
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		if re.MatchString(sc.Text()) {
			n++
		}
	}
	return n, sc.Err()
}

// checkDefaults and checkHardening read the rollback scripts defaults.sh and
// hardening.sh write: the only record that either ran. The dashboard used to
// look for ~/.mimac/stamps, which nothing writes, and warned on every Mac.
func checkDefaults(stateDir string) group {
	rollback := filepath.Join(stateDir, "defaults-rollback.sh")
	if _, err := os.Stat(rollback); err != nil {
		return group{"macOS Defaults", sevInfo,
			[]statusLine{sl(sevInfo, "Not applied — run: make defaults")}, "make defaults"}
	}
	n, err := countLines(rollback, `defaults write|defaults delete`)
	if err != nil {
		return group{"macOS Defaults", sevWarn,
			[]statusLine{sl(sevWarn, "Cannot read the rollback script: "+err.Error())}, ""}
	}
	if n == 0 {
		return group{"macOS Defaults", sevInfo,
			[]statusLine{sl(sevInfo, "Rollback script present but empty")}, ""}
	}
	return group{"macOS Defaults", sevOK, []statusLine{
		sl(sevOK, "Applied"),
		sl(sevInfo, fmt.Sprintf("%d change(s) tracked in rollback script", n)),
		sl(sevInfo, "Rollback: "+rollback),
	}, ""}
}

func checkHardening(stateDir string) group {
	rollback := filepath.Join(stateDir, "hardening-rollback.sh")
	if _, err := os.Stat(rollback); err != nil {
		// "make harden", which resolves from the repo root where the f key runs
		// it. The fix used to be "Run: hardening.sh", which resolves nowhere.
		return group{"Security Hardening", sevInfo,
			[]statusLine{sl(sevInfo, "Not applied — run: make harden")}, "make harden"}
	}
	n, err := countLines(rollback, `sudo|sysadminctl|defaults write|defaults delete`)
	if err != nil {
		return group{"Security Hardening", sevWarn,
			[]statusLine{sl(sevWarn, "Cannot read the rollback script: "+err.Error())}, ""}
	}
	if n == 0 {
		return group{"Security Hardening", sevInfo,
			[]statusLine{sl(sevInfo, "Rollback script present but empty")}, ""}
	}
	return group{"Security Hardening", sevOK, []statusLine{
		sl(sevOK, "Applied"),
		sl(sevInfo, fmt.Sprintf("%d change(s) tracked in rollback script", n)),
		sl(sevInfo, "Rollback: "+rollback),
	}, ""}
}

// checkBackups reports what setup displaced, not the health of anything, so
// the caller shows it only when there is something to report. setup moves
// whatever is in a dotfile's place into ~/.mimac/backups/<timestamp>/ before
// linking. An empty directory, which setup used to leave on every relink, is
// not a backup. The dashboard once read ~/.mimac/backup, which nothing writes.
func checkBackups(stateDir string) (group, bool) {
	backupDir := filepath.Join(stateDir, "backups")
	entries, err := os.ReadDir(backupDir)
	if err != nil {
		return group{}, false
	}
	var dirs []string
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		inner, err := os.ReadDir(filepath.Join(backupDir, e.Name()))
		if err == nil && len(inner) > 0 {
			dirs = append(dirs, e.Name())
		}
	}
	if len(dirs) == 0 {
		return group{}, false
	}
	sort.Sort(sort.Reverse(sort.StringSlice(dirs)))
	return group{"Backups", sevOK, []statusLine{
		sl(sevOK, fmt.Sprintf("%d backup(s)", len(dirs))),
		sl(sevInfo, "Latest:   "+dirs[0]),
		sl(sevInfo, "Location: "+backupDir),
	}, ""}, true
}

// checkShell compares the login shell with the zsh first on PATH, the one
// setup's shell phase sets. The dashboard used to warn about any shell outside
// Homebrew, /bin/zsh included.
func checkShell() group {
	user := os.Getenv("USER")
	if user == "" {
		return group{"Shell", sevWarn,
			[]statusLine{sl(sevWarn, "USER environment variable is not set")}, ""}
	}
	out, err := exec.Command("dscl", ".", "-read", "/Users/"+user, "UserShell").Output()
	if err != nil {
		return group{"Shell", sevWarn,
			[]statusLine{sl(sevWarn, fmt.Sprintf("dscl failed: %v", err))}, ""}
	}
	current := ""
	if parts := strings.Fields(strings.TrimSpace(string(out))); len(parts) >= 2 {
		current = parts[1]
	}
	zshPath, _ := exec.LookPath("zsh")
	if current != "" && current == zshPath {
		return group{"Shell", sevOK,
			[]statusLine{sl(sevOK, "Login shell: "+current)}, ""}
	}
	lines := []statusLine{
		sl(sevWarn, fmt.Sprintf("Login shell: %s (expected: %s)", current, zshPath)),
	}
	fix := ""
	switch {
	case zshPath == "":
	case shellListed(zshPath):
		fix = "chsh -s " + zshPath
	default:
		// chsh refuses a shell /etc/shells does not list ("non-standard", man
		// chsh), and Homebrew does not register its zsh, so a bare chsh could
		// only fail. Registering it needs sudo: named, not run.
		lines = append(lines,
			sl(sevInfo, zshPath+" is not listed in /etc/shells, so chsh will refuse it"),
			sl(sevInfo, "  first: echo "+zshPath+" | sudo tee -a /etc/shells"))
	}
	return group{"Shell", sevWarn, lines, fix}
}

// shellsFile is the list chsh checks. A variable so the tests can point it at a
// fixture.
var shellsFile = "/etc/shells"

// shellListed reports whether path is a whole line of shellsFile, surrounding
// whitespace aside, so zsh-beta is not taken for zsh. An unreadable file counts
// as unlisted.
func shellListed(path string) bool {
	b, err := os.ReadFile(shellsFile)
	if err != nil {
		return false
	}
	for _, l := range strings.Split(string(b), "\n") {
		if strings.TrimSpace(l) == path {
			return true
		}
	}
	return false
}

// checkPATH reports whether binDir is on this process's PATH. When it is not,
// but ~/.zshrc already adds it, as MiMac's own .zshrc does, the shell this runs
// in has not read .zshrc, and the fix is a new shell: doctor --fix appends the
// line only when .zshrc lacks it, so offering it there would change nothing.
// The test is doctor's own, a grep for $HOME/bin, so the two agree.
func checkPATH(home, binDir string) group {
	for _, p := range filepath.SplitList(os.Getenv("PATH")) {
		if p == binDir {
			return group{"PATH", sevOK,
				[]statusLine{sl(sevOK, binDir+" is on PATH")}, ""}
		}
	}
	if b, err := os.ReadFile(filepath.Join(home, ".zshrc")); err == nil && strings.Contains(string(b), "$HOME/bin") {
		return group{"PATH", sevWarn, []statusLine{
			sl(sevWarn, binDir+" is NOT on PATH in this shell"),
			sl(sevInfo, "~/.zshrc adds it: open a new terminal, or run exec zsh"),
		}, ""}
	}
	return group{"PATH", sevWarn,
		[]statusLine{sl(sevWarn, binDir+" is NOT on PATH")}, "make doctor ARGS=--fix"}
}

func checkHomebrew() group {
	brew := brewBin()
	if brew == "" {
		return group{"Homebrew", sevErr,
			[]statusLine{sl(sevErr, "Not installed — see https://brew.sh")}, ""}
	}
	out, err := exec.Command(brew, "--version").Output()
	if err != nil {
		return group{"Homebrew", sevWarn,
			[]statusLine{sl(sevWarn, "brew --version failed: "+err.Error())}, ""}
	}
	ver := strings.SplitN(strings.TrimSpace(string(out)), "\n", 2)[0]
	return group{"Homebrew", sevOK,
		[]statusLine{sl(sevOK, ver)}, ""}
}

// A Brewfile entry, for brewfileSummary's count. What is installed against it
// is sync --check's answer (daily.go).
var (
	reBrewPkg = regexp.MustCompile(`^brew\s+"([^"]+)"`)
	reCaskPkg = regexp.MustCompile(`^cask\s+"([^"]+)"`)
)

// ── Messages & commands ───────────────────────────────────────────────────

type checksMsg []group
type fixDoneMsg struct{ err error }

func runChecks(repoRoot, home, binDir string) tea.Cmd {
	return func() tea.Msg { return checksMsg(collect(repoRoot, home, binDir)) }
}

// ── Model ─────────────────────────────────────────────────────────────────

type model struct {
	groups       []group
	groupIdx     int
	detailScroll int
	leftFocus    bool
	width        int
	height       int
	loading      bool
	flash        string
	pendingFix   bool
	repoRoot     string
	home         string
	binDir       string
}

func newModel(repoRoot, home, binDir string) model {
	return model{
		repoRoot:  repoRoot,
		home:      home,
		binDir:    binDir,
		loading:   true,
		leftFocus: true,
	}
}

func (m model) Init() tea.Cmd {
	return runChecks(m.repoRoot, m.home, m.binDir)
}

// ── Update ────────────────────────────────────────────────────────────────

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
	case checksMsg:
		m.groups = []group(msg)
		m.loading = false
		m.clampCursor()
	case fixDoneMsg:
		if msg.err != nil {
			m.flash = "fix failed: " + msg.err.Error()
		} else {
			m.flash = "done — refreshing…"
		}
		m.loading = true
		return m, runChecks(m.repoRoot, m.home, m.binDir)
	case tea.KeyMsg:
		return m.handleKey(msg)
	}
	return m, nil
}

func (m model) handleKey(msg tea.KeyMsg) (model, tea.Cmd) {
	key := msg.String()

	if key == "ctrl+c" {
		return m, tea.Quit
	}

	if m.pendingFix {
		switch key {
		case "enter":
			m.pendingFix = false
			m.flash = ""
			if g := m.currentGroup(); g != nil && g.fix != "" {
				shell := os.Getenv("SHELL")
				if shell == "" {
					shell = "/bin/zsh"
				}
				cmd := exec.Command(shell, "-c",
					"cd "+shellQuote(m.repoRoot)+" && "+g.fix)
				return m, tea.ExecProcess(cmd, func(err error) tea.Msg {
					return fixDoneMsg{err: err}
				})
			}
		default:
			m.pendingFix = false
			m.flash = ""
		}
		return m, nil
	}

	if key == "q" || key == "esc" {
		return m, tea.Quit
	}
	if m.loading {
		return m, nil
	}

	m.flash = ""
	switch key {
	case "tab", "shift+tab":
		m.leftFocus = !m.leftFocus
		m.detailScroll = 0
	case "left", "h":
		m.leftFocus = true
		m.detailScroll = 0
	case "right", "l":
		m.leftFocus = false

	case "up", "k":
		if m.leftFocus {
			if m.groupIdx > 0 {
				m.groupIdx--
				m.detailScroll = 0
			}
		} else {
			if m.detailScroll > 0 {
				m.detailScroll--
			}
		}
	case "down", "j":
		if m.leftFocus {
			if m.groupIdx < len(m.groups)-1 {
				m.groupIdx++
				m.detailScroll = 0
			}
		} else {
			m.scrollBy(1)
		}
	case "pgup":
		if !m.leftFocus {
			m.scrollBy(-m.pageStep())
		}
	case "pgdown":
		if !m.leftFocus {
			m.scrollBy(m.pageStep())
		}

	case "r":
		m.loading = true
		return m, runChecks(m.repoRoot, m.home, m.binDir)

	case "f":
		if g := m.currentGroup(); g != nil && g.fix != "" {
			m.pendingFix = true
			m.flash = "Run \"" + g.fix + "\"? [enter] confirm  [esc] cancel"
			return m, nil
		}
		m.flash = "no fix available for this check"
	}
	return m, nil
}

// scrollBy moves the detail pane by n lines, within 0 and the last full page.
func (m *model) scrollBy(n int) {
	g := m.currentGroup()
	if g == nil {
		return
	}
	m.detailScroll = min(max(m.detailScroll+n, 0), max(len(g.lines)-m.detailViewH(), 0))
}

// pageStep is half the detail pane, and at least one line.
func (m model) pageStep() int { return max(m.detailViewH()/2, 1) }

// bodyHeight is the height of the two panes, borders included: the terminal
// less the header and footer lines, and never under 4.
func (m model) bodyHeight() int { return max(m.height-2, 4) }

// detailViewH is the number of visible detail lines in the right pane: the
// body, less its border (2) and the group header (1). It reads bodyHeight,
// which viewBody draws with, so the scroll bound and the drawing agree.
func (m model) detailViewH() int { return m.bodyHeight() - 2 - 1 }

func (m *model) clampCursor() {
	if m.groupIdx >= len(m.groups) {
		m.groupIdx = max(0, len(m.groups)-1)
	}
}

func (m model) currentGroup() *group {
	if m.groupIdx < len(m.groups) {
		return &m.groups[m.groupIdx]
	}
	return nil
}

// ── Styles ────────────────────────────────────────────────────────────────

var (
	stylePaneOff = theme.StylePaneOff
	stylePaneOn  = theme.StylePaneOn
	styleTitle   = theme.StyleTitle
	styleFooter  = theme.StyleFooter

	styleFlash     = lipgloss.NewStyle().Foreground(theme.ColGreen)
	styleFlashWarn = lipgloss.NewStyle().Foreground(theme.ColAmber)
	styleDim       = lipgloss.NewStyle().Foreground(theme.ColDim)
	styleCursor    = lipgloss.NewStyle().Bold(true).Foreground(theme.ColHighlight)
	styleNorm      = lipgloss.NewStyle().Foreground(theme.ColNormal)
	styleLoading   = lipgloss.NewStyle().Foreground(theme.ColSubtle)

	styleOK   = lipgloss.NewStyle().Foreground(theme.ColGreen)
	styleWarn = lipgloss.NewStyle().Foreground(theme.ColAmber)
	styleErr  = lipgloss.NewStyle().Foreground(theme.ColRed)
	styleInfo = lipgloss.NewStyle().Foreground(theme.ColDim)
)

func sevStyle(s severity) lipgloss.Style {
	switch s {
	case sevOK:
		return styleOK
	case sevWarn:
		return styleWarn
	case sevErr:
		return styleErr
	default:
		return styleInfo
	}
}

// ── View ──────────────────────────────────────────────────────────────────

func (m model) View() string {
	if m.width == 0 {
		return "Loading…"
	}
	return lipgloss.JoinVertical(lipgloss.Left,
		m.viewHeader(),
		m.viewBody(),
		m.viewFooter(),
	)
}

func (m model) viewHeader() string {
	left := styleTitle.Render("mimac-status") + styleFooter.Render("  Daily status")
	var right string
	if m.loading {
		right = styleLoading.Render("checking…")
	} else {
		verdict, sev := summary(m.groups)
		right = sevStyle(sev).Render(verdict)
	}
	gap := max(m.width-lipgloss.Width(left)-lipgloss.Width(right), 1)
	return m.clampWidth(left + strings.Repeat(" ", gap) + right)
}

// clampWidth trims a rendered, styled line to the terminal width. lipgloss's
// MaxWidth is ANSI-aware, which a rune-based truncate is not: cutting an escape
// sequence in half corrupts the rest of the frame rather than shortening it.
func (m model) clampWidth(s string) string {
	if m.width <= 0 {
		return s
	}
	return lipgloss.NewStyle().MaxWidth(m.width).Render(s)
}

func (m model) viewFooter() string {
	hints := styleFooter.Render("[↑↓/jk] navigate  [tab] switch pane  [f]ix  [r]efresh  [q]uit")
	version := styleFooter.Render(fmt.Sprintf("  %s (%s)", Version, GitSHA))
	if m.flash == "" {
		return m.clampWidth(hints + version)
	}
	var flashStr string
	if m.pendingFix || strings.Contains(m.flash, "fail") || strings.Contains(m.flash, "no fix") {
		flashStr = "  " + styleFlashWarn.Render(m.flash)
	} else {
		flashStr = "  " + styleFlash.Render(m.flash)
	}
	return m.clampWidth(hints + flashStr)
}

func (m model) viewBody() string {
	paneH := m.bodyHeight() - 2 // subtract border top+bottom

	if m.loading && len(m.groups) == 0 {
		inner := m.width - 4
		return stylePaneOn.Width(inner).Height(paneH).
			Render(styleLoading.Render("Running the checks…"))
	}

	const leftInner = 26
	rightInner := max(m.width-leftInner-4, 10)

	return lipgloss.JoinHorizontal(lipgloss.Top,
		m.viewLeft(leftInner, paneH),
		m.viewRight(rightInner, paneH),
	)
}

func (m model) viewLeft(inner, height int) string {
	var sb strings.Builder
	for i, g := range m.groups {
		icon := sevStyle(g.sev).Render(g.sev.icon())
		nameW := inner - 5 // "▸ " or "  " (2) + icon(1) + " " (1) + padding(1)
		name := theme.Truncate(g.name, nameW)
		pad := strings.Repeat(" ", max(0, nameW-lipgloss.Width(name)))

		var line string
		if i == m.groupIdx {
			if m.leftFocus {
				line = styleCursor.Render("▸ ") + icon + " " + styleCursor.Render(name) + pad
			} else {
				line = styleNorm.Render("▸ ") + icon + " " + styleNorm.Render(name) + pad
			}
		} else {
			line = "  " + icon + " " + styleNorm.Render(name) + pad
		}
		sb.WriteString(line + "\n")
	}

	content := strings.TrimRight(sb.String(), "\n")
	pane := stylePaneOff
	if m.leftFocus {
		pane = stylePaneOn
	}
	return pane.Width(inner).Height(height).Render(content)
}

func (m model) viewRight(inner, height int) string {
	pane := stylePaneOff
	if !m.leftFocus {
		pane = stylePaneOn
	}

	g := m.currentGroup()
	if g == nil {
		return pane.Width(inner).Height(height).Render(styleDim.Render("no data"))
	}

	vh := height - 1 // lines available below the header
	start := m.detailScroll
	end := min(start+vh, len(g.lines))

	// Header: group name, fix hint, and, when the lines overflow, "start–end /
	// total" at the right.
	header := styleTitle.Render(g.name)
	if g.fix != "" {
		header += styleDim.Render("  [f] " + g.fix)
	}
	if len(g.lines) > vh {
		scrollInfo := styleDim.Render(fmt.Sprintf("  %d–%d / %d", start+1, end, len(g.lines)))
		header += strings.Repeat(" ", max(0, inner-lipgloss.Width(header)-lipgloss.Width(scrollInfo))) + scrollInfo
	}

	var sb strings.Builder
	sb.WriteString(header + "\n")
	for _, l := range g.lines[start:end] {
		icon := sevStyle(l.sev).Render(l.sev.icon())
		text, fix := l.text, ""
		if l.fix != "" {
			fix = "  → " + l.fix
		}
		// The fix is cut before the text is: it is the line's suggestion, and
		// the text is what is wrong.
		room := max(inner-3, 1)
		if lipgloss.Width(text)+lipgloss.Width(fix) > room {
			fix = ""
		}
		sb.WriteString(icon + " " + styleNorm.Render(theme.Truncate(text, room)) + styleDim.Render(fix) + "\n")
	}
	content := strings.TrimRight(sb.String(), "\n")
	return pane.Width(inner).Height(height).Render(content)
}

// ── Helpers ───────────────────────────────────────────────────────────────

func shellQuote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", "'\\''") + "'"
}

// ── Main ──────────────────────────────────────────────────────────────────

func usage(w io.Writer) {
	fmt.Fprint(w, `mimac-status — the daily dashboard

Usage:
  mimac-status          Open the TUI dashboard
  mimac-status --plain  Print the same panels as text, and exit
  mimac-status --help   Show this help

Panels, daily work first:
  Unrecorded            What the next Mac would not get: Homebrew packages
                        the Brewfile lacks or no longer has, work in ~/MiMac
                        not committed or pushed, the app-preferences snapshot
  Upkeep                ~/MiMac behind origin, Go tools older than their source,
                        outdated Homebrew packages, macOS updates
  Time Machine Backups  A destination, and the age of the last backup
  Installation          Dotfiles, ~/bin links, shell, PATH, Homebrew, the
                        Brewfile, macOS defaults, hardening

A line's fix is shown beside it; f runs the panel's first one, after asking.
MIMAC_ROOT names a checkout other than ~/MiMac.

TUI keys:
  ↑/↓  k/j           Navigate panels (left) or scroll detail (right)
  ←/→  h/l           Switch panes
  tab / shift+tab     Switch panes
  pgup / pgdown       Scroll the detail pane by half a page
  f                   Run the fix for the selected panel
  r                   Refresh every panel
  q / esc             Quit
`)
}

// options is what the command line asked for.
type options struct {
	help, plain bool
}

// parseArgs decides what to do with the command line. bad is the argument to
// refuse. Extracted from main so the decision is testable without os.Exit.
func parseArgs(args []string) (opts options, bad string) {
	if len(args) == 0 {
		return options{}, ""
	}
	if len(args) > 1 {
		return options{}, args[1]
	}
	switch args[0] {
	case "--help", "-h":
		return options{help: true}, ""
	case "--plain":
		return options{plain: true}, ""
	default:
		return options{}, args[0]
	}
}

func main() {
	opts, bad := parseArgs(os.Args[1:])
	switch {
	case bad != "":
		usage(os.Stderr)
		fmt.Fprintf(os.Stderr, "\nunknown argument: %s\n", bad)
		os.Exit(2)
	case opts.help:
		usage(os.Stdout)
		os.Exit(0)
	}

	home, err := os.UserHomeDir()
	if err != nil {
		fmt.Fprintf(os.Stderr, "mimac-status: cannot determine home directory: %v\n", err)
		os.Exit(1)
	}

	repoRoot := filepath.Join(home, "MiMac")
	if r := os.Getenv("MIMAC_ROOT"); r != "" {
		repoRoot = r
	}
	binDir := filepath.Join(home, "bin")

	if opts.plain {
		renderPlain(os.Stdout, collect(repoRoot, home, binDir))
		return
	}

	tty, err := os.OpenFile("/dev/tty", os.O_RDWR, 0)
	if err != nil {
		fmt.Fprintf(os.Stderr, "mimac-status: cannot open terminal: %v\n", err)
		os.Exit(1)
	}
	defer tty.Close()

	p := tea.NewProgram(
		newModel(repoRoot, home, binDir),
		tea.WithAltScreen(),
		tea.WithInput(tty),
		tea.WithOutput(tty),
	)
	if _, err := p.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "mimac-status: %v\n", err)
		os.Exit(1)
	}
}
