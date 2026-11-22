package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

type keybind struct {
	Keys    string `json:"keys"`
	Action  string `json:"action"`
	Value   string `json:"value"`
	Release bool   `json:"release,omitempty"`
}

type keybindStore struct {
	Keybinds        []keybind         `json:"keybinds"`
	KeybindRebinds  map[string]string `json:"keybindRebinds"`
	Unbinds         []string          `json:"unbinds"`
	KeybindDisabled []string          `json:"keybindDisabled"`
}

type neutralKeybindStore struct {
	Desktop keybindStore `json:"desktop"`
}

const i3NativeBinding = "__RXB_I3_NATIVE__"

type resolvedI3Bind struct {
	chord   string
	command string
	id      string
	release bool
}

// readKeybindStore reads the same neutral desktop.json document consumed by
// upstream WM providers. Missing files mean the upstream defaults, never a
// locally invented shortcut set.
func readKeybindStore(path string) (keybindStore, error) {
	if path == "" {
		root := os.Getenv("RYOKU_CONFIG_HOME")
		if root == "" {
			return keybindStore{}, nil
		}
		path = filepath.Join(root, "desktop.json")
	}
	info, err := os.Stat(path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return keybindStore{}, nil
		}
		return keybindStore{}, err
	}
	if info.IsDir() {
		path = filepath.Join(path, "desktop.json")
	}
	data, err := os.ReadFile(path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return keybindStore{}, nil
		}
		return keybindStore{}, err
	}
	var neutral neutralKeybindStore
	if err := json.Unmarshal(data, &neutral); err != nil {
		return keybindStore{}, fmt.Errorf("decode neutral desktop settings: %w", err)
	}
	return neutral.Desktop, nil
}

func i3Chord(raw string) (string, bool) {
	parts := strings.Split(raw, "+")
	if len(parts) == 0 {
		return "", false
	}
	out := make([]string, 0, len(parts))
	for _, token := range parts {
		token = strings.TrimSpace(token)
		if token == "" || strings.ContainsAny(token, "\r\n") {
			return "", false
		}
		switch strings.ToUpper(token) {
		case "SUPER", "MOD4":
			token = "Mod4"
		case "ALT", "MOD1":
			token = "Mod1"
		case "CTRL", "CONTROL":
			token = "Control"
		case "SHIFT":
			token = "Shift"
		case "SPACE":
			token = "space"
		case "ENTER", "RETURN":
			token = "Return"
		case "ESC", "ESCAPE":
			token = "Escape"
		case "PAGEUP":
			token = "Prior"
		case "PAGEDOWN":
			token = "Next"
		case "MOUSE_UP":
			token = "button4"
		case "MOUSE_DOWN":
			token = "button5"
		}
		if strings.HasPrefix(strings.ToLower(token), "mouse:") {
			switch strings.TrimPrefix(strings.ToLower(token), "mouse:") {
			case "272":
				token = "button1"
			case "273":
				token = "button3"
			case "274":
				token = "button2"
			case "275":
				token = "button4"
			case "276":
				token = "button5"
			default:
				return "", false
			}
		}
		out = append(out, token)
	}
	return strings.Join(out, "+"), true
}

func shellExec(command string) string {
	return "exec --no-startup-id " + strconv.Quote(command)
}

func actExec(id string, args ...string) string {
	parts := []string{"ryoku-wm-i3", "act", id}
	parts = append(parts, args...)
	return shellExec(strings.Join(parts, " "))
}

