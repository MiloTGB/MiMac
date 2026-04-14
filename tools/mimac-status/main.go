// mimac-status — interactive installation health dashboard
// Two-pane Bubble Tea TUI: checks (left) | detail (right)
package main

import (
	"bufio"
	"fmt"
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

// ── Severity levels ──────────────────────────────────────────────────────────

type severity int

const (
	sevOK severity = iota
	sevWarn
	sevFail
)

func (s severity) String() string {
	switch s {
	case sevOK:
		return "OK"
	case sevWarn:
		return "WARN"
	case sevFail:
		return "FAIL"
	}
	return "?"
}

// ── Check result ─────────────────────────────────────────────────────────────

type checkResult struct {
	name    string
	sev     severity
	summary string
	detail  string
	fix     string
}

// ── Check functions ──────────────────────────────────────────────────────────

func checkDotfiles(repoRoot string) checkResult {
	name := "Dotfiles"
	dotDir := filepath.Join(repoRoot, "dots")

	info, err := os.Stat(dotDir)
	if err != nil || !info.IsDir() {
		return checkResult{
			name:    name,
			sev:     sevFail,
			summary: "dots/ directory missing",
			detail:  fmt.Sprintf("Expected directory: %s", dotDir),
			fix:     "Run: make setup",
		}
	}

	// Check for a few expected dotfiles
	expected := []string{".bashrc", ".zshrc", ".nanorc"}
	var missing []string
	for _, f := range expected {
		p := filepath.Join(dotDir, f)
		if _, err := os.Stat(p); err != nil {
			missing = append(missing, f)
		}
	}

	if len(missing) > 0 {
		return checkResult{
			name:    name,
			sev:     sevWarn,
			summary: fmt.Sprintf("%d expected dotfile(s) missing", len(missing)),
			detail:  "Missing: " + strings.Join(missing, ", "),
			fix:     "Check dots/ directory contents",
		}
	}

	return checkResult{
		name:    name,
		sev:     sevOK,
		summary: "Dotfiles present",
		detail:  fmt.Sprintf("Found %d expected files in %s", len(expected), dotDir),
	}
}

func checkTools(repoRoot string) checkResult {
	name := "Tools"
	toolsDir := filepath.Join(repoRoot, "tools")

	info, err := os.Stat(toolsDir)
	if err != nil || !info.IsDir() {
		return checkResult{
			name:    name,
			sev:     sevFail,
			summary: "tools/ directory missing",
			detail:  fmt.Sprintf("Expected directory: %s", toolsDir),
			fix:     "Run: make setup",
		}
	}

	entries, err := os.ReadDir(toolsDir)
	if err != nil {
		return checkResult{
			name:    name,
			sev:     sevFail,
			summary: "Cannot read tools/",
			detail:  err.Error(),
			fix:     "Check filesystem permissions",
		}
	}

	var dirs []string
	for _, e := range entries {
		if e.IsDir() {
			dirs = append(dirs, e.Name())
		}
	}

	if len(dirs) == 0 {
		return checkResult{
			name:    name,
			sev:     sevWarn,
			summary: "No tool subdirectories",
			detail:  "tools/ exists but contains no subdirectories",
			fix:     "Run: make setup",
		}
	}

	return checkResult{
		name:    name,
		sev:     sevOK,
		summary: fmt.Sprintf("%d tool(s) found", len(dirs)),
		detail:  "Tools: " + strings.Join(dirs, ", "),
	}
}

func checkDefaults(stateDir string) checkResult {
	name := "Defaults"
	stampsDir := filepath.Join(stateDir, "stamps")

	info, err := os.Stat(stampsDir)
	if err != nil || !info.IsDir() {
		return checkResult{
			name:    name,
			sev:     sevWarn,
			summary: "No stamps directory",
			detail:  fmt.Sprintf("Expected: %s", stampsDir),
			fix:     "Run: make defaults",
		}
	}

	entries, err := os.ReadDir(stampsDir)
	if err != nil {
		return checkResult{
			name:    name,
			sev:     sevFail,
			summary: "Cannot read stamps/",
			detail:  err.Error(),
		}
	}

	var stamps []string
	for _, e := range entries {
		if !e.IsDir() {
			stamps = append(stamps, e.Name())
		}
	}

	if len(stamps) == 0 {
		return checkResult{
			name:    name,
			sev:     sevWarn,
			summary: "No stamps found",
			detail:  "defaults have not been applied yet",
			fix:     "Run: make defaults",
		}
	}

	return checkResult{
		name:    name,
		sev:     sevOK,
		summary: fmt.Sprintf("%d stamp(s)", len(stamps)),
		detail:  "Stamps: " + strings.Join(stamps, ", "),
	}
}

func checkHardening(stateDir string) checkResult {
	name := "Hardening"
	stamp := filepath.Join(stateDir, "stamps", "hardening")

	if _, err := os.Stat(stamp); err != nil {
		return checkResult{
			name:    name,
			sev:     sevWarn,
			summary: "Hardening not applied",
			detail:  "No hardening stamp found at " + stamp,
			fix:     "Run: hardening.sh",
		}
	}

	return checkResult{
		name:    name,
		sev:     sevOK,
		summary: "Hardening applied",
		detail:  "Stamp present at " + stamp,
	}
}

func checkBackups(stateDir string) checkResult {
	name := "Backups"
	backupDir := filepath.Join(stateDir, "backup")

	info, err := os.Stat(backupDir)
	if err != nil || !info.IsDir() {
		return checkResult{
			name:    name,
			sev:     sevWarn,
			summary: "No backup directory",
			detail:  fmt.Sprintf("Expected: %s", backupDir),
			fix:     "Backups are created automatically during setup",
		}
	}

	entries, err := os.ReadDir(backupDir)
	if err != nil {
		return checkResult{
			name:    name,
			sev:     sevFail,
			summary: "Cannot read backup/",
			detail:  err.Error(),
		}
	}

	if len(entries) == 0 {
		return checkResult{
			name:    name,
			sev:     sevOK,
			summary: "Backup dir exists (empty)",
			detail:  "No backed-up files (clean install)",
		}
	}

	var files []string
	for _, e := range entries {
		files = append(files, e.Name())
	}
	sort.Strings(files)

	return checkResult{
		name:    name,
		sev:     sevOK,
		summary: fmt.Sprintf("%d backup(s)", len(files)),
		detail:  "Files: " + strings.Join(files, ", "),
	}
}

func checkShell() checkResult {
	name := "Shell"
	shell := os.Getenv("SHELL")

	if shell == "" {
		return checkResult{
			name:    name,
			sev:     sevWarn,
			summary: "$SHELL not set",
			detail:  "Cannot determine current shell",
			fix:     "Set SHELL environment variable",
		}
	}

	// Check if it's a Homebrew-installed shell
	if strings.HasPrefix(shell, "/opt/homebrew") || strings.HasPrefix(shell, "/usr/local") {
		return checkResult{
			name:    name,
			sev:     sevOK,
			summary: filepath.Base(shell) + " (Homebrew)",
			detail:  "Shell: " + shell,
		}
	}

	return checkResult{
		name:    name,
		sev:     sevWarn,
		summary: filepath.Base(shell) + " (system)",
		detail:  "Shell: " + shell + "\nConsider using Homebrew-installed shell",
		fix:     "Run: make setup to install and configure shell",
	}
}

func checkPATH() checkResult {
	name := "PATH"
	pathVar := os.Getenv("PATH")
	dirs := filepath.SplitList(pathVar)

	// Check for Homebrew in PATH
	hasHomebrew := false
	for _, d := range dirs {
		if strings.Contains(d, "homebrew") || strings.Contains(d, "/usr/local/bin") {
			hasHomebrew = true
			break
		}
	}

	if !hasHomebrew {
		return checkResult{
			name:    name,
			sev:     sevWarn,
			summary: "Homebrew not in PATH",
			detail:  "PATH does not include Homebrew directories",
			fix:     "Add Homebrew to your shell profile",
		}
	}

	// Show first few PATH entries
	show := dirs
	if len(show) > 5 {
		show = show[:5]
	}

	return checkResult{
		name:    name,
		sev:     sevOK,
		summary: fmt.Sprintf("%d directories", len(dirs)),
		detail:  "First entries:\n  " + strings.Join(show, "\n  "),
	}
}

func checkHomebrew() checkResult {
	name := "Homebrew"

	brewPath, err := exec.LookPath("brew")
	if err != nil {
		return checkResult{
			name:    name,
			sev:     sevFail,
			summary: "Homebrew not installed",
			detail:  "brew command not found in PATH",
			fix:     "Install from https://brew.sh",
		}
	}

	out, err := exec.Command(brewPath, "--version").Output()
	if err != nil {
		return checkResult{
			name:    name,
			sev:     sevWarn,
			summary: "Cannot get version",
			detail:  "brew found at " + brewPath + " but --version failed",
		}
	}

	version := strings.TrimSpace(strings.Split(string(out), "\n")[0])

	return checkResult{
		name:    name,
		sev:     sevOK,
		summary: version,
		detail:  "Path: " + brewPath,
	}
}

func checkBrewfile(repoRoot string) checkResult {
	name := "Brewfile"
	bfPath := filepath.Join(repoRoot, "Brewfile")

	f, err := os.Open(bfPath)
	if err != nil {
		return checkResult{
			name:    name,
			sev:     sevFail,
			summary: "Brewfile missing",
			detail:  fmt.Sprintf("Expected: %s", bfPath),
			fix:     "Run: make setup",
		}
	}
	defer f.Close()

	formulaRe := regexp.MustCompile(`^brew "([^"]+)"`)
	caskRe := regexp.MustCompile(`^cask "([^"]+)"`)

	var formulae, casks int
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := scanner.Text()
		if formulaRe.MatchString(line) {
			formulae++
		} else if caskRe.MatchString(line) {
			casks++
		}
	}

	total := formulae + casks
	if total == 0 {
		return checkResult{
			name:    name,
			sev:     sevWarn,
			summary: "Brewfile empty",
			detail:  "No formulae or casks found",
			fix:     "Run: make brew to populate Brewfile",
		}
	}

	return checkResult{
		name:    name,
		sev:     sevOK,
		summary: fmt.Sprintf("%d formulae, %d casks", formulae, casks),
		detail:  fmt.Sprintf("Total packages: %d\nPath: %s", total, bfPath),
	}
}

