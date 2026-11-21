package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
)

type bindRow struct {
	ID         string   `json:"id"`
	Category   string   `json:"category"`
	Label      string   `json:"label"`
	Hint       string   `json:"hint,omitempty"`
	Keys       []string `json:"keys"`
	Default    string   `json:"default"`
	Chord      string   `json:"chord"`
	Kind       string   `json:"kind"`
	Rebindable bool     `json:"rebindable"`
	Locked     bool     `json:"locked"`
	Unhonored  string   `json:"unhonored,omitempty"`
	Disabled   bool     `json:"disabled,omitempty"`
}

func runBinds(_ []string) error {
	rows := []bindRow{
		{ID: "terminal", Category: "Launch", Label: "Terminal", Hint: "Open the configured terminal.", Keys: []string{"SUPER", "RETURN"}, Default: "SUPER + RETURN", Chord: "SUPER + RETURN", Kind: "app", Locked: true},
		{ID: "launcher", Category: "Launch", Label: "Application launcher", Keys: []string{"SUPER", "SPACE"}, Default: "SUPER + SPACE", Chord: "SUPER + SPACE", Kind: "shell", Locked: true},
		{ID: "quicksettings", Category: "Ryoku", Label: "Quick settings", Keys: []string{"SUPER", "ESCAPE"}, Default: "SUPER + ESCAPE", Chord: "SUPER + ESCAPE", Kind: "shell", Locked: true},
		{ID: "hub", Category: "Ryoku", Label: "Ryoku Hub", Keys: []string{"SUPER", "COMMA"}, Default: "SUPER + COMMA", Chord: "SUPER + COMMA", Kind: "shell", Locked: true},
		{ID: "wallpaper", Category: "Ryoku", Label: "Wallpaper picker", Keys: []string{"SUPER", "W"}, Default: "SUPER + W", Chord: "SUPER + W", Kind: "shell", Locked: true},
		{ID: "screenshot", Category: "Ryoku", Label: "Screenshot", Keys: []string{"SUPER", "SHIFT", "S"}, Default: "SUPER + SHIFT + S", Chord: "SUPER + SHIFT + S", Kind: "shell", Locked: true},
		{ID: "lock", Category: "Session", Label: "Lock screen", Keys: []string{"SUPER", "L"}, Default: "SUPER + L", Chord: "SUPER + L", Kind: "shell", Locked: true},
		{ID: "close", Category: "Windows", Label: "Close window", Keys: []string{"SUPER", "Q"}, Default: "SUPER + Q", Chord: "SUPER + Q", Kind: "wm", Locked: true},
		{ID: "fullscreen", Category: "Windows", Label: "Toggle fullscreen", Keys: []string{"SUPER", "F"}, Default: "SUPER + F", Chord: "SUPER + F", Kind: "wm", Locked: true},
		{ID: "floating", Category: "Windows", Label: "Toggle floating", Keys: []string{"SUPER", "SHIFT", "F"}, Default: "SUPER + SHIFT + F", Chord: "SUPER + SHIFT + F", Kind: "wm", Locked: true},
		{ID: "reload", Category: "Session", Label: "Reload i3 configuration", Keys: []string{"SUPER", "SHIFT", "R"}, Default: "SUPER + SHIFT + R", Chord: "SUPER + SHIFT + R", Kind: "wm", Locked: true},
		{ID: "exit", Category: "Session", Label: "Exit Ryoku session", Keys: []string{"SUPER", "SHIFT", "E"}, Default: "SUPER + SHIFT + E", Chord: "SUPER + SHIFT + E", Kind: "wm", Locked: true},
		{ID: "focus-left", Category: "Windows", Label: "Focus left", Keys: []string{"SUPER", "LEFT"}, Default: "SUPER + LEFT", Chord: "SUPER + LEFT", Kind: "wm", Locked: true},
		{ID: "focus-right", Category: "Windows", Label: "Focus right", Keys: []string{"SUPER", "RIGHT"}, Default: "SUPER + RIGHT", Chord: "SUPER + RIGHT", Kind: "wm", Locked: true},
		{ID: "focus-up", Category: "Windows", Label: "Focus up", Keys: []string{"SUPER", "UP"}, Default: "SUPER + UP", Chord: "SUPER + UP", Kind: "wm", Locked: true},
		{ID: "focus-down", Category: "Windows", Label: "Focus down", Keys: []string{"SUPER", "DOWN"}, Default: "SUPER + DOWN", Chord: "SUPER + DOWN", Kind: "wm", Locked: true},
		{ID: "move-left", Category: "Windows", Label: "Move window left", Keys: []string{"SUPER", "SHIFT", "LEFT"}, Default: "SUPER + SHIFT + LEFT", Chord: "SUPER + SHIFT + LEFT", Kind: "wm", Locked: true},
		{ID: "move-right", Category: "Windows", Label: "Move window right", Keys: []string{"SUPER", "SHIFT", "RIGHT"}, Default: "SUPER + SHIFT + RIGHT", Chord: "SUPER + SHIFT + RIGHT", Kind: "wm", Locked: true},
		{ID: "move-up", Category: "Windows", Label: "Move window up", Keys: []string{"SUPER", "SHIFT", "UP"}, Default: "SUPER + SHIFT + UP", Chord: "SUPER + SHIFT + UP", Kind: "wm", Locked: true},
		{ID: "move-down", Category: "Windows", Label: "Move window down", Keys: []string{"SUPER", "SHIFT", "DOWN"}, Default: "SUPER + SHIFT + DOWN", Chord: "SUPER + SHIFT + DOWN", Kind: "wm", Locked: true},
	}
	for n := 1; n <= 9; n++ {
		key := fmt.Sprint(n)
		rows = append(rows,
			bindRow{ID: "workspace-" + key, Category: "Workspaces", Label: "Switch to workspace " + key, Keys: []string{"SUPER", key}, Default: "SUPER + " + key, Chord: "SUPER + " + key, Kind: "wm", Locked: true},
			bindRow{ID: "move-workspace-" + key, Category: "Workspaces", Label: "Move window to workspace " + key, Keys: []string{"SUPER", "SHIFT", key}, Default: "SUPER + SHIFT + " + key, Chord: "SUPER + SHIFT + " + key, Kind: "wm", Locked: true},
		)
	}
	return json.NewEncoder(out).Encode(rows)
}

