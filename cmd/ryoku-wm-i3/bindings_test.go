package main

import (
	"strings"
	"testing"
)

func TestI3ChordTranslatesRyokuModifiersAndMouseButtons(t *testing.T) {
	cases := map[string]string{
		"SUPER + SHIFT + Q": "Mod4+Shift+Q",
		"ALT + CTRL + Return": "Mod1+Control+Return",
		"SUPER + mouse:272": "Mod4+button1",
		"SUPER + mouse:273": "Mod4+button3",
		"SUPER + mouse_up": "Mod4+button4",
		"SUPER + mouse_down": "Mod4+button5",
		"SUPER + KP_0": "Mod4+KP_0",
	}
	for input, want := range cases {
		got, ok := i3Chord(input)
		if !ok || got != want {
			t.Errorf("i3Chord(%q) = %q, %v; want %q, true", input, got, ok, want)
		}
	}
	if _, ok := i3Chord("SUPER + mouse:999"); ok {
		t.Fatal("unknown mouse button must be rejected")
	}
}

func TestResolveShippedBindsMapsAndReportsCatalogue(t *testing.T) {
	binds, rows, report := resolveShippedBinds(keybindStore{})
	if len(rows) != len(ShippedBinds()) {
		t.Fatalf("rows = %d, want %d", len(rows), len(ShippedBinds()))
	}
	if len(binds) == 0 || len(report) == 0 {
		t.Fatalf("expected both implemented binds and explicit limitations; binds=%d report=%d", len(binds), len(report))
	}
	foundClose, foundUnsupported, foundFamily := false, false, false
	for _, row := range rows {
		if row.ID == "window.close" {
			foundClose = row.Unhonored == "" && row.Chord == "SUPER + Q"
		}
		if row.Unhonored != "" {
			foundUnsupported = true
		}
		if row.ID == "workspace.focus" {
			foundFamily = row.Unhonored == "" && row.Chord == "SUPER + {n}"
		}
	}
	if !foundClose || !foundUnsupported || !foundFamily {
		t.Fatalf("catalogue support reporting incomplete: close=%v unsupported=%v family=%v", foundClose, foundUnsupported, foundFamily)
	}
	generated := renderGeneratedI3Config(binds)
	if !strings.Contains(generated, "bindsym Mod4+q ") || !strings.Contains(generated, "workspace number 1") {
		t.Fatalf("generated i3 config is missing semantic Ryoku actions:\n%s", generated)
	}
	if strings.Contains(generated, "Mod4+r") {
		t.Fatal("unsupported pin action must not be invented or emitted")
	}
}

func TestResolveShippedBindsHonoursFamilyRebindAndDisabledRows(t *testing.T) {
	store := keybindStore{
		KeybindRebinds: map[string]string{"SUPER + {n}": "SUPER + CTRL + {n}"},
		KeybindDisabled: []string{"SUPER + F"},
	}
	binds, rows, _ := resolveShippedBinds(store)
	contains := func(chord string) bool {
		for _, bind := range binds {
			if bind.chord == chord {
				return true
			}
		}
		return false
	}
	if !contains("Mod4+Control+1") || contains("Mod4+1") {
		t.Fatalf("workspace family rebind not applied with upstream semantics: %+v", binds)
	}
	if contains("Mod4+f") {
		t.Fatal("disabled fullscreen chord was emitted")
	}
	for _, row := range rows {
		if row.ID == "workspace.focus" && row.Chord != "SUPER + CTRL + {n}" {
			t.Fatalf("workspace family legend chord = %q", row.Chord)
		}
		if row.ID == "window.fullscreen" && (!row.Disabled || row.Chord != "") {
			t.Fatalf("disabled fullscreen row not represented honestly: %+v", row)
		}
	}
}

func TestReboundDefaultWinsChordCollisionBeforeStaticDefault(t *testing.T) {
	store := keybindStore{KeybindRebinds: map[string]string{"SUPER + Q": "SUPER + F"}}
	binds, _, _ := resolveShippedBinds(store)
	var owner string
	for _, bind := range binds {
		if bind.chord == "Mod4+f" {
			owner = bind.id
			break
		}
	}
	if owner != "window.close" {
		t.Fatalf("rebound close must claim SUPER+F before fullscreen static default; owner=%q", owner)
	}
}

func TestCustomBindWinsShippedChordAndCanUseRelease(t *testing.T) {
	store := keybindStore{Keybinds: []keybind{{Keys: "SUPER + Q", Action: "exec", Value: "printf custom", Release: true}}}
	binds, _, _ := resolveShippedBinds(store)
	if len(binds) == 0 || binds[0].id != "custom.0" || !binds[0].release {
		t.Fatalf("custom bind did not claim the chord first: %+v", binds)
	}
	generated := renderGeneratedI3Config(binds)
	if !strings.Contains(generated, "bindsym --release Mod4+q") {
		t.Fatalf("release flag missing from generated custom binding: %s", generated)
	}
}

func TestMouseGesturesUseI3FloatingModifierWithoutGeneratedBind(t *testing.T) {
	binds, rows, _ := resolveShippedBinds(keybindStore{})
	for _, row := range rows {
		if row.ID == "mouse.move" || row.ID == "mouse.resize" {
			if row.Unhonored != "" {
				t.Fatalf("native i3 floating modifier should honor %s: %s", row.ID, row.Unhonored)
			}
		}
	}
	for _, bind := range binds {
		if bind.id == "mouse.move" || bind.id == "mouse.resize" {
			t.Fatalf("mouse gestures should use the existing floating_modifier directive, not duplicate binds: %+v", bind)
		}
	}
}