// i3Action maps upstream semantic IDs to i3 commands. A blank command must
// always carry a human-readable reason; untranslated behaviours remain visible
// in the Hub and are never silently discarded.
func i3Action(id string, workspace int) (string, string) {
	switch id {
	case "window.close":
		return actExec("window.close"), ""
	case "window.fullscreen":
		return actExec("window.fullscreen"), ""
	case "window.float":
		return actExec("window.float"), ""
	case "window.pin":
		return "sticky toggle", ""
	case "window.presetHeight":
		return "", "i3 cannot preserve Ryoku's tiled preset-height behaviour without changing the window's floating state."
	case "column.tabbed":
		return "layout toggle tabbed split", ""
	case "column.center":
		return "", "i3 cannot center a tiled column without converting the window to floating."
	case "focus.left", "focus.right", "focus.up", "focus.down":
		return "focus " + strings.TrimPrefix(id, "focus."), ""
	case "move.left", "move.right", "move.up", "move.down":
		return "move " + strings.TrimPrefix(id, "move."), ""
	case "resize.narrower":
		return actExec("window.resizeBy", "narrower"), ""
	case "resize.wider":
		return actExec("window.resizeBy", "wider"), ""
	case "resize.shorter":
		return actExec("window.resizeBy", "shorter"), ""
	case "resize.taller":
		return actExec("window.resizeBy", "taller"), ""
	case "resize.grow", "resize.shrink":
		return "", "i3 has incremental resize commands but no equivalent to Ryoku's preset-width cycling."
	case "workspace.focus", "workspace.focus.numpad":
		return fmt.Sprintf("workspace number %d", workspace), ""
	case "workspace.moveWindow", "workspace.moveWindow.numpad":
		return fmt.Sprintf("move container to workspace number %d", workspace), ""
	case "workspace.moveWindowSilent", "workspace.moveWindowSilent.numpad":
		return fmt.Sprintf("move container to workspace number %d", workspace), ""
	case "workspace.prev", "workspace.prevWheel":
		return "workspace prev", ""
	case "workspace.next", "workspace.nextWheel":
		return "workspace next", ""
	case "workspace.moveWindowPrev":
		return "move container to workspace prev", ""
	case "workspace.moveWindowNext":
		return "move container to workspace next", ""
	case "workspace.hideWindow":
		return "move scratchpad", ""
	case "workspace.scratchpad":
		return "scratchpad show", ""
	case "display.focus.left", "display.focus.right", "display.focus.up", "display.focus.down":
		return "focus output " + strings.TrimPrefix(id, "display.focus."), ""
	case "display.moveWindow.left", "display.moveWindow.right", "display.moveWindow.up", "display.moveWindow.down":
		return "move container to output " + strings.TrimPrefix(id, "display.moveWindow."), ""
	case "display.moveWorkspace.left", "display.moveWorkspace.right", "display.moveWorkspace.up", "display.moveWorkspace.down":
		return "move workspace to output " + strings.TrimPrefix(id, "display.moveWorkspace."), ""
	case "app.terminal":
		return shellExec("ryoku-app terminal"), ""
	case "app.files":
		return shellExec("ryoku-app files"), ""
	case "app.browser":
		return shellExec("ryoku-app browser"), ""
	case "app.editor":
		return shellExec("ryoku-app editor"), ""
	case "app.notes":
		return shellExec("ryoku-app notes"), ""
	case "app.yazi":
		return shellExec("kitty -e yazi"), ""
	case "app.ryotunes":
		return shellExec("ryotunes"), ""
	case "shell.launcher":
		return shellExec("ryoku-shell launcher"), ""
	case "shell.ask":
		return shellExec("ryoku-shell ask"), ""
	case "shell.cheatsheet":
		return shellExec("ryoku-shell cheatsheet"), ""
	case "shell.gamebar":
		return shellExec("ryoku-shell gamebar"), ""
	case "shell.lock":
		return shellExec("ryoku-x11-lock"), ""
	case "shell.quicksettings":
		return shellExec("ryoku-shell quicksettings"), ""
	case "shell.wallpaper":
		return shellExec("ryogami wallpaper ui"), ""
	case "shell.wallpaperRandom":
		return shellExec("ryogami wallpaper random"), ""
	case "shell.clipboard":
		return shellExec("ryoku-shell clipboard"), ""
	case "shell.visualizer":
		return shellExec("ryoku-shell visualizer"), ""
	case "shell.visualizerOverlay":
		return shellExec("ryoku-shell visualizer-overlay"), ""
	case "shell.visualizerPlace":
		return shellExec("ryoku-shell visualizer-place"), ""
	case "shell.voice":
		return shellExec("ryoku-shell voice"), ""
	case "shell.settings":
		return shellExec("ryoku-shell settings"), ""
	case "shell.stageEditor":
		return shellExec("ryoku-shell hub open widgets"), ""
	case "shell.screenshot", "shell.screenshotPrint":
		return shellExec("ryoku-cmd-ryoshot"), ""
	case "shell.screenshotMonitor":
		return shellExec("RYOSHOT_MODE=monitor ryoku-cmd-ryoshot"), ""
	case "shell.restartAudio":
		return shellExec("ryoku-restart-audio"), ""
	case "media.volumeUp", "media.volumeDown", "media.mute", "media.micMute",
		"media.play", "media.pause", "media.next", "media.prev":
		return "", "X11 secure-lock sessions cannot preserve Ryoku's allow-while-locked media-key contract; this action remains visible but is not bound."
	case "hardware.brightnessUp":
		return shellExec("ryoku-cmd-brightness +5"), ""
	case "hardware.brightnessDown":
		return shellExec("ryoku-cmd-brightness -5"), ""
	case "mouse.move", "mouse.resize":
		// payload/ryoku-x11/config sets floating_modifier $mod; i3 handles
		// the original Mod+mouse move/resize gestures natively.
		return i3NativeBinding, ""
	case "window.resize":
		return "", "The original Ryoku resize submap has no faithful i3 mode translation yet."
	case "window.focusPrevious":
		return "focus prev", ""
	case "column.first", "column.last":
		return "", "i3 does not expose a reliable first/last column action with the same semantics."
	case "column.mergeLeft", "column.mergeRight":
		return "", "i3 has no equivalent to Ryoku's adjacent-column merge/consume behaviour."
	case "resize.resetHeight":
		return "", "i3 cannot reset a tiled window to Ryoku's compositor-independent preset height."
	case "workspace.reorderUp", "workspace.reorderDown":
		return "", "i3 cannot reorder dynamic workspaces with the same semantics as the original Ryoku action."
	case "workspace.overview", "workspace.overviewDesktops":
		return "", "The original Ryoku overview/desktop-block interaction has no faithful i3 equivalent."
	case "display.cycle":
		return "", "Display cycling is not implemented; use the existing X11 display settings workflow."
	case "shell.rashin", "shell.ryovm", "shell.colorPicker", "shell.inhibitShortcuts":
		return "", "This action depends on a Wayland-only helper or compositor shortcut-inhibition API and is not available in RXB X11."
	case "hardware.touchpadToggle", "hardware.touchpadOn", "hardware.touchpadOff":
		return "", "Touchpad control has not been ported to the X11 input provider."
	default:
		return "", "This original Ryoku action has not yet been translated to i3."
	}
}

