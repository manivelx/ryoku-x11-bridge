package main

import (
	"encoding/json"
	"fmt"
	"strconv"
)

type rect struct{X int `json:"x"`;Y int `json:"y"`;Width int `json:"width"`;Height int `json:"height"`}
type mode struct{Width int `json:"width"`;Height int `json:"height"`;Refresh float64 `json:"refresh"`}
type i3Output struct{Name string `json:"name"`;Active bool `json:"active"`;Primary bool `json:"primary"`;CurrentWorkspace string `json:"current_workspace"`;Rect rect `json:"rect"`;CurrentMode mode `json:"current_mode"`;Modes []mode `json:"modes"`;Make string `json:"make"`;Model string `json:"model"`}
type i3Workspace struct{Num int `json:"num"`;Name string `json:"name"`;Visible bool `json:"visible"`;Focused bool `json:"focused"`;Output string `json:"output"`;Urgent bool `json:"urgent"`}
type node struct{ID int64 `json:"id"`;Name string `json:"name"`;Type string `json:"type"`;Border string `json:"border"`;Layout string `json:"layout"`;Percent float64 `json:"percent"`;Rect rect `json:"rect"`;WindowRect rect `json:"window_rect"`;Focused bool `json:"focused"`;PID int `json:"pid"`;AppID *string `json:"app_id"`;WindowProperties struct{Class string `json:"class"`;Instance string `json:"instance"`;Title string `json:"title"`} `json:"window_properties"`;FullscreenMode int `json:"fullscreen_mode"`;Floating string `json:"floating"`;Nodes []node `json:"nodes"`;FloatingNodes []node `json:"floating_nodes"`}
func readState()(Snapshot,error){
	sock:=socketPath();c,e:=dial(sock);if e!=nil{return Snapshot{},e};defer c.close()
	var outs []i3Output;var wss []i3Workspace;var tree node
	for _,q:=range []struct{k uint32;v any;dst any}{{msgOutputs,nil,&outs},{msgWorkspaces,nil,&wss},{msgTree,nil,&tree}}{raw,err:=c.request(q.k,q.v);if err!=nil{return Snapshot{},err};if err=json.Unmarshal(raw,q.dst);err!=nil{return Snapshot{},err}}
	s:=Snapshot{Outputs:[]Output{},Workspaces:[]Workspace{},Windows:[]Window{}}
	for _,o:=range outs{if !o.Active{continue};x:=Output{Name:o.Name,Width:o.Rect.Width,Height:o.Rect.Height,Scale:1,Focused:false,ActiveWorkspace:o.CurrentWorkspace,Make:o.Make,Model:o.Model,X:o.Rect.X,Y:o.Rect.Y,Mode:fmt.Sprintf("%dx%d@%.0f",o.CurrentMode.Width,o.CurrentMode.Height,o.CurrentMode.Refresh)};for _,m:=range o.Modes{x.Modes=append(x.Modes,fmt.Sprintf("%dx%d@%.0f",m.Width,m.Height,m.Refresh))};s.Outputs=append(s.Outputs,x)}
	for _,w:=range wss{if w.Focused{s.FocusedOutput=w.Output};s.Workspaces=append(s.Workspaces,Workspace{ID:w.Name,Name:w.Name,Output:w.Output,Index:w.Num,Active:w.Focused,Windows:0})}
	for i:=range s.Outputs{s.Outputs[i].Focused=s.Outputs[i].Name==s.FocusedOutput}
	byWS:=map[string]int{};for _,w:=range s.Workspaces{byWS[w.ID]=w.Index}
	walkWindows(&tree,"","",s.Workspaces,&s.Windows)
	for i:=range s.Workspaces { s.Workspaces[i].Fullscreen = workspaceHasFullscreen(&tree,s.Workspaces[i].Name) }
	for i:=range s.Workspaces{for _,w:=range s.Windows{if w.Workspace==s.Workspaces[i].ID{s.Workspaces[i].Windows++}}}
	_ = byWS
	return s,nil
}
func workspaceHasFullscreen(n *node, workspace string) bool {
\tif n.Type == "workspace" && n.Name == workspace { return nodeHasFullscreen(n) }; for i := range n.Nodes { if workspaceHasFullscreen(&n.Nodes[i], workspace) { return true } }; for i := range n.FloatingNodes { if workspaceHasFullscreen(&n.FloatingNodes[i], workspace) { return true } }; return false
}
func nodeHasFullscreen(n *node) bool { if n.FullscreenMode != 0 { return true }; for i := range n.Nodes { if nodeHasFullscreen(&n.Nodes[i]) { return true } }; for i := range n.FloatingNodes { if nodeHasFullscreen(&n.FloatingNodes[i]) { return true } }; return false }
func walkWindows(n *node,ws,out string,wss []Workspace,windows *[]Window){
	if n.Type=="workspace"{ws=n.Name}
	if n.Type=="output"{out=n.Name}
	if n.WindowProperties.Title!=""||n.AppID!=nil||n.PID>0{
		app:=n.WindowProperties.Class;if n.AppID!=nil&&*n.AppID!=""{app=*n.AppID}
		title:=n.Name;if n.WindowProperties.Title!=""{title=n.WindowProperties.Title}
		if title!=""{*windows=append(*windows,Window{ID:strconv.FormatInt(n.ID,10),AppID:app,Title:title,Workspace:ws,Output:out,Pid:n.PID,FocusOrder:len(*windows),Floating:n.Floating=="user_on"||n.Floating=="auto_on",X:n.Rect.X,Y:n.Rect.Y,Width:n.Rect.Width,Height:n.Rect.Height})}
	}
	for i:=range n.Nodes{walkWindows(&n.Nodes[i],ws,out,wss,windows)}
	for i:=range n.FloatingNodes{walkWindows(&n.FloatingNodes[i],ws,out,wss,windows)}
}
