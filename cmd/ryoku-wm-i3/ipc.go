package main

import (
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"os/exec"
	"strings"
	"time"
)

const ipcMagic="i3-ipc"
const (msgCommand uint32=0; msgWorkspaces uint32=1; msgSubscribe uint32=2; msgOutputs uint32=3; msgTree uint32=4)
type ipcConn struct{ c net.Conn }
func (i *ipcConn) close(){if i!=nil&&i.c!=nil{_ = i.c.Close()}}
func (i *ipcConn) request(kind uint32,payload any)(json.RawMessage,error){b,e:=json.Marshal(payload);if e!=nil{return nil,e};if e=i.write(kind,b);e!=nil{return nil,e};k,body,e:=i.readMessage();if e!=nil{return nil,e};if k!=kind{return nil,fmt.Errorf("i3 IPC reply type mismatch: got %d want %d",k,kind)};return body,nil}
func (i *ipcConn) write(kind uint32,b []byte)error{if len(b)>4*1024*1024{return errors.New("i3 IPC payload too large")};h:=make([]byte,14);copy(h,ipcMagic);binary.LittleEndian.PutUint32(h[6:10],uint32(len(b)));binary.LittleEndian.PutUint32(h[10:14],kind);if _,e:=i.c.Write(append(h,b...));e!=nil{return e};return nil}
func (i *ipcConn) readMessage()(uint32,[]byte,error){h:=make([]byte,14);if _,e:=io.ReadFull(i.c,h);e!=nil{return 0,nil,e};if string(h[:6])!=ipcMagic{return 0,nil,errors.New("invalid i3 IPC magic")};n:=binary.LittleEndian.Uint32(h[6:10]);if n>4*1024*1024{return 0,nil,fmt.Errorf("i3 IPC payload length %d exceeds limit",n)};b:=make([]byte,n);if _,e:=io.ReadFull(i.c,b);e!=nil{return 0,nil,e};return binary.LittleEndian.Uint32(h[10:14]),b,nil}
func socketPath()string{if s:=os.Getenv("I3SOCK");s!=""{if alive(s){return s}};if s:=os.Getenv("SWAYSOCK");s!=""{if alive(s){return s}};if b,e:=exec.Command("i3","--get-socketpath").Output();e==nil{s:=strings.TrimSpace(string(b));if alive(s){return s}};if b,e:=exec.Command("i3-msg","-t","get_version").Output();e==nil{_ = b};return ""}
func alive(s string)bool{c,e:=net.DialTimeout("unix",s,150*time.Millisecond);if e!=nil{return false};_ = c.Close();return true}
func dial(s string)(*ipcConn,error){if s==""{return nil,errors.New("no live i3 IPC socket (I3SOCK unset or stale)")};c,e:=net.DialTimeout("unix",s,500*time.Millisecond);if e!=nil{return nil,e};return &ipcConn{c:c},nil}
