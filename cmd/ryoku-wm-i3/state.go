package main

import (
	"encoding/json"
	"fmt"
	"strconv"
)

type rect struct {
	X      int `json:"x"`
	Y      int `json:"y"`
	Width  int `json:"width"`
	Height int `json:"height"`
}
type mode struct {
	Width   int     `json:"width"`
	Height  int     `json:"height"`
	Refresh float64 `json:"refresh"`
}
type i3Output struct {
	Name             string `json:"name"`
	Active           bool   `json:"active"`
	Primary          bool   `json:"primary"`
	CurrentWorkspace string `json:"current_workspace"`
	Rect             rect   `json:"rect"`
	CurrentMode      mode   `json:"current_mode"`
	Modes            []mode `json:"modes"`
	Make             string `json:"make"`
	Model            string `json:"model"`
}
type i3Workspace struct {
	Num     int    `json:"num"`
	Name    string `json:"name"`
	Visible bool   `json:"visible"`
	Focused bool   `json:"focused"`
	Output  string `json:"output"`
	Urgent  bool   `json:"urgent"`
}
type node struct {
	ID               int64   `json:"id"`
	Name             string  `json:"name"`
	Type             string  `json:"type"`
	Border           string  `json:"border"`
	Layout           string  `json:"layout"`
	Percent          float64 `json:"percent"`
	Rect             rect    `json:"rect"`
	WindowRect       rect    `json:"window_rect"`
	Focused          bool    `json:"focused"`
	PID              int     `json:"pid"`
	AppID            *string `json:"app_id"`
	WindowProperties struct {
		Class    string `json:"class"`
		Instance string `json:"instance"`
		Title    string `json:"title"`
	} `json:"window_properties"`
	FullscreenMode int    `json:"fullscreen_mode"`
	Floating       string `json:"floating"`
	Nodes          []node `json:"nodes"`
	FloatingNodes  []node `json:"floating_nodes"`
}

func readState() (Snapshot, error) {
	return readStateForKinds(nil)
}

func readStateForKinds(want map[string]bool) (Snapshot, error) {
	all := len(want) == 0
	needOutputs := all || want["outputs"]
	needWorkspaces := all || want["workspaces"] || needOutputs || want["focus"]
	needTree := all || want["workspaces"] || want["windows"]

	socket := socketPath()
	connection, err := dial(socket)
	if err != nil {
		return Snapshot{}, err
	}
	defer connection.close()

	snapshot := Snapshot{
		Outputs:    []Output{},
		Workspaces: []Workspace{},
		Windows:    []Window{},
	}

	if needOutputs {
		var outputs []i3Output
		raw, err := connection.request(msgOutputs, nil)
		if err != nil {
			return Snapshot{}, err
		}
		if err := json.Unmarshal(raw, &outputs); err != nil {
			return Snapshot{}, err
		}
		for _, output := range outputs {
			if !output.Active {
				continue
			}
			row := Output{
				Name:            output.Name,
				Width:           output.Rect.Width,
				Height:          output.Rect.Height,
				Scale:           1,
				ActiveWorkspace: output.CurrentWorkspace,
				Make:            output.Make,
				Model:           output.Model,
				X:               output.Rect.X,
				Y:               output.Rect.Y,
				Mode:            fmt.Sprintf("%dx%d@%.0f", output.CurrentMode.Width, output.CurrentMode.Height, output.CurrentMode.Refresh),
			}
			for _, mode := range output.Modes {
				row.Modes = append(row.Modes, fmt.Sprintf("%dx%d@%.0f", mode.Width, mode.Height, mode.Refresh))
			}
			snapshot.Outputs = append(snapshot.Outputs, row)
		}
	}

	if needWorkspaces {
		var workspaces []i3Workspace
		raw, err := connection.request(msgWorkspaces, nil)
		if err != nil {
			return Snapshot{}, err
		}
		if err := json.Unmarshal(raw, &workspaces); err != nil {
			return Snapshot{}, err
		}
		ranks := map[string]int{}
		for _, workspace := range workspaces {
			if workspace.Focused {
				snapshot.FocusedOutput = workspace.Output
			}
			ranks[workspace.Output]++
			index := workspace.Num
			if index <= 0 {
				index = ranks[workspace.Output]
			}
			snapshot.Workspaces = append(snapshot.Workspaces, Workspace{
				ID:      workspace.Name,
				Name:    workspace.Name,
				Output:  workspace.Output,
				Index:   index,
				Active:  workspace.Visible,
				Windows: 0,
			})
		}
		for index := range snapshot.Outputs {
			snapshot.Outputs[index].Focused = snapshot.Outputs[index].Name == snapshot.FocusedOutput
		}
	}

	if needTree {
		var tree node
		raw, err := connection.request(msgTree, nil)
		if err != nil {
			return Snapshot{}, err
		}
		if err := json.Unmarshal(raw, &tree); err != nil {
			return Snapshot{}, err
		}
		var treeWindows []Window
		walkWindows(&tree, "", "", snapshot.Workspaces, &treeWindows)
		if all || want["windows"] {
			// Preserve the focused-window sentinel for shell consumers. i3 does
			// not expose authoritative focus history, so non-focused windows all
			// use 1 and CapFocusHistory remains unadvertised.
			for index := range treeWindows {
				if treeWindows[index].Focused {
					treeWindows[index].FocusOrder = 0
				} else {
					treeWindows[index].FocusOrder = 1
				}
			}
			snapshot.Windows = treeWindows
		}
		if want["workspaces"] || all {
			for index := range snapshot.Workspaces {
				snapshot.Workspaces[index].Fullscreen = workspaceHasFullscreen(&tree, snapshot.Workspaces[index].Name)
				for _, window := range treeWindows {
					if window.Workspace == snapshot.Workspaces[index].ID {
						snapshot.Workspaces[index].Windows++
					}
				}
			}
		}
	}
	return snapshot, nil
}

