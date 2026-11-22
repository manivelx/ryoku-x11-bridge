package main

import (
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"strings"
	"testing"
)

func TestIPCRequestUsesEmptyPayloadForQueries(t *testing.T) {
	client, server := net.Pipe()
	defer client.Close()
	defer server.Close()
	done := make(chan error, 1)
	go func() {
		header := make([]byte, 14)
		if _, err := io.ReadFull(server, header); err != nil {
			done <- err
			return
		}
		if string(header[:6]) != ipcMagic {
			done <- errBadHeader
			return
		}
		if got := binary.LittleEndian.Uint32(header[6:10]); got != 0 {
			done <- errUnexpectedPayload
			return
		}
		if got := binary.LittleEndian.Uint32(header[10:14]); got != msgTree {
			done <- errWrongType
			return
		}
		body := []byte("{}")
		reply := make([]byte, 14)
		copy(reply, ipcMagic)
		binary.LittleEndian.PutUint32(reply[6:10], uint32(len(body)))
		binary.LittleEndian.PutUint32(reply[10:14], msgTree)
		_, err := server.Write(append(reply, body...))
		done <- err
	}()
	raw, err := (&ipcConn{c: client}).request(msgTree, nil)
	if err != nil {
		t.Fatal(err)
	}
	var got map[string]any
	if err := json.Unmarshal(raw, &got); err != nil {
		t.Fatal(err)
	}
	if err := <-done; err != nil {
		t.Fatal(err)
	}
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
					Class    string `json:"class"`
					Instance string `json:"instance"`
					Title    string `json:"title"`
				}{Class: app, Instance: "kitty", Title: title},
			}},
		}},
	}}}
	var windows []Window
	walkWindows(&root, "", "", nil, &windows)
	if len(windows) != 1 {
		t.Fatalf("got %d windows, want 1", len(windows))
	}
	w := windows[0]
	if w.ID != "1234" || w.AppID != app || w.Title != title || w.Workspace != "1" || w.Output != "HDMI-1" {
		t.Fatalf("unexpected window identity: %+v", w)
	}
	if !w.Focused || w.Pid != 4321 || w.Width != 1200 || w.Height != 800 {
		t.Fatalf("window metadata missing: %+v", w)
	}
	if !workspaceHasFullscreen(&root, "1") {
		t.Fatal("workspace fullscreen state was not detected")
	}
	if workspaceHasFullscreen(&root, "2") {
		t.Fatal("unrelated workspace reported fullscreen")
	}
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

func TestBoundedWorkspaceDelta(t *testing.T) {
	for _, tc := range []struct {
		raw   string
		dir   string
		count int
	}{
		{raw: "1", dir: "next", count: 1},
		{raw: "4", dir: "next", count: 4},
		{raw: "-2", dir: "prev", count: 2},
		{raw: "-20", dir: "prev", count: 20},
	} {
		dir, count, err := boundedDelta(tc.raw)
		if err != nil || dir != tc.dir || count != tc.count {
			t.Fatalf("boundedDelta(%q) = %q, %d, %v", tc.raw, dir, count, err)
		}
	}
	for _, raw := range []string{"0", "21", "-21", "next", "1; kill"} {
		if _, _, err := boundedDelta(raw); err == nil {
			t.Fatalf("boundedDelta(%q) unexpectedly succeeded", raw)
		}
	}
}

func TestFindWindowIDByExactTitle(t *testing.T) {
	windows := []Window{
		{ID: "100", Title: "Terminal"},
		{ID: "200", Title: "Terminal — project"},
	}
	if id, ok := findWindowIDByTitle(windows, "Terminal"); !ok || id != "100" {
		t.Fatalf("exact title lookup = %q, %v", id, ok)
	}
	if id, ok := findWindowIDByTitle(windows, "terminal"); ok {
		t.Fatalf("case-insensitive title lookup unexpectedly returned %q", id)
	}
	if _, ok := findWindowIDByTitle(windows, "missing"); ok {
		t.Fatal("missing title unexpectedly found")
	}
}

func TestWorkspaceAndActionValidation(t *testing.T) {
	if quoteWorkspace("2") != "2" {
		t.Fatal("numeric workspace must stay numeric")
	}
	if quoteWorkspace("web dev") != `"web dev"` {
		t.Fatal("workspace names with spaces must be quoted")
	}
	for _, direction := range []string{"left", "right", "up", "down"} {
		if !validDirection(direction) {
			t.Fatalf("%s should be accepted", direction)
		}
	}
	for _, direction := range []string{"north", "LEFT", "left; kill"} {
		if validDirection(direction) {
			t.Fatalf("%s should be rejected", direction)
		}
	}
}

var (
	errBadHeader         = &testError{"bad header"}
	errUnexpectedPayload = &testError{"unexpected payload"}
	errWrongType         = &testError{"wrong type"}
)

type testError struct{ message string }

func (e *testError) Error() string { return e.message }

func TestIPCCommandPayloadIsRawText(t *testing.T) {
	client, server := net.Pipe()
	defer client.Close()
	defer server.Close()

	done := make(chan error, 1)
	go func() {
		header := make([]byte, 14)
		if _, err := io.ReadFull(server, header); err != nil {
			done <- err
			return
		}
		length := binary.LittleEndian.Uint32(header[6:10])
		body := make([]byte, length)
		if _, err := io.ReadFull(server, body); err != nil {
			done <- err
			return
		}
		if got := string(body); got != "workspace 2" {
			done <- fmt.Errorf("RUN_COMMAND payload = %q, want raw command text", got)
			return
		}
		replyBody := []byte(`[{"success":true}]`)
		reply := make([]byte, 14)
		copy(reply, ipcMagic)
		binary.LittleEndian.PutUint32(reply[6:10], uint32(len(replyBody)))
		binary.LittleEndian.PutUint32(reply[10:14], msgCommand)
		_, err := server.Write(append(reply, replyBody...))
		done <- err
	}()

	if _, err := (&ipcConn{c: client}).request(msgCommand, "workspace 2"); err != nil {
		t.Fatal(err)
	}
	if err := <-done; err != nil {
		t.Fatal(err)
	}
}

func TestFocusedWindowSentinelDoesNotClaimHistory(t *testing.T) {
	windows := []Window{
		{ID: "1", Focused: false},
		{ID: "2", Focused: true},
		{ID: "3", Focused: false},
	}
	setFocusedWindowSentinel(windows)
	for _, window := range windows {
		want := 1
		if window.Focused {
			want = 0
		}
		if window.FocusOrder != want {
			t.Fatalf("window %s focusOrder = %d, want %d", window.ID, window.FocusOrder, want)
		}
	}
}

func TestFormatModeNormalizesMillihertzAndOmitsMissingData(t *testing.T) {
	for _, tc := range []struct {
		name string
		mode mode
		want string
	}{
		{name: "millihertz", mode: mode{Width: 1920, Height: 1080, Refresh: 60000}, want: "1920x1080@60"},
		{name: "fractional millihertz", mode: mode{Width: 1920, Height: 1080, Refresh: 59940}, want: "1920x1080@59.94"},
		{name: "already hertz", mode: mode{Width: 1280, Height: 720, Refresh: 60}, want: "1280x720@60"},
		{name: "unknown refresh", mode: mode{Width: 1024, Height: 768}, want: "1024x768"},
		{name: "missing mode", mode: mode{}, want: ""},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if got := formatMode(tc.mode); got != tc.want {
				t.Fatalf("formatMode(%+v) = %q, want %q", tc.mode, got, tc.want)
			}
		})
	}
}