func i3Rebindable(cb CatalogBind) bool {
	for _, token := range strings.Split(cb.Chord, " + ") {
		if strings.HasPrefix(token, "mouse") || strings.HasPrefix(token, "XF86") {
			return false
		}
	}
	return true
}

func expandCatalogueChord(cb CatalogBind, index int) string {
	chord := cb.Chord
	if cb.Family {
		digit := index % 10
		if cb.Numpad {
			chord = strings.ReplaceAll(chord, "{n}", fmt.Sprintf("KP_%d", digit))
		} else {
			chord = strings.ReplaceAll(chord, "{n}", strconv.Itoa(digit))
		}
	}
	return chord
}

func effectiveCatalogueChord(chord string, rebinds map[string]string) string {
	if value := strings.TrimSpace(rebinds[chord]); value != "" {
		return value
	}
	return chord
}

func effectiveFamilyChord(chord string, index int, rebinds map[string]string) string {
	familyKey := strings.ReplaceAll(chord, strconv.Itoa(index%10), "{n}")
	if value := strings.TrimSpace(rebinds[familyKey]); value != "" {
		return strings.ReplaceAll(value, "{n}", strconv.Itoa(index%10))
	}
	return effectiveCatalogueChord(chord, rebinds)
}

func resolveShippedBinds(store keybindStore) ([]resolvedI3Bind, []bindRow, []Unhonored) {
	catalogue := ShippedBinds()
	disabled := map[string]bool{}
	for _, chord := range append(append([]string{}, store.Unbinds...), store.KeybindDisabled...) {
		disabled[strings.TrimSpace(chord)] = true
	}
	rows := make([]bindRow, 0, len(catalogue)+len(store.Keybinds))
	binds := make([]resolvedI3Bind, 0, len(catalogue)+len(store.Keybinds))
	var rebound, static []resolvedI3Bind
	var report []Unhonored
	claimed := map[string]bool{}

	// Upstream precedence is custom > rebound default > static default.
	for index, custom := range store.Keybinds {
		chord, ok := i3Chord(custom.Keys)
		if !ok {
			reason := fmt.Sprintf("i3 cannot bind the custom chord %q.", custom.Keys)
			rows = append(rows, bindRow{ID: fmt.Sprintf("custom.%d", index), Category: "Custom", Label: custom.Action, Default: custom.Keys, Chord: custom.Keys, Kind: "custom", Unhonored: reason})
			report = append(report, Unhonored{Key: fmt.Sprintf("desktop.keybinds[%d]", index), Reason: reason})
			continue
		}
		command, reason := customI3Action(custom)
		row := bindRow{ID: fmt.Sprintf("custom.%d", index), Category: "Custom", Label: custom.Action, Keys: strings.Split(chord, "+"), Default: custom.Keys, Chord: chord, Kind: "custom", Rebindable: false, Unhonored: reason}
		rows = append(rows, row)
		if reason != "" {
			report = append(report, Unhonored{Key: fmt.Sprintf("desktop.keybinds[%d]", index), Reason: reason})
			continue
		}
		if command != "" {
			binds = append(binds, resolvedI3Bind{chord: chord, command: command, id: row.ID, release: custom.Release})
			claimed[chord] = true
		}
	}

	for _, cb := range catalogue {
		defaultChord := cb.Chord
		effective := effectiveCatalogueChord(defaultChord, store.KeybindRebinds)
		row := bindRow{
			ID: cb.ID, Category: cb.Category, Label: cb.Label, Hint: cb.Hint,
			Keys: DisplayKeys(effective), Default: defaultChord, Chord: effective,
			Kind: string(cb.Kind), Rebindable: i3Rebindable(cb), Locked: cb.Locked,
			Disabled: disabled[defaultChord],
		}
		if row.Disabled {
			row.Keys = nil
			row.Chord = ""
		}
		var command, reason string
		if !row.Disabled {
			command, reason = i3Action(cb.ID, 1)
			if missing := cb.Missing(HasProgram); missing != "" {
				command, reason = "", missing
			}
			if reason == "" && command == "" && !cb.Family {
				reason = "No i3 action was generated for this original Ryoku action."
			}
			if reason != "" {
				row.Unhonored = reason
				report = append(report, Unhonored{Key: cb.ID, Reason: reason})
			}
		}
		rows = append(rows, row)
		if row.Disabled || reason != "" || command == i3NativeBinding {
			continue
		}

		if cb.Family {
			for n := 1; n <= 10; n++ {
				original := expandCatalogueChord(cb, n)
				if disabled[original] {
					continue
				}
				effectiveChord := effectiveFamilyChord(original, n, store.KeybindRebinds)
				chord, ok := i3Chord(effectiveChord)
				if !ok {
					report = append(report, Unhonored{Key: cb.ID, Reason: fmt.Sprintf("i3 cannot bind the effective chord %q.", effectiveChord)})
					continue
				}
				action, why := i3Action(cb.ID, n%10)
				if why != "" || action == "" || action == i3NativeBinding {
					continue
				}
				candidate := resolvedI3Bind{chord: chord, command: action, id: cb.ID}
				if effectiveChord != original {
					rebound = append(rebound, candidate)
				} else {
					static = append(static, candidate)
				}
			}
			continue
		}

		chord, ok := i3Chord(effective)
		if !ok {
			row.Unhonored = fmt.Sprintf("i3 cannot bind the chord %q.", effective)
			report = append(report, Unhonored{Key: cb.ID, Reason: row.Unhonored})
			continue
		}
		candidate := resolvedI3Bind{chord: chord, command: command, id: cb.ID}
		if effective != defaultChord {
			rebound = append(rebound, candidate)
		} else {
			static = append(static, candidate)
		}
	}

	claim := func(candidates []resolvedI3Bind) {
		for _, candidate := range candidates {
			if claimed[candidate.chord] {
				continue
			}
			binds = append(binds, candidate)
			claimed[candidate.chord] = true
		}
	}
	claim(rebound)
	claim(static)
	return binds, rows, report
}

