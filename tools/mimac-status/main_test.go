package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// The Backups check read ~/.mimac/backup, which nothing writes, so it warned
// "No backup directory" on every Mac. It reads ~/.mimac/backups now, counts
// only directories that hold something, and is left out when there are none.
func TestCheckBackups(t *testing.T) {
	state := t.TempDir()

	if _, ok := checkBackups(state); ok {
		t.Fatal("no backups directory: the check should be left out")
	}

	// The directory setup never wrote, with something in it: still nothing.
	if err := os.MkdirAll(filepath.Join(state, "backup", "20260101-000000"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(state, "backup", "20260101-000000", ".zshrc"), nil, 0o644); err != nil {
		t.Fatal(err)
	}
	if _, ok := checkBackups(state); ok {
		t.Fatal("~/.mimac/backup is not where setup writes; it should not count")
	}

	// An empty run directory, as setup used to leave on every relink.
	backups := filepath.Join(state, "backups")
	if err := os.MkdirAll(filepath.Join(backups, "20260925-202135"), 0o755); err != nil {
		t.Fatal(err)
	}
	if _, ok := checkBackups(state); ok {
		t.Fatal("an empty backup directory is not a backup")
	}

	// Two real backups: counted, newest first.
	for _, d := range []string{"20260926-090000", "20261003-120000"} {
		if err := os.MkdirAll(filepath.Join(backups, d), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(backups, d, ".aliases"), nil, 0o644); err != nil {
			t.Fatal(err)
		}
	}
	c, ok := checkBackups(state)
	if !ok {
		t.Fatal("two backups: the check should be shown")
	}
	if c.sev != sevOK || c.summary != "2 backup(s)" {
		t.Errorf("got %v %q, want OK \"2 backup(s)\"", c.sev, c.summary)
	}
	if !strings.Contains(c.detail, "Latest:   20261003-120000") {
		t.Errorf("detail should name the newest backup: %q", c.detail)
	}
}
