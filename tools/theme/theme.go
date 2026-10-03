// Package theme provides shared lipgloss colors and styles for MiMac TUI tools.
package theme

import "github.com/charmbracelet/lipgloss"

// ── Shared palette ───────────────────────────────────────────────────────────

var (
	ColSubtle    = lipgloss.AdaptiveColor{Light: "#888888", Dark: "#555555"}
	ColDim       = lipgloss.AdaptiveColor{Light: "#aaaaaa", Dark: "#444444"}
	ColNormal    = lipgloss.AdaptiveColor{Light: "#222222", Dark: "#cccccc"}
	ColHighlight = lipgloss.AdaptiveColor{Light: "#d7005f", Dark: "#ff87af"}
	ColAccent    = lipgloss.AdaptiveColor{Light: "#005fd7", Dark: "#87d7ff"}
	ColGreen     = lipgloss.AdaptiveColor{Light: "#00875f", Dark: "#5fd7a7"}
	ColAmber     = lipgloss.AdaptiveColor{Light: "#875f00", Dark: "#ffd787"}
	ColRed       = lipgloss.AdaptiveColor{Light: "#af0000", Dark: "#ff8787"}
)

// ── Shared utilities ─────────────────────────────────────────────────────────

// Truncate clips s to at most n runes, appending "…" when clipped. It never
// returns something wider than n: zero columns or fewer is an empty string, so
// a caller whose width arithmetic goes negative gets nothing, not an overflow.
func Truncate(s string, n int) string {
	runes := []rune(s)
	if len(runes) <= n {
		return s
	}
	if n <= 0 {
		return ""
	}
	if n == 1 {
		return "…"
	}
	return string(runes[:n-1]) + "…"
}

// ── Shared styles ────────────────────────────────────────────────────────────

var (
	StylePaneOff = lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(ColSubtle)
	StylePaneOn = lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(ColAccent)

	StyleTitle  = lipgloss.NewStyle().Bold(true).Foreground(ColNormal)
	StyleFooter = lipgloss.NewStyle().Foreground(ColSubtle)
)