func workspaceHasFullscreen(n *node, workspace string) bool {
	if n.Type == "workspace" && n.Name == workspace {
		return nodeHasFullscreen(n)
	}
	for i := range n.Nodes {
		if workspaceHasFullscreen(&n.Nodes[i], workspace) {
			return true
		}
	}
	for i := range n.FloatingNodes {
		if workspaceHasFullscreen(&n.FloatingNodes[i], workspace) {
			return true
		}
	}
	return false
}
func nodeHasFullscreen(n *node) bool {
	if n.FullscreenMode != 0 {
		return true
	}
	for i := range n.Nodes {
		if nodeHasFullscreen(&n.Nodes[i]) {
			return true
		}
	}
	for i := range n.FloatingNodes {
		if nodeHasFullscreen(&n.FloatingNodes[i]) {
			return true
		}
	}
	return false
}
func walkWindows(n *node, ws, out string, wss []Workspace, windows *[]Window) {
	if n.Type == "workspace" {
		ws = n.Name
	}
	if n.Type == "output" {
		out = n.Name
	}
	if n.WindowProperties.Title != "" || n.WindowProperties.Class != "" || n.WindowProperties.Instance != "" || n.AppID != nil || n.PID > 0 {
		app := n.WindowProperties.Class
		if n.AppID != nil && *n.AppID != "" {
			app = *n.AppID
		}
		title := n.Name
		if n.WindowProperties.Title != "" {
			title = n.WindowProperties.Title
		}
		if title != "" {
			*windows = append(*windows, Window{ID: strconv.FormatInt(n.ID, 10), AppID: app, Title: title, Workspace: ws, Output: out, Pid: n.PID, Focused: n.Focused, Floating: n.Floating == "user_on" || n.Floating == "auto_on", X: n.Rect.X, Y: n.Rect.Y, Width: n.Rect.Width, Height: n.Rect.Height})
		}
	}
	for i := range n.Nodes {
		walkWindows(&n.Nodes[i], ws, out, wss, windows)
	}
	for i := range n.FloatingNodes {
		walkWindows(&n.FloatingNodes[i], ws, out, wss, windows)
	}
}
