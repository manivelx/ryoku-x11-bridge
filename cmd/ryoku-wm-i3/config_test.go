package main

import (
	"reflect"
	"testing"
)

func TestParseI3BindRowsUsesDeclaredBindingsAndModAliases(t *testing.T) {
	config := `# a comment
set $mod Mod4
bindsym $mod+Return exec --no-startup-id terminal
bindsym --release $mod+Shift+space exec launcher
bindcode 123 exec special
exec startup-command
`
	rows, err := parseI3BindRows(config)
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 3 {
		t.Fatalf("got %d rows, want 3: %#v", len(rows), rows)
	}
	if got, want := rows[0].Keys, []string{"SUPER", "ENTER"}; !reflect.DeepEqual(got, want) {
		t.Fatalf("first chord = %#v, want %#v", got, want)
	}
	if rows[0].Kind != "custom" || rows[0].Default != "" || rows[0].Rebindable {
		t.Fatalf("custom row was presented as a shipped/rebindable bind: %#v", rows[0])
	}
	if got, want := rows[1].Keys, []string{"SUPER", "SHIFT", "SPACE"}; !reflect.DeepEqual(got, want) {
		t.Fatalf("second chord = %#v, want %#v", got, want)
	}
	if rows[2].Chord != "123" {
		t.Fatalf("bindcode chord = %q, want 123", rows[2].Chord)
	}
}

func TestParseI3BindRowsRejectsEmptyConfig(t *testing.T) {
	if _, err := parseI3BindRows("  \n# no binds\n"); err == nil {
		t.Fatal("expected empty config error")
	}
}

func TestDisplayI3ChordRejectsEmptyTokens(t *testing.T) {
	if got := displayI3Chord("Mod4++q"); got != nil {
		t.Fatalf("malformed chord returned %#v", got)
	}
}
