package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
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

func TestRunBindsDoesNotInventCatalogueRows(t *testing.T) {
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
	if len(rows) != 0 {
		t.Fatalf("unported catalogue must not return fabricated bind rows: %+v", rows)
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

func TestApplyFailsClosedWithoutWritingGeneratedConfig(t *testing.T) {
	configHome := t.TempDir()
	t.Setenv("XDG_CONFIG_HOME", configHome)
	store := filepath.Join(t.TempDir(), "store.json")
	if err := os.WriteFile(store, []byte("{}"), 0o600); err != nil {
		t.Fatal(err)
	}

	for _, args := range [][]string{{store, "--preview"}, {store}} {
		buffer, restore := captureProviderOutput(t)
		if err := runApply(args); err != nil {
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
		if len(report.Written) != 0 {
			t.Fatalf("fail-closed apply reported written files: %+v", report.Written)
		}
		if len(report.Unhonored) == 0 {
			t.Fatal("expected explicit unhonored settings")
		}
	}
	if _, err := os.Stat(filepath.Join(configHome, "ryoku-x11")); !os.IsNotExist(err) {
		t.Fatalf("apply must not create an empty config directory, stat err=%v", err)
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