func customI3Action(custom keybind) (string, string) {
	switch custom.Action {
	case "exec", "":
		if strings.TrimSpace(custom.Value) == "" {
			return "", "Custom exec action has an empty command."
		}
		return shellExec(custom.Value), ""
	case "close":
		return actExec("window.close"), ""
	case "fullscreen":
		return actExec("window.fullscreen"), ""
	case "togglefloating":
		return actExec("window.float"), ""
	case "workspace":
		n, err := strconv.Atoi(strings.TrimSpace(custom.Value))
		if err != nil || n < 1 || n > 1000 {
			return "", fmt.Sprintf("i3 workspace action requires a positive workspace number, not %q.", custom.Value)
		}
		return fmt.Sprintf("workspace number %d", n), ""
	case "movetoworkspace", "movetoworkspacesilent":
		n, err := strconv.Atoi(strings.TrimSpace(custom.Value))
		if err != nil || n < 1 || n > 1000 {
			return "", fmt.Sprintf("i3 move-to-workspace action requires a positive workspace number, not %q.", custom.Value)
		}
		return fmt.Sprintf("move container to workspace number %d", n), ""
	default:
		return "", fmt.Sprintf("i3 does not support the custom Ryoku action %q.", custom.Action)
	}
}

func renderGeneratedI3Config(binds []resolvedI3Bind) string {
	var builder strings.Builder
	builder.WriteString("# Generated by ryoku-wm-i3 from the pinned upstream Ryoku keybinding catalogue.\n")
	builder.WriteString("# Do not edit: use Ryoku Settings/Hub; place local additions in user.conf.\n")
	for _, bind := range binds {
		builder.WriteString("bindsym ")
		if bind.release {
			builder.WriteString("--release ")
		}
		builder.WriteString(bind.chord)
		builder.WriteString(" ")
		builder.WriteString(bind.command)
		builder.WriteString(" # RXB:")
		builder.WriteString(bind.id)
		builder.WriteByte('\n')
	}
	return builder.String()
}