// ── Run all checks ───────────────────────────────────────────────────────────

func runChecks() []checkResult {
	home, _ := os.UserHomeDir()
	stateDir := filepath.Join(home, ".mimac")
	repoRoot := filepath.Join(home, "MiMac")

	return []checkResult{
		checkHomebrew(),
		checkBrewfile(repoRoot),
		checkDotfiles(repoRoot),
		checkTools(repoRoot),
		checkDefaults(stateDir),
		checkHardening(stateDir),
		checkBackups(stateDir),
		checkShell(),
		checkPATH(),
	}
}

// ── Model ────────────────────────────────────────────────────────────────────

type model struct {
	checks  []checkResult
	cursor  int
	width   int
	height  int
}

func newModel(checks []checkResult) model {
	return model{checks: checks}
}

func (m model) Init() tea.Cmd { return nil }

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height

	case tea.KeyMsg:
		switch msg.String() {
		case "q", "ctrl+c", "esc":
			return m, tea.Quit
		case "up", "k":
			if m.cursor > 0 {
				m.cursor--
			}
		case "down", "j":
			if m.cursor < len(m.checks)-1 {
				m.cursor++
			}
		case "r":
			m.checks = runChecks()
			if m.cursor >= len(m.checks) {
				m.cursor = len(m.checks) - 1
			}
		}
	}
	return m, nil
}

