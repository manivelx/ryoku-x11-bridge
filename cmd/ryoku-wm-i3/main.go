package main

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"
)

var out = bufio.NewWriter(os.Stdout)

func main() {
	if len(os.Args) < 2 { usage(); os.Exit(2) }
	defer out.Flush()
	var err error
	switch os.Args[1] {
	case "caps": err = runCaps()
	case "state": err = runState()
	case "watch": err = runWatch(os.Args[2:])
	case "act": err = runAct(os.Args[2:])
	case "defaults": _,err = fmt.Fprintln(out, "{}")
	case "schema": _,err = fmt.Fprintln(out, "[]")
	case "binds": err = runBinds(os.Args[2:])
	case "apply": err = runApply(os.Args[2:])
	case "outputs": err = runOutputs(os.Args[2:])
	case "session": err = runSession()
	case "environment": err = runEnvironment(os.Args[2:])
	case "-h","--help","help": usage()
	default: err = fmt.Errorf("unknown verb %q", os.Args[1])
	}
	_ = out.Flush()
	if err != nil { fmt.Fprintf(os.Stderr,"ryoku-wm-i3: %v\n",err); os.Exit(1) }
}
func usage(){fmt.Fprintln(os.Stderr,"ryoku-wm-i3: caps|state|watch|act|apply|defaults|schema|binds|outputs|session|environment")}
func runCaps() error {
	c := Caps{
		Name:           "i3",
		Version:        "0.2.0",
		Instance:       socketPath(),
		Supports:       []string{"workspaces", "workspaceMoveToOutput", "windowWorkspaceMap", "workspaceFullscreenState", "windowGeometry", "windowFloat", "sessionExit", "configReload", "tiledLayout"},
		SettingDomains: []string{},
		ConfigDir:      "ryoku-x11",
		ConfigEntry:    "ryoku-x11/config",
		ConfigFiles:    []string{"ryoku-x11/config", "ryoku-x11/user.conf"},
		GeneratedFiles: []string{"ryoku-x11/generated.conf"},
		Packages:       []string{"i3-wm", "quickshell", "i3lock", "xclip", "maim", "slop", "xorg-xrandr"},
		WorkspaceModel: "dynamic",
		ForeignAPIs:    []ForeignAPI{},
	}
	return json.NewEncoder(out).Encode(c)
}

func runState() error { s,e:=readState(); if e!=nil{return e}; enc:=json.NewEncoder(out); enc.SetIndent("","  "); return enc.Encode(s) }
func runWatch(args []string) error {
	want:=map[string]bool{}; for _,a:=range args{want[a]=true}
	for {
		sock:=socketPath(); if sock=="" { time.Sleep(500*time.Millisecond); continue }
		c,e:=dial(sock); if e!=nil {time.Sleep(500*time.Millisecond);continue}
		raw,e:=c.request(msgSubscribe,[]string{"workspace","output","window","mode"}); if e!=nil {c.close();time.Sleep(500*time.Millisecond);continue}
		var ack struct{Success bool `json:"success"`}
		if e=json.Unmarshal(raw,&ack); e!=nil || !ack.Success {c.close();time.Sleep(500*time.Millisecond);continue}
		emitState:=func() bool {
			s,e:=readState(); if e!=nil{return false}
			frames:=[]Frame{{Kind:"outputs",Outputs:s.Outputs},{Kind:"workspaces",Workspaces:s.Workspaces},{Kind:"windows",Windows:s.Windows},{Kind:"focus",FocusedOutput:s.FocusedOutput}}
			for _,f:=range frames { if len(want)==0 || want[f.Kind] {if json.NewEncoder(out).Encode(f)!=nil || out.Flush()!=nil{return false}} }
			return true
		}
		if !emitState(){c.close();return nil}
		if json.NewEncoder(out).Encode(Frame{Kind:"ready"})!=nil || out.Flush()!=nil {c.close();return nil}
		for {
			_,_,e:=c.readMessage()
			if e!=nil {break}
			if !emitState(){c.close();return nil}
		}
		c.close(); time.Sleep(500*time.Millisecond)
	}
}
func runAct(a []string) error {\n\treturn runAction(a)\n}\n\nfunc runCommand(command string) error { c,e:=dial(socketPath());if e!=nil{return e};defer c.close();raw,e:=c.request(msgCommand,command);if e!=nil{return e};var replies []struct{Success bool `json:"success"`;Error bool `json:"error"`;ParseError bool `json:"parse_error"`;ErrorMessage string `json:"error_message"`};if e=json.Unmarshal(raw,&replies);e!=nil{return e};for _,r:=range replies{if !r.Success{return fmt.Errorf("i3 rejected command %q: %s",command,r.ErrorMessage)}};return nil }
func runOutputs(args []string) error {if len(args)==0{return errors.New("outputs: missing layout file")};rep:=ApplyReport{Provider:"i3",Unhonored:[]Unhonored{{Key:"outputs",Reason:"Live output configuration is not yet implemented; no display settings were changed."}}};enc:=json.NewEncoder(out);enc.SetIndent("","  ");return enc.Encode(rep)}
func runSession() error {_,e:=fmt.Fprint(out,"[Desktop Entry]\nName=Ryoku (X11 / i3)\nComment=Ryoku desktop on Xorg with i3\nTryExec=i3\nExec=ryoku-x11-session\nType=Application\nDesktopNames=Ryoku;\n");return e}
func runEnvironment(args []string) error {if len(args)!=1{return errors.New("environment: expected one process id")};pid,e:=strconv.Atoi(args[0]);if e!=nil||pid<=0{return errors.New("environment: invalid process id")};b,e:=os.ReadFile(fmt.Sprintf("/proc/%d/environ",pid));if e!=nil{return e};sock:=envValue(b,"I3SOCK");if sock==""{return nil};if !alive(sock){return nil};_,e=fmt.Fprintf(out,"I3SOCK=%s%c",sock,byte(0));return e}
func envValue(b []byte,k string)string{for _,p:=range strings.Split(string(b),"\x00"){if strings.HasPrefix(p,k+"="){return strings.TrimPrefix(p,k+"=")}};return ""}
func boundedDelta(raw string) (string, int, error) {
	delta, err := strconv.Atoi(raw)
	if err != nil || delta == 0 || delta < -20 || delta > 20 {
		return "", 0, fmt.Errorf("workspace delta must be between -20 and 20, excluding zero: %q", raw)
	}
	direction := "next"
	if delta < 0 {
		direction = "prev"
		delta = -delta
	}
	return direction, delta, nil
}

func findWindowIDByTitle(windows []Window, title string) (string, bool) {
	for _, window := range windows {
		if window.Title == title && window.ID != "" {
			return window.ID, true
		}
	}
	return "", false
}

func quoteWorkspace(s string)string{if _,e:=strconv.Atoi(s);e==nil{return s};return quoteToken(s)}
func quoteToken(s string)string{return strconv.Quote(s)}
func validDirection(s string)bool{return s=="left"||s=="right"||s=="up"||s=="down"}
