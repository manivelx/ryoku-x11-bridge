package main

import (
	"encoding/binary"
	"net"
	"os"
	"path/filepath"
	"testing"
)

func TestIPCHeaderLayout(t *testing.T) {
	i := &ipcConn{}
	b := make([]byte, 14)
	copy(b, ipcMagic)
	binary.LittleEndian.PutUint32(b[6:10], 3)
	binary.LittleEndian.PutUint32(b[10:14], msgTree)
	if string(b[:6]) != "i3-ipc" || binary.LittleEndian.Uint32(b[6:10]) != 3 || binary.LittleEndian.Uint32(b[10:14]) != msgTree {
		t.Fatal("invalid header")
	}
	_ = i
}
func TestValidDirection(t *testing.T) {
	for _, v := range []string{"left", "right", "up", "down"} {
		if !validDirection(v) {
			t.Fatalf("%s should be valid", v)
		}
	}
	for _, v := range []string{"north", "", "LEFT"} {
		if validDirection(v) {
			t.Fatalf("%s should be invalid", v)
		}
	}
}
func TestQuoteWorkspace(t *testing.T) {
	if quoteWorkspace("3") != "3" {
		t.Fatal("numeric workspace should remain numeric")
	}
	if quoteWorkspace("dev work") != `"dev work"` {
		t.Fatal("workspace with spaces must be quoted")
	}
}

func TestSocketPathFromEnvAcceptsOnlyLiveI3Socket(t *testing.T) {
	socket := filepath.Join(t.TempDir(), "i3.sock")
	listener, err := net.Listen("unix", socket)
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()

	if got := socketPathFromEnv(socket); got != socket {
		t.Fatalf("got %q, want %q", got, socket)
	}
	if got := socketPathFromEnv(filepath.Join(t.TempDir(), "missing.sock")); got != "" {
		t.Fatalf("stale I3SOCK should be rejected, got %q", got)
	}
}

func TestSocketPathIgnoresSwaySocket(t *testing.T) {
	swaySocket := filepath.Join(t.TempDir(), "sway.sock")
	listener, err := net.Listen("unix", swaySocket)
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()

	t.Setenv("I3SOCK", "")
	t.Setenv("SWAYSOCK", swaySocket)
	// socketPath may ask the local i3 binary, but it must not use SWAYSOCK.
	if got := socketPathFromEnv(os.Getenv("SWAYSOCK")); got != "" {
		t.Fatalf("Sway socket must never be accepted as an i3 socket: %q", got)
	}
	for _, entry := range withoutEnv([]string{"PATH=/bin", "SWAYSOCK=" + swaySocket, "I3SOCK=/tmp/i3"}, "SWAYSOCK") {
		if len(entry) >= len("SWAYSOCK=") && entry[:len("SWAYSOCK=")] == "SWAYSOCK=" {
			t.Fatalf("SWAYSOCK leaked into sanitized environment: %q", entry)
		}
	}
}