// ── Styles ───────────────────────────────────────────────────────────────────

var (
	styleCheckOK   = lipgloss.NewStyle().Foreground(theme.ColGreen)
	styleCheckWarn = lipgloss.NewStyle().Foreground(theme.ColAmber)
	styleCheckFail = lipgloss.NewStyle().Foreground(theme.ColRed)
	styleCheckName = lipgloss.NewStyle().Foreground(theme.ColNormal)
	styleCursor    = lipgloss.NewStyle().Bold(true).Foreground(theme.ColHighlight)
	styleDetail    = lipgloss.NewStyle().Foreground(theme.ColNormal)
	styleFix       = lipgloss.NewStyle().Foreground(theme.ColAmber)
	styleCount     = lipgloss.NewStyle().Bold(true).Foreground(theme.ColAccent)
)

// ── View ─────────────────────────────────────────────────────────────────────

func (m model) View() string {
	if m.width == 0 {
		return "Initializing…"
	}

	const leftInner = 36
	rightInner := m.width - leftInner - 4
	if rightInner < 20 {
		rightInner = 20
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
	title := theme.StyleTitle.Render("mimac-status")
	sub := styleCount.Render("Installation Health")
	gap := m.width - lipgloss.Width(title) - lipgloss.Width(sub)
	if gap < 1 {
		gap = 1
	}
	return title + strings.Repeat(" ", gap) + sub
}

func (m model) viewFooter() string {
	return theme.StyleFooter.Render("↑↓/jk move · r refresh · q quit")
}

func (m model) viewLeft(inner, height int) string {
	var sb strings.Builder
	lines := 0

	start := 0
	if m.cursor >= height {
		start = m.cursor - height + 1
	}

	for i, c := range m.checks {
		if i < start {
			continue
		}
		if lines >= height {
			break
		}

		var icon string
		switch c.sev {
		case sevOK:
			icon = styleCheckOK.Render("✓")
		case sevWarn:
			icon = styleCheckWarn.Render("!")
		case sevFail:
			icon = styleCheckFail.Render("✗")
		}

		nameW := 14
		name := c.name
		if len(name) > nameW {
			name = name[:nameW-1] + "…"
		}
		pad := nameW - len(name)
		if pad < 0 {
			pad = 0
		}

		sumW := inner - nameW - 6
		if sumW < 0 {
			sumW = 0
		}
		summary := c.summary
		if len(summary) > sumW {
			summary = summary[:sumW-1] + "…"
		}

		isCursor := i == m.cursor

		var line string
		if isCursor {
			line = styleCursor.Render("▸ ") + icon + " " +
				styleCursor.Render(name) + strings.Repeat(" ", pad+1) +
				styleCheckName.Render(summary)
		} else {
			line = "  " + icon + " " +
				styleCheckName.Render(name) + strings.Repeat(" ", pad+1) +
				lipgloss.NewStyle().Foreground(theme.ColSubtle).Render(summary)
		}

		sb.WriteString(line + "\n")
		lines++
	}

	content := strings.TrimRight(sb.String(), "\n")
	return theme.StylePaneOn.Width(inner).Height(height).Render(content)
}

func (m model) viewRight(inner, height int) string {
	if m.cursor >= len(m.checks) {
		return theme.StylePaneOff.Width(inner).Height(height).Render("")
	}

	c := m.checks[m.cursor]

	var sb strings.Builder

	// Title
	var sevStyle lipgloss.Style
	switch c.sev {
	case sevOK:
		sevStyle = styleCheckOK
	case sevWarn:
		sevStyle = styleCheckWarn
	case sevFail:
		sevStyle = styleCheckFail
	}

	sb.WriteString(theme.StyleTitle.Render(c.name) + "  " + sevStyle.Render("["+c.sev.String()+"]") + "\n")
	sb.WriteString("\n")

	// Summary
	sb.WriteString(styleDetail.Render(c.summary) + "\n")
	sb.WriteString("\n")

	// Detail
	if c.detail != "" {
		for _, line := range strings.Split(c.detail, "\n") {
			sb.WriteString(lipgloss.NewStyle().Foreground(theme.ColSubtle).Render(line) + "\n")
		}
		sb.WriteString("\n")
	}

	// Fix suggestion
	if c.fix != "" {
		sb.WriteString(styleFix.Render("Fix: "+c.fix) + "\n")
	}

	content := strings.TrimRight(sb.String(), "\n")
	return theme.StylePaneOff.Width(inner).Height(height).Render(content)
}

// ── Usage ────────────────────────────────────────────────────────────────────

func usage() {
	fmt.Fprintf(os.Stderr, `mimac-status — interactive installation health dashboard

Usage:
  mimac-status          Launch the TUI dashboard
  mimac-status --help   Show this help

The dashboard checks:
  • Homebrew installation and version
  • Brewfile presence and contents
  • Dotfiles in dots/
  • Tools directory
  • macOS defaults (stamps)
  • Security hardening
  • Backups
  • Shell configuration
  • PATH configuration

Keys:
  ↑↓ / j k    Navigate checks
  r            Refresh all checks
  q / Esc      Quit
`)
}

// ── Main ─────────────────────────────────────────────────────────────────────

func main() {
	if len(os.Args) > 1 {
		arg := os.Args[1]
		if arg == "-h" || arg == "--help" || arg == "help" {
			usage()
			os.Exit(0)
		}
		fmt.Fprintf(os.Stderr, "mimac-status: unknown argument: %s\n", arg)
		usage()
		os.Exit(1)
	}

	home, err := os.UserHomeDir()
	if err != nil {
		fmt.Fprintf(os.Stderr, "mimac-status: cannot determine home directory: %v\n", err)
		os.Exit(1)
	}

	repoRoot := filepath.Join(home, "MiMac")
	if _, err := os.Stat(repoRoot); err != nil {
		fmt.Fprintf(os.Stderr, "mimac-status: repo not found at %s: %v\n", repoRoot, err)
		os.Exit(1)
	}

	checks := runChecks()

	p := tea.NewProgram(newModel(checks), tea.WithAltScreen())
	if _, err := p.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "mimac-status: %v\n", err)
		os.Exit(1)
	}
}
