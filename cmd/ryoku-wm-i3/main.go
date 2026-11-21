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
	case "binds": _,err = fmt.Fprintln(out, "[]")
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
	c:=Caps{Name:"i3",Version:"0.1.0",Instance:socketPath(),Supports:[]string{"workspaces","workspaceMoveToOutput","windowWorkspaceMap","workspaceFullscreenState","windowGeometry","sessionExit"},WorkspaceModel:"dynamic",ForeignAPIs:[]any{},SettingDomains:[]string{},ConfigFiles:[]string{},GeneratedFiles:[]string{}}
	enc:=json.NewEncoder(out); enc.SetIndent("","  "); return enc.Encode(c)
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
func runAct(a []string) error {
	if len(a)==0{return errors.New("act: missing action id")}
	id,rest:=a[0],a[1:]
	switch id {
	case "window.focus","window.close","window.fullscreen","window.float":
		if len(rest)<1{return fmt.Errorf("act %s: missing window id",id)}
		n,e:=strconv.ParseInt(rest[0],10,64); if e!=nil || n<=0{return fmt.Errorf("act %s: invalid window id %q",id,rest[0])}
		cmd:=fmt.Sprintf("[con_id=%d] ",n)
		switch id {case "window.focus":cmd+="focus";case "window.close":cmd+="kill";case "window.fullscreen":cmd+="fullscreen toggle";case "window.float":cmd+="floating toggle"}
		return runCommand(cmd)
	case "app.focus":\n\t\tif len(rest)<1{return errors.New("act app.focus: missing app id")}\n\t\tsnap,e:=readState();if e!=nil{return e};for _,w:=range snap.Windows{if strings.EqualFold(w.AppID,rest[0]){n,err:=strconv.ParseInt(w.ID,10,64);if err==nil{return runCommand(fmt.Sprintf("[con_id=%d] focus",n))}}};return fmt.Errorf("no window found for app id %q",rest[0])\n\tcase "session.exit": return runCommand("exit")\n\tcase "workspace.focus":
		if len(rest)<1{return errors.New("act workspace.focus: missing workspace id")}
		return runCommand("workspace "+quoteWorkspace(rest[0]))
	case "workspace.cycle":
		d:=1; if len(rest)>0 {v,e:=strconv.Atoi(rest[0]);if e!=nil{return fmt.Errorf("invalid delta %q",rest[0])};d=v};dir:="next";if d<0{dir="prev";d=-d};for i:=0;i<d;i++{if e:=runCommand("workspace "+dir);e!=nil{return e}};return nil
	case "workspace.moveToOutput":
		if len(rest)<2{return errors.New("act workspace.moveToOutput: expected workspace id and output")}
		return runCommand("workspace "+quoteWorkspace(rest[0])+"; move workspace to output "+quoteToken(rest[1]))
	case "window.moveToWorkspace":
		if len(rest)<2{return errors.New("act window.moveToWorkspace: expected window id and workspace id")}
		n,e:=strconv.ParseInt(rest[0],10,64);if e!=nil||n<=0{return errors.New("invalid window id")}
		return runCommand(fmt.Sprintf("[con_id=%d] move container to workspace %s; focus",n,quoteWorkspace(rest[1])))
	case "window.focusDirection":
		if len(rest)<1{return errors.New("direction required")};d:=strings.ToLower(rest[0]);if !validDirection(d){return fmt.Errorf("invalid direction %q",d)};return runCommand("focus "+d)
	case "window.moveBy":
		if len(rest)<1{return errors.New("direction required")};d:=strings.ToLower(rest[0]);if !validDirection(d){return fmt.Errorf("invalid direction %q",d)};return runCommand("move "+d)
	case "window.resizeBy":
		if len(rest)<1{return errors.New("resize direction required")};switch rest[0]{case "wider":return runCommand("resize grow width 10 px or 10 ppt");case "narrower":return runCommand("resize shrink width 10 px or 10 ppt");case "taller":return runCommand("resize grow height 10 px or 10 ppt");case "shorter":return runCommand("resize shrink height 10 px or 10 ppt")}
		return fmt.Errorf("invalid resize direction %q",rest[0])
	case "output.focusDirection":
		if len(rest)<1{return errors.New("direction required")};d:=strings.ToLower(rest[0]);if !validDirection(d){return fmt.Errorf("invalid direction %q",d)};return runCommand("focus output "+d)
	case "window.center": return runCommand("move position center")
	default:return fmt.Errorf("unsupported or unknown action %q",id)
	}
}
func runCommand(command string) error { c,e:=dial(socketPath());if e!=nil{return e};defer c.close();raw,e:=c.request(msgCommand,command);if e!=nil{return e};var replies []struct{Success bool `json:"success"`;Error bool `json:"error"`;ParseError bool `json:"parse_error"`;ErrorMessage string `json:"error_message"`};if e=json.Unmarshal(raw,&replies);e!=nil{return e};for _,r:=range replies{if !r.Success{return fmt.Errorf("i3 rejected command %q: %s",command,r.ErrorMessage)}};return nil }
func runApply(args []string) error {
	path:="";preview:=false;for _,a:=range args{if a=="--preview"{preview=true}else if path==""{path=a}}
	if path==""{return errors.New("apply: missing store path")}
	report:=ApplyReport{Provider:"i3",Unhonored:[]Unhonored{{Key:"desktop.appearance",Reason:"The i3 provider currently does not generate visual decoration settings."},{Key:"desktop.input",Reason:"Input settings are not yet translated into the isolated i3 configuration."},{Key:"desktop.windowRules",Reason:"Window rules are not yet translated by this provider."},{Key:"desktop.keybinds",Reason:"Keybind generation is not yet implemented."}}}
	_ = preview
	enc:=json.NewEncoder(out);enc.SetIndent("","  ");return enc.Encode(report)
}
func runOutputs(args []string) error {if len(args)==0{return errors.New("outputs: missing layout file")};rep:=ApplyReport{Provider:"i3",Unhonored:[]Unhonored{{Key:"outputs",Reason:"Live output configuration is not yet implemented; no display settings were changed."}}};enc:=json.NewEncoder(out);enc.SetIndent("","  ");return enc.Encode(rep)}
func runSession() error {_,e:=fmt.Fprint(out,"[Desktop Entry]\nName=Ryoku (X11 / i3)\nComment=Ryoku desktop on Xorg with i3\nTryExec=i3\nExec=ryoku-x11-session\nType=Application\nDesktopNames=Ryoku;\n");return e}
func runEnvironment(args []string) error {if len(args)!=1{return errors.New("environment: expected one process id")};pid,e:=strconv.Atoi(args[0]);if e!=nil||pid<=0{return errors.New("environment: invalid process id")};b,e:=os.ReadFile(fmt.Sprintf("/proc/%d/environ",pid));if e!=nil{return e};sock:=envValue(b,"I3SOCK");if sock==""{return nil};if !alive(sock){return nil};_,e=fmt.Fprintf(out,"I3SOCK=%s%c",sock,byte(0));return e}
func envValue(b []byte,k string)string{for _,p:=range strings.Split(string(b),"\x00"){if strings.HasPrefix(p,k+"="){return strings.TrimPrefix(p,k+"=")}};return ""}
func quoteWorkspace(s string)string{if _,e:=strconv.Atoi(s);e==nil{return s};return quoteToken(s)}
func quoteToken(s string)string{return strconv.Quote(s)}
func validDirection(s string)bool{return s=="left"||s=="right"||s=="up"||s=="down"}
