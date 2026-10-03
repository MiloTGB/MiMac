package main

import (
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// The ignore mark is sync's way of saying "never offer this again": i marks a
// package for ~/.mimac/sync-ignore, the picker prints it as an ignore- line,
// and quitting with q keeps the marks. brew-packages has no ignore list, so
// it hides the key, and q there stays a cancel. Ported from mrk-picker.

func pickerModel(noIgnore bool) model {
	m := newModel([]category{{name: "New", pkgs: []*pkg{
		{name: "jq", kind: formula},
		{name: "ripgrep", kind: formula},
		{name: "zoom", kind: cask},
		{name: "git", kind: formula, installed: true},
	}}})
	m.leftFocus = false // the package pane, where the keys act
	m.noIgnore = noIgnore
	m.width, m.height = 100, 30
	return m
}

func press(m model, keys ...string) model {
	for _, k := range keys {
		var msg tea.KeyMsg
		switch k {
		case "ctrl+c":
			msg = tea.KeyMsg{Type: tea.KeyCtrlC}
		case "enter":
			msg = tea.KeyMsg{Type: tea.KeyEnter}
		case "up":
			msg = tea.KeyMsg{Type: tea.KeyUp}
		case " ":
			msg = tea.KeyMsg{Type: tea.KeySpace, Runes: []rune(" ")}
		default:
			msg = tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune(k)}
		}
		tm, _ := m.Update(msg)
		m = tm.(model)
	}
	return m
}

func pkgs(m model) []*pkg { return m.cats[0].pkgs }

func TestIgnoreMarksAndSelectionAreExclusive(t *testing.T) {
	m := press(pickerModel(false), "i") // jq ignored, cursor to ripgrep
	if p := pkgs(m)[0]; !p.ignored || p.selected || m.pkgIdx != 1 {
		t.Fatalf("i should mark jq ignored and move on: ignored=%v selected=%v cursor=%d", p.ignored, p.selected, m.pkgIdx)
	}
	m = press(m, "up", " ") // back to jq, then add it
	if p := pkgs(m)[0]; p.ignored || !p.selected {
		t.Errorf("space on an ignored package should add it and clear the mark: ignored=%v selected=%v", p.ignored, p.selected)
	}
	m = press(m, "up", "i") // and ignore it again
	if p := pkgs(m)[0]; !p.ignored || p.selected {
		t.Errorf("i on a selected package should mark it ignored and drop the selection: ignored=%v selected=%v", p.ignored, p.selected)
	}
	m = press(m, "a")
	for _, p := range pkgs(m)[:3] {
		if !p.selected || p.ignored {
			t.Errorf("a should add every package and clear its mark: %s ignored=%v selected=%v", p.name, p.ignored, p.selected)
		}
	}
}

func TestAnInstalledPackageCannotBeIgnored(t *testing.T) {
	m := pickerModel(false)
	m.pkgIdx = 3 // git, installed
	if p := pkgs(press(m, "i"))[3]; p.ignored {
		t.Error("an installed package was marked ignored")
	}
}

func TestNoIgnoreHidesTheKey(t *testing.T) {
	m := press(pickerModel(true), "i")
	if p := pkgs(m)[0]; p.ignored || m.pkgIdx != 0 {
		t.Errorf("with --no-ignore, i should do nothing: ignored=%v cursor=%d", p.ignored, m.pkgIdx)
	}
	if f := m.viewFooter(); strings.Contains(f, "ignore") {
		t.Errorf("with --no-ignore, the footer should not offer the key: %q", f)
	}
}

func TestEmitLinesAndExitStatus(t *testing.T) {
	marked := func(noIgnore bool) model { return press(pickerModel(noIgnore), "i", " ") } // ignore jq, add ripgrep

	m := press(marked(false), "enter")
	if got := strings.Join(emitLines(m.cats, m.cancelled), ","); got != "ignore-formula:jq,formula:ripgrep" || exitStatus(m) != 0 {
		t.Errorf("enter: lines %q, status %d; want the ignore and the addition, status 0", got, exitStatus(m))
	}

	m = press(marked(false), "q")
	if got := strings.Join(emitLines(m.cats, m.cancelled), ","); got != "ignore-formula:jq" || exitStatus(m) != 0 {
		t.Errorf("q: lines %q, status %d; want the ignore kept, the addition dropped, status 0", got, exitStatus(m))
	}

	m = press(marked(false), "ctrl+c")
	if exitStatus(m) != 1 {
		t.Errorf("ctrl+c: status %d; want 1, which drops everything", exitStatus(m))
	}

	// brew-packages: q is a cancel, as it always was.
	m = press(press(pickerModel(true), " "), "q")
	if exitStatus(m) != 1 {
		t.Errorf("q with --no-ignore: status %d; want 1, a cancel", exitStatus(m))
	}
	m = press(press(pickerModel(true), " "), "enter")
	if got := strings.Join(emitLines(m.cats, m.cancelled), ","); got != "formula:jq" || exitStatus(m) != 0 {
		t.Errorf("enter with --no-ignore: lines %q, status %d", got, exitStatus(m))
	}
}

func TestHeaderCountsIgnoresAndFooterFits(t *testing.T) {
	m := press(pickerModel(false), "i", " ")
	if h := m.viewHeader(); !strings.Contains(h, "1 selected · 1 ignored") {
		t.Errorf("header should count both: %q", h)
	}
	for _, w := range []int{20, 40, 80, 120} {
		m.width = w
		if fw := lipgloss.Width(m.viewFooter()); fw > w {
			t.Errorf("footer is %d columns at width %d", fw, w)
		}
	}
}