func runKeybindApply(args []string) error {
	storePath := ""
	preview := false
	for _, arg := range args {
		if arg == "--preview" {
			preview = true
		} else if storePath == "" {
			storePath = arg
		}
	}
	store, err := readKeybindStore(storePath)
	if err != nil {
		return fmt.Errorf("apply: %w", err)
	}
	binds, _, unhonored := resolveShippedBinds(store)
	unhonored = append(unhonored,
		Unhonored{Key: "desktop.windowRules", Reason: "Window rules are not yet translated into i3 criteria."},
		Unhonored{Key: "desktop.input", Reason: "Input settings remain managed by the existing X11 input configuration."},
		Unhonored{Key: "desktop.appearance", Reason: "Provider-specific appearance settings are not generated from the neutral store yet."},
		Unhonored{Key: "desktop.autostart", Reason: "Autostart settings are not yet applied by the i3 provider."},
	)
	report := ApplyReport{Provider: "i3", Unhonored: unhonored, ReloadNeeded: len(binds) > 0}
	if preview {
		return json.NewEncoder(out).Encode(report)
	}
	configHome := os.Getenv("XDG_CONFIG_HOME")
	if configHome == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return err
		}
		configHome = filepath.Join(home, ".config")
	}
	configDir := filepath.Join(configHome, "ryoku-x11")
	if info, err := os.Lstat(configDir); err == nil && info.Mode()&os.ModeSymlink != 0 {
		return fmt.Errorf("apply: refusing symlinked RXB config directory %s", configDir)
	}
	if err := os.MkdirAll(configDir, 0o700); err != nil {
		return err
	}
	target := filepath.Join(configDir, "generated.conf")
	if info, err := os.Lstat(target); err == nil && info.Mode()&os.ModeSymlink != 0 {
		return fmt.Errorf("apply: refusing symlinked generated config %s", target)
	}
	tmp, err := os.CreateTemp(configDir, ".generated.conf.*")
	if err != nil {
		return err
	}
	tmpName := tmp.Name()
	defer os.Remove(tmpName)
	if err := tmp.Chmod(0o600); err != nil {
		tmp.Close()
		return err
	}
	if _, err := tmp.WriteString(renderGeneratedI3Config(binds)); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Sync(); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	if err := os.Rename(tmpName, target); err != nil {
		return err
	}
	report.Written = []string{target}
	report.ReloadNeeded = true
	if socketPath() != "" {
		if err := runCommand("reload"); err != nil {
			return fmt.Errorf("apply: generated keybindings were written but i3 reload failed: %w", err)
		}
		report.ReloadNeeded = false
	}
	return json.NewEncoder(out).Encode(report)
}