func runApply(args []string) error {
	storePath := ""
	preview := false
	for _, arg := range args {
		if arg == "--preview" {
			preview = true
		} else if storePath == "" {
			storePath = arg
		}
	}
	if storePath == "" {
		return errors.New("apply: missing settings store path")
	}
	if _, err := os.Stat(storePath); err != nil {
		return fmt.Errorf("apply: cannot read settings store: %w", err)
	}

	report := ApplyReport{
		Provider: "i3",
		Unhonored: []Unhonored{
			{Key: "desktop.keybinds", Reason: "RXB i3 keybindings are currently fixed in the session config; live rebinding is not enabled."},
			{Key: "desktop.windowRules", Reason: "Window rules are not yet translated into i3 criteria."},
			{Key: "desktop.input", Reason: "Input settings remain managed by the existing X11 input configuration."},
			{Key: "desktop.appearance", Reason: "Provider-specific appearance settings are not generated from the neutral store yet."},
		},
	}
	if !preview {
		configHome, err := os.UserConfigDir()
		if err != nil {
			return fmt.Errorf("apply: resolve XDG config directory: %w", err)
		}
		dir := filepath.Join(configHome, "ryoku-x11")
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return fmt.Errorf("apply: create i3 config directory: %w", err)
		}
		generated := "# Generated by ryoku-wm-i3. Do not edit; place personal overrides in user.conf.\n"
		if err := os.WriteFile(filepath.Join(dir, "generated.conf"), []byte(generated), 0o644); err != nil {
			return fmt.Errorf("apply: write generated i3 config: %w", err)
		}
	}
	return json.NewEncoder(out).Encode(report)
}
