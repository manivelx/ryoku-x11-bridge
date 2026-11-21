package main

type Caps struct {
	Name              string   `json:"name"`
	Version           string   `json:"version,omitempty"`
	Instance          string   `json:"instance,omitempty"`
	Supports          []string `json:"supports"`
	WorkspaceModel    string   `json:"workspaceModel"`
	ForeignAPIs       []any    `json:"foreignApis"`
	SettingDomains    []string `json:"settingDomains"`
	ConfigDir         string   `json:"configDir,omitempty"`
	ConfigEntry       string   `json:"configEntry,omitempty"`
	ConfigFiles       []string `json:"configFiles,omitempty"`
	GeneratedFiles    []string `json:"generatedFiles,omitempty"`
	Packages          []string `json:"packages,omitempty"`
	WindowRuleActions []string `json:"windowRuleActions,omitempty"`
}
type Output struct {
	Name            string   `json:"name"`
	Width           int      `json:"width"`
	Height          int      `json:"height"`
	Scale           float64  `json:"scale"`
	Focused         bool     `json:"focused,omitempty"`
	ActiveWorkspace string   `json:"activeWorkspace,omitempty"`
	Make            string   `json:"make,omitempty"`
	Model           string   `json:"model,omitempty"`
	PhysicalWidth   int      `json:"physicalWidth,omitempty"`
	Disabled        bool     `json:"disabled,omitempty"`
	X               int      `json:"x"`
	Y               int      `json:"y"`
	Mode            string   `json:"mode,omitempty"`
	Modes           []string `json:"modes,omitempty"`
}
type Workspace struct {
	ID         string `json:"id"`
	Name       string `json:"name"`
	Output     string `json:"output,omitempty"`
	Index      int    `json:"index,omitempty"`
	Active     bool   `json:"active,omitempty"`
	Windows    int    `json:"windows"`
	Fullscreen bool   `json:"fullscreen,omitempty"`
}
type Window struct {
	ID         string `json:"id"`
	AppID      string `json:"appId,omitempty"`
	Title      string `json:"title,omitempty"`
	Workspace  string `json:"workspace,omitempty"`
	Output     string `json:"output,omitempty"`
	Pid        int    `json:"pid,omitempty"`
	FocusOrder int    `json:"focusOrder"`
	Focused    bool   `json:"-"`
	Floating   bool   `json:"floating,omitempty"`
	X          int    `json:"x,omitempty"`
	Y          int    `json:"y,omitempty"`
	Width      int    `json:"width,omitempty"`
	Height     int    `json:"height,omitempty"`
}
type Snapshot struct {
	FocusedOutput   string      `json:"focusedOutput,omitempty"`
	Outputs         []Output    `json:"outputs,omitempty"`
	Workspaces      []Workspace `json:"workspaces,omitempty"`
	Windows         []Window    `json:"windows,omitempty"`
	KeyboardLayout  string      `json:"keyboardLayout,omitempty"`
	KeyboardLayouts []string    `json:"keyboardLayouts,omitempty"`
}
type Frame struct {
	Kind            string      `json:"kind"`
	FocusedOutput   string      `json:"focusedOutput,omitempty"`
	Outputs         []Output    `json:"outputs,omitempty"`
	Workspaces      []Workspace `json:"workspaces,omitempty"`
	Windows         []Window    `json:"windows,omitempty"`
	KeyboardLayout  string      `json:"keyboardLayout,omitempty"`
	KeyboardLayouts []string    `json:"keyboardLayouts,omitempty"`
}
type ApplyReport struct {
	Provider     string      `json:"provider"`
	Written      []string    `json:"written,omitempty"`
	Unhonored    []Unhonored `json:"unhonored,omitempty"`
	ReloadNeeded bool        `json:"reloadNeeded,omitempty"`
}
type Unhonored struct {
	Key    string `json:"key"`
	Reason string `json:"reason"`
}
