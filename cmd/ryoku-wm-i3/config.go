package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
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
	// Do not fabricate an effective bind legend. The i3 config is currently
	// fixed, while the upstream catalogue/rebind resolver has not yet been
	// ported. An empty answer is more accurate than reporting made-up chords.
	return json.NewEncoder(out).Encode([]bindRow{})
}

func runApply(args []string) error {
	storePath := ""
	for _, arg := range args {
		if arg == "--preview" {
			continue
		}
		if storePath == "" {
			storePath = arg
		}
	}
	if storePath == "" {
		return errors.New("apply: missing settings store path")
	}
	store, err := os.ReadFile(storePath)
	if err != nil {
		return fmt.Errorf("apply: cannot read settings store: %w", err)
	}
	if !json.Valid(store) {
		return errors.New("apply: settings store is not valid JSON")
	}

	// Fail closed until the neutral-store-to-i3 translation is implemented.
	// In particular, do not create an empty generated.conf that could be
	// mistaken for a successfully applied settings file.
	report := ApplyReport{
		Provider: "i3",
		Unhonored: []Unhonored{
			{Key: "desktop.keybinds", Reason: "i3 keybinding translation is not implemented; the active session config is unchanged."},
			{Key: "desktop.windowRules", Reason: "Window rules are not yet translated into i3 criteria."},
			{Key: "desktop.input", Reason: "Input settings remain managed by the existing X11 input configuration."},
			{Key: "desktop.appearance", Reason: "Provider-specific appearance settings are not generated from the neutral store yet."},
		},
	}
	return json.NewEncoder(out).Encode(report)
}
