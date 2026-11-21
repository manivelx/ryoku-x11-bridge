package main

import (
	"encoding/binary"
	"encoding/json"
	"io"
	"net"
	"testing"
	"strings"
)

func TestIPCRequestUsesEmptyPayloadForQueries(t *testing.T) {
	client, server := net.Pipe()
	defer client.Close()
	defer server.Close()
	done := make(chan error, 1)
	go func() {
		header := make([]byte, 14)
		if _, err := io.ReadFull(server, header); err != nil { done <- err; return }
		if string(header[:6]) != ipcMagic { done <- errBadHeader; return }
		if got := binary.LittleEndian.Uint32(header[6:10]); got != 0 { done <- errUnexpectedPayload; return }
		if got := binary.LittleEndian.Uint32(header[10:14]); got != msgTree { done <- errWrongType; return }
		body := []byte("{}")
		reply := make([]byte, 14)
		copy(reply, ipcMagic)
		binary.LittleEndian.PutUint32(reply[6:10], uint32(len(body)))
		binary.LittleEndian.PutUint32(reply[10:14], msgTree)
		_, err := server.Write(append(reply, body...))
		done <- err
	}()
	raw, err := (&ipcConn{c: client}).request(msgTree, nil)
	if err != nil { t.Fatal(err) }
	var got map[string]any
	if err := json.Unmarshal(raw, &got); err != nil { t.Fatal(err) }
	if err := <-done; err != nil { t.Fatal(err) }
}

func TestWalkWindowsPreservesIdentityAndFullscreen(t *testing.T) {
	title := "Terminal"
	app := "kitty"
	root := node{Type: "root", Nodes: []node{{
		Type: "output", Name: "HDMI-1", Nodes: []node{{
			Type: "workspace", Name: "1", Nodes: []node{{
				ID: 1234, Type: "con", Name: title, Focused: true, PID: 4321,
				AppID: &app, FullscreenMode: 1,
				Rect: rect{X: 100, Y: 50, Width: 1200, Height: 800},
				WindowProperties: struct {
					Class string `json:"class"`
					Instance string `json:"instance"`
					Title string `json:"title"`
				}{Class: app, Instance: "kitty", Title: title},
			}},
		}},
	}}}
	var windows []Window
	walkWindows(&root, "", "", nil, &windows)
	if len(windows) != 1 { t.Fatalf("got %d windows, want 1", len(windows)) }
	w := windows[0]
	if w.ID != "1234" || w.AppID != app || w.Title != title || w.Workspace != "1" || w.Output != "HDMI-1" {
		t.Fatalf("unexpected window identity: %+v", w)
	}
	if !w.Focused || w.Pid != 4321 || w.Width != 1200 || w.Height != 800 {
		t.Fatalf("window metadata missing: %+v", w)
	}
	if !workspaceHasFullscreen(&root, "1") { t.Fatal("workspace fullscreen state was not detected") }
	if workspaceHasFullscreen(&root, "2") { t.Fatal("unrelated workspace reported fullscreen") }
}


func TestIPCReadMessageHandlesFragmentedFrames(t *testing.T) {
	client, server := net.Pipe()
	defer client.Close()
	defer server.Close()
	body := []byte(`{"success":true}`)
	header := make([]byte, 14)
	copy(header, ipcMagic)
	binary.LittleEndian.PutUint32(header[6:10], uint32(len(body)))
	binary.LittleEndian.PutUint32(header[10:14], msgSubscribe)
	go func() {
		for _, part := range [][]byte{header[:3], header[3:9], header[9:], body[:4], body[4:]} {
			_, _ = server.Write(part)
		}
	}()
	kind, got, err := (&ipcConn{c: client}).readMessage()
	if err != nil {
		t.Fatal(err)
	}
	if kind != msgSubscribe || string(got) != string(body) {
		t.Fatalf("got kind=%d body=%q", kind, got)
	}
}

func TestIPCReadRejectsInvalidMagic(t *testing.T) {
	client, server := net.Pipe()
	defer client.Close()
	defer server.Close()
	go func() {
		header := make([]byte, 14)
		copy(header, "bad-ipc")
		_, _ = server.Write(header)
	}()
	_, _, err := (&ipcConn{c: client}).readMessage()
	if err == nil || err.Error() != "invalid i3 IPC magic" {
		t.Fatalf("expected invalid magic error, got %v", err)
	}
}

func TestIPCReadRejectsOversizedPayloadBeforeAllocation(t *testing.T) {
	client, server := net.Pipe()
	defer client.Close()
	defer server.Close()
	go func() {
		header := make([]byte, 14)
		copy(header, ipcMagic)
		binary.LittleEndian.PutUint32(header[6:10], 4*1024*1024+1)
		binary.LittleEndian.PutUint32(header[10:14], msgTree)
		_, _ = server.Write(header)
	}()
	_, _, err := (&ipcConn{c: client}).readMessage()
	if err == nil || !strings.Contains(err.Error(), "exceeds limit") {
		t.Fatalf("expected payload limit error, got %v", err)
	}
}

func TestIPCRequestRejectsMismatchedReplyType(t *testing.T) {
	client, server := net.Pipe()
	defer client.Close()
	defer server.Close()
	go func() {
		header := make([]byte, 14)
		_, _ = io.ReadFull(server, header)
		reply := make([]byte, 14)
		copy(reply, ipcMagic)
		binary.LittleEndian.PutUint32(reply[10:14], msgOutputs)
		_, _ = server.Write(reply)
	}()
	_, err := (&ipcConn{c: client}).request(msgTree, nil)
	if err == nil || !strings.Contains(err.Error(), "reply type mismatch") {
		t.Fatalf("expected reply type mismatch, got %v", err)
	}
}

func TestWorkspaceAndActionValidation(t *testing.T) {
	if quoteWorkspace("2") != "2" { t.Fatal("numeric workspace must stay numeric") }
	if quoteWorkspace("web dev") != `"web dev"` { t.Fatal("workspace names with spaces must be quoted") }
	for _, direction := range []string{"left", "right", "up", "down"} {
		if !validDirection(direction) { t.Fatalf("%s should be accepted", direction) }
	}
	for _, direction := range []string{"north", "LEFT", "left; kill"} {
		if validDirection(direction) { t.Fatalf("%s should be rejected", direction) }
	}
}

var (
	errBadHeader = &testError{"bad header"}
	errUnexpectedPayload = &testError{"unexpected payload"}
	errWrongType = &testError{"wrong type"}
)
type testError struct{ message string }
func (e *testError) Error() string { return e.message }
