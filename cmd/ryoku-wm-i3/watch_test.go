package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"io"
	"net"
	"testing"
	"time"
)

func TestEmitChangedFramesSendsFullInitialSyncAndReadyIsSeparate(t *testing.T) {
	buffer, restore := captureProviderOutput(t)
	defer restore()

	snapshot := Snapshot{
		FocusedOutput: "HDMI-1",
		Outputs:       []Output{{Name: "HDMI-1", Width: 1920, Height: 1080, Focused: true}},
		Workspaces:    []Workspace{{ID: "1", Name: "1", Output: "HDMI-1", Active: true}},
		Windows:       []Window{{ID: "101", Title: "Terminal", Workspace: "1"}},
	}
	var previous Snapshot
	if err := emitChangedFrames(snapshot, &previous, true, nil); err != nil {
		t.Fatal(err)
	}
	lines := bytes.Split(bytes.TrimSpace(buffer.Bytes()), []byte("\n"))
	if len(lines) != 4 {
		t.Fatalf("initial sync should contain four state frames, got %d: %s", len(lines), buffer.String())
	}
	kinds := map[string]bool{}
	for _, line := range lines {
		var frame Frame
		if err := json.Unmarshal(line, &frame); err != nil {
			t.Fatal(err)
		}
		kinds[frame.Kind] = true
	}
	for _, kind := range []string{"outputs", "workspaces", "windows", "focus"} {
		if !kinds[kind] {
			t.Fatalf("initial sync omitted %q frame", kind)
		}
	}
	if previous.FocusedOutput != snapshot.FocusedOutput {
		t.Fatal("previous snapshot was not updated after initial sync")
	}
}

func TestEmitChangedFramesOnlySendsChangedKinds(t *testing.T) {
	buffer, restore := captureProviderOutput(t)
	defer restore()

	previous := Snapshot{
		FocusedOutput: "HDMI-1",
		Outputs:       []Output{{Name: "HDMI-1", Width: 1920, Height: 1080, Focused: true}},
		Workspaces:    []Workspace{{ID: "1", Name: "1", Output: "HDMI-1", Active: true}},
		Windows:       []Window{{ID: "101", Title: "Terminal", Workspace: "1"}},
	}
	next := previous
	next.Windows = []Window{{ID: "101", Title: "Terminal", Workspace: "1"}, {ID: "202", Title: "Browser", Workspace: "1"}}

	if err := emitChangedFrames(next, &previous, false, nil); err != nil {
		t.Fatal(err)
	}
	lines := bytes.Split(bytes.TrimSpace(buffer.Bytes()), []byte("\n"))
	if len(lines) != 1 {
		t.Fatalf("expected only one changed frame, got %d: %s", len(lines), buffer.String())
	}
	var frame Frame
	if err := json.Unmarshal(lines[0], &frame); err != nil {
		t.Fatal(err)
	}
	if frame.Kind != "windows" || len(frame.Windows) != 2 {
		t.Fatalf("unexpected incremental frame: %+v", frame)
	}
}

func TestEmitChangedFramesHonoursRequestedKinds(t *testing.T) {
	buffer, restore := captureProviderOutput(t)
	defer restore()

	next := Snapshot{Outputs: []Output{{Name: "DP-1", Width: 1280, Height: 720}}}
	var previous Snapshot
	if err := emitChangedFrames(next, &previous, true, map[string]bool{"outputs": true}); err != nil {
		t.Fatal(err)
	}
	var frame Frame
	if err := json.Unmarshal(bytes.TrimSpace(buffer.Bytes()), &frame); err != nil {
		t.Fatal(err)
	}
	if frame.Kind != "outputs" {
		t.Fatalf("requested outputs frame, got %q", frame.Kind)
	}
}

func TestCoalesceEventsReturnsAfterQuietWindow(t *testing.T) {
	client, server := net.Pipe()
	defer client.Close()
	defer server.Close()
	if err := coalesceEvents(&ipcConn{c: client}, 10*time.Millisecond); err != nil {
		t.Fatalf("quiet event stream should end the coalescing window, got %v", err)
	}
}

func TestCoalesceEventsReportsSocketLoss(t *testing.T) {
	client, server := net.Pipe()
	defer client.Close()
	_ = server.Close()
	err := coalesceEvents(&ipcConn{c: client}, 10*time.Millisecond)
	if err == nil || err == io.EOF {
		t.Fatalf("socket loss must be surfaced for watch resynchronization, got %v", err)
	}
}

var _ = bufio.NewWriter
