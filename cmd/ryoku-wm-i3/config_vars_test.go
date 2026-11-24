package main

import "testing"

func TestParseI3BindRowsPrefixVariables(t *testing.T) {
	config := "set $mod Mod4\nset $mod2 Mod1\nbindsym $mod2+x exec foo\nbindsym $mod+y exec bar\n"
	for i := 0; i < 50; i++ { // map iteration order is random; repeat
		rows, err := parseI3BindRows(config)
		if err != nil {
			t.Fatal(err)
		}
		if len(rows) != 2 {
			t.Fatalf("want 2 rows, got %d", len(rows))
		}
		if got := rows[0].Chord; got != "ALT + X" {
			t.Fatalf("$mod2 chord = %q, want ALT + X", got)
		}
		if got := rows[1].Chord; got != "SUPER + Y" {
			t.Fatalf("$mod chord = %q, want SUPER + Y", got)
		}
	}
}
