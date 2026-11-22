package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func captureProviderOutput(t *testing.T) (*bytes.Buffer, func()) {
	t.Helper()
	previous := out
	var buffer bytes.Buffer
	out = bufio.NewWriter(&buffer)
	return &buffer, func() {
		_ = out.Flush()
		out = previous
	}
}

func TestRequiredWindowID(t *testing.T) {
	if id, err := requiredWindowID([]string{"123"}, 0); err != nil || id != 123 {
		t.Fatalf("expected id 123, got %d, err=%v", id, err)
	}
	for _, value := range []string{"", "0", "-1", "abc"} {
		if _, err := requiredWindowID([]string{value}, 0); err == nil {
			t.Fatalf("expected invalid window id %q to fail", value)
		}
	}
}

func TestRunBindsReportsRyokuCatalogueAndI3CustomRows(t *testing.T) {
	previous := readActiveI3Config
	readActiveI3Config = func() (string, error) {
		return "set $mod Mod4\nbindsym $mod+Return exec terminal\n", nil
	}
	defer func() { readActiveI3Config = previous }()
	configHome := t.TempDir()
	t.Setenv("RYOKU_CONFIG_HOME", configHome)

	buffer, restore := captureProviderOutput(t)
	defer restore()
	if err := runBinds(nil); err != nil {
		t.Fatal(err)
	}
	_ = out.Flush()
	var rows []bindRow
	if err := json.Unmarshal(buffer.Bytes(), &rows); err != nil {
		t.Fatal(err)
	}
	if len(rows) != len(ShippedBinds())+1 {
		t.Fatalf("bind legend returned %d rows, want %d shipped plus one custom: %+v", len(rows), len(ShippedBinds())+1, rows)
	}
	if rows[0].ID != "window.close" || rows[0].Default != "SUPER + Q" || rows[0].Unhonored != "" {
		t.Fatalf("implemented shipped Ryoku bind was not exposed as supported: %+v", rows[0])
	}
	unsupported := false
	for _, row := range rows {
		if row.Unhonored != "" {
			unsupported = true
		}
	}
	if !unsupported {
		t.Fatal("untranslated upstream actions must remain visible with an explicit unsupported reason")
	}
	custom := rows[len(rows)-1]
	if custom.Chord != "SUPER + ENTER" || custom.Kind != "custom" || custom.Default != "" {
		t.Fatalf("active i3 custom binding was not preserved as a custom row: %+v", custom)
	}
}

func TestRunCapsAdvertisesOnlyImplementedFeatures(t *testing.T) {
	buffer, restore := captureProviderOutput(t)
	defer restore()
	if err := runCaps(); err != nil {
		t.Fatal(err)
	}
	_ = out.Flush()
	var caps Caps
	if err := json.Unmarshal(buffer.Bytes(), &caps); err != nil {
		t.Fatal(err)
	}
	if caps.Name != "i3" || caps.Version == "" {
		t.Fatalf("unexpected i3 provider metadata: %+v", caps)
	}
	expected := map[string]bool{
		"workspaces": true, "workspaceMoveToOutput": true, "windowWorkspaceMap": true,
		"workspaceFullscreenState": true, "windowGeometry": true, "windowFloat": true,
		"sessionExit": true, "configReload": true, "tiledLayout": true,
	}
	for _, capability := range caps.Supports {
		if !expected[capability] {
			t.Fatalf("provider advertises unimplemented capability %q", capability)
		}
		delete(expected, capability)
	}
	for capability := range expected {
		t.Fatalf("provider does not advertise implemented capability %q", capability)
	}
}

func TestApplyPreviewsAndWritesGeneratedKeybindings(t *testing.T) {
	configHome := t.TempDir()
	t.Setenv("XDG_CONFIG_HOME", configHome)
	store := filepath.Join(t.TempDir(), "store.json")
	data := `{"desktop":{"keybindRebinds":{"SUPER + Q":"SUPER + X"},"keybindDisabled":["SUPER + F"]}}`
	if err := os.WriteFile(store, []byte(data), 0o600); err != nil {
		t.Fatal(err)
	}

	buffer, restore := captureProviderOutput(t)
	if err := runApply([]string{store, "--preview"}); err != nil {
		restore()
		t.Fatal(err)
	}
	_ = out.Flush()
	var preview ApplyReport
	if err := json.Unmarshal(buffer.Bytes(), &preview); err != nil {
		restore()
		t.Fatal(err)
	}
	restore()
	if len(preview.Written) != 0 {
		t.Fatalf("preview must not write files: %+v", preview.Written)
	}
	if _, err := os.Stat(filepath.Join(configHome, "ryoku-x11")); !os.IsNotExist(err) {
		t.Fatalf("preview unexpectedly created the RXB config directory: %v", err)
	}

	buffer, restore = captureProviderOutput(t)
	if err := runApply([]string{store}); err != nil {
		restore()
		t.Fatal(err)
	}
	_ = out.Flush()
	var report ApplyReport
	if err := json.Unmarshal(buffer.Bytes(), &report); err != nil {
		restore()
		t.Fatal(err)
	}
	restore()
	if len(report.Written) != 1 || !report.ReloadNeeded {
		t.Fatalf("apply did not report the generated config and required reload: %+v", report)
	}
	generated, err := os.ReadFile(filepath.Join(configHome, "ryoku-x11", "generated.conf"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(generated), "Mod4+x") {
		t.Fatalf("rebound close action was not generated: %s", generated)
	}
	if strings.Contains(string(generated), "Mod4+f") {
		t.Fatalf("disabled fullscreen action was unexpectedly generated: %s", generated)
	}
	if len(report.Unhonored) == 0 {
		t.Fatal("unsupported upstream actions must be reported")
	}
}


func TestApplyRejectsInvalidJSON(t *testing.T) {
	store := filepath.Join(t.TempDir(), "store.json")
	if err := os.WriteFile(store, []byte("{"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := runApply([]string{store, "--preview"}); err == nil {
		t.Fatal("invalid settings JSON must be rejected")
	}
}
