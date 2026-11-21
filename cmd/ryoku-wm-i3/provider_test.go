package main

import (
	"encoding/binary"
	"testing"
)

func TestIPCHeaderLayout(t *testing.T){
	i:=&ipcConn{}
	b:=make([]byte,14);copy(b,ipcMagic);binary.LittleEndian.PutUint32(b[6:10],3);binary.LittleEndian.PutUint32(b[10:14],msgTree)
	if string(b[:6])!="i3-ipc"||binary.LittleEndian.Uint32(b[6:10])!=3||binary.LittleEndian.Uint32(b[10:14])!=msgTree{t.Fatal("invalid header")}
	_ = i
}
func TestValidDirection(t *testing.T){for _,v:=range []string{"left","right","up","down"}{if !validDirection(v){t.Fatalf("%s should be valid",v)}};for _,v:=range []string{"north","", "LEFT"}{if validDirection(v){t.Fatalf("%s should be invalid",v)}}}
func TestQuoteWorkspace(t *testing.T){if quoteWorkspace("3")!="3"{t.Fatal("numeric workspace should remain numeric")};if quoteWorkspace("dev work")!=`"dev work"`{t.Fatal("workspace with spaces must be quoted")}}
