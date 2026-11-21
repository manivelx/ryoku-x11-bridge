package main

import (
	"errors"
	"fmt"
	"strconv"
	"strings"
)

func runAction(args []string) error {
	if len(args) == 0 {
		return errors.New("act: missing action id")
	}
	id, rest := args[0], args[1:]
	switch id {
	case "window.focus", "window.close", "window.fullscreen", "window.float":
		windowID, err := requiredWindowID(rest, 0)
		if err != nil {
			return fmt.Errorf("act %s: %w", id, err)
		}
		command := fmt.Sprintf("[con_id=%d] ", windowID)
		switch id {
		case "window.focus":
			command += "focus"
		case "window.close":
			command += "kill"
		case "window.fullscreen":
			command += "fullscreen toggle"
		case "window.float":
			command += "floating toggle"
		}
		return runCommand(command)

	case "app.focus":
		if len(rest) < 1 || strings.TrimSpace(rest[0]) == "" {
			return errors.New("act app.focus: missing app id")
		}
		snapshot, err := readState()
		if err != nil {
			return err
		}
		for _, window := range snapshot.Windows {
			if strings.EqualFold(window.AppID, rest[0]) {
				id, parseErr := strconv.ParseInt(window.ID, 10, 64)
				if parseErr == nil && id > 0 {
					return runCommand(fmt.Sprintf("[con_id=%d] focus", id))
				}
			}
		}
		return fmt.Errorf("no window found for app id %q", rest[0])

	case "session.exit":
		return runCommand("exit")

	case "workspace.focus":
		if len(rest) < 1 {
			return errors.New("act workspace.focus: missing workspace id")
		}
		return runCommand("workspace " + quoteWorkspace(rest[0]))

	case "workspace.cycle":
		delta := "1"
		if len(rest) > 0 {
			delta = rest[0]
		}
		direction, count, err := boundedDelta(delta)
		if err != nil {
			return err
		}
		for i := 0; i < count; i++ {
			if err := runCommand("workspace " + direction); err != nil {
				return err
			}
		}
		return nil

	case "workspace.moveToOutput":
		if len(rest) < 2 {
			return errors.New("act workspace.moveToOutput: expected workspace id and output")
		}
		return runCommand("workspace " + quoteWorkspace(rest[0]) +
			"; move workspace to output " + quoteToken(rest[1]))

	case "workspace.moveToOutputBy":
		if len(rest) < 1 || !validDirection(strings.ToLower(rest[0])) {
			return errors.New("act workspace.moveToOutputBy: expected left, right, up or down")
		}
		return runCommand("move workspace to output " + strings.ToLower(rest[0]))

	case "window.moveToWorkspaceBy":
		if len(rest) < 1 {
			return errors.New("act window.moveToWorkspaceBy: expected a non-zero workspace delta")
		}
		direction, count, err := boundedDelta(rest[0])
		if err != nil {
			return err
		}
		for i := 0; i < count; i++ {
			if err := runCommand("move container to workspace " + direction); err != nil {
				return err
			}
		}
		return nil

	case "window.summon":
		if len(rest) < 1 {
			return errors.New("act window.summon: expected exact window title")
		}
		snapshot, err := readState()
		if err != nil {
			return err
		}
		id, ok := findWindowIDByTitle(snapshot.Windows, rest[0])
		if !ok {
			return fmt.Errorf("no window found with title %q", rest[0])
		}
		windowID, err := strconv.ParseInt(id, 10, 64)
		if err != nil || windowID <= 0 {
			return fmt.Errorf("invalid window id %q", id)
		}
		return runCommand(fmt.Sprintf("[con_id=%d] move container to workspace current; [con_id=%d] focus", windowID, windowID))

	case "window.moveToWorkspace":
		if len(rest) < 2 {
			return errors.New("act window.moveToWorkspace: expected window id and workspace id")
		}
		windowID, err := requiredWindowID(rest, 0)
		if err != nil {
			return err
		}
		return runCommand(fmt.Sprintf("[con_id=%d] move container to workspace %s; [con_id=%d] focus",
			windowID, quoteWorkspace(rest[1]), windowID))

	case "window.focusDirection":
		if len(rest) < 1 || !validDirection(strings.ToLower(rest[0])) {
			return errors.New("act window.focusDirection: expected left, right, up or down")
		}
		return runCommand("focus " + strings.ToLower(rest[0]))

	case "window.moveBy":
		if len(rest) < 1 || !validDirection(strings.ToLower(rest[0])) {
			return errors.New("act window.moveBy: expected left, right, up or down")
		}
		return moveFocusedBy(strings.ToLower(rest[0]))

	case "window.resizeBy":
		if len(rest) < 1 {
			return errors.New("act window.resizeBy: expected narrower, wider, shorter or taller")
		}
		var command string
		switch rest[0] {
		case "wider":
			command = "resize grow width 10 px or 10 ppt"
		case "narrower":
			command = "resize shrink width 10 px or 10 ppt"
		case "taller":
			command = "resize grow height 10 px or 10 ppt"
		case "shorter":
			command = "resize shrink height 10 px or 10 ppt"
		default:
			return fmt.Errorf("act window.resizeBy: invalid resize direction %q", rest[0])
		}
		return runCommand(command)

	case "window.presetHeight":
		first := false
		if len(rest) > 0 {
			if len(rest) != 1 || rest[0] != "first" {
				return errors.New("act window.presetHeight: expected no argument or 'first'")
			}
			first = true
		}
		return resizeFocusedPreset("height", first)

	case "window.presetWidth":
		if len(rest) != 0 {
			return errors.New("act window.presetWidth: takes no arguments")
		}
		return resizeFocusedPreset("width", false)

	case "window.center":
		return centerFocusedWindow()

	case "window.maximize":
		return maximizeFocusedWindow()

	case "window.place":
		return placeWindow(rest)

	case "window.moveToOutputBy":
		if len(rest) < 1 || !validDirection(strings.ToLower(rest[0])) {
			return errors.New("act window.moveToOutputBy: expected left, right, up or down")
		}
		return runCommand("move container to output " + strings.ToLower(rest[0]))

	case "workspace.layout":
		if len(rest) < 2 {
			return errors.New("act workspace.layout: expected workspace id and layout")
		}
		layout := strings.ToLower(strings.TrimSpace(rest[1]))
		switch layout {
		case "default", "tabbed", "stacking", "splitv", "splith":
			// Supported i3 workspace layouts.
		case "toggle":
			layout = "toggle split"
		default:
			return fmt.Errorf("act workspace.layout: unsupported layout %q", layout)
		}
		return runCommand("workspace " + quoteWorkspace(rest[0]) + "; layout " + layout)

	case "config.reload":
		return runCommand("reload")

	default:
		return fmt.Errorf("unsupported or unknown action %q", id)
	}
}

func requiredWindowID(args []string, index int) (int64, error) {
	if index >= len(args) || strings.TrimSpace(args[index]) == "" {
		return 0, errors.New("missing window id")
	}
	id, err := strconv.ParseInt(args[index], 10, 64)
	if err != nil || id <= 0 {
		return 0, fmt.Errorf("invalid window id %q", args[index])
	}
	return id, nil
}

func focusedWindow(snapshot Snapshot) (Window, error) {
	for _, window := range snapshot.Windows {
		if window.Focused {
			return window, nil
		}
	}
	return Window{}, errors.New("no focused window in i3 tree")
}

func outputForWindow(snapshot Snapshot, window Window) (Output, error) {
	for _, output := range snapshot.Outputs {
		if output.Name == window.Output {
			return output, nil
		}
	}
	return Output{}, fmt.Errorf("output %q for window %q is not active", window.Output, window.ID)
}

func moveFocusedBy(direction string) error {
	snapshot, err := readState()
	if err != nil {
		return err
	}
	window, err := focusedWindow(snapshot)
	if err != nil {
		return err
	}
	id, err := requiredWindowID([]string{window.ID}, 0)
	if err != nil {
		return err
	}
	x, y := window.X, window.Y
	const step = 40
	switch direction {
	case "left":
		x -= step
	case "right":
		x += step
	case "up":
		y -= step
	case "down":
		y += step
	}
	return runCommand(fmt.Sprintf("[con_id=%d] floating enable; [con_id=%d] move position %d px %d px", id, id, x, y))
}

func resizeFocusedPreset(axis string, first bool) error {
	snapshot, err := readState()
	if err != nil {
		return err
	}
	window, err := focusedWindow(snapshot)
	if err != nil {
		return err
	}
	output, err := outputForWindow(snapshot, window)
	if err != nil {
		return err
	}
	id, err := requiredWindowID([]string{window.ID}, 0)
	if err != nil {
		return err
	}
	ratios := []int{50, 66, 75, 90}
	current, total := window.Width, output.Width
	if axis == "height" {
		current, total = window.Height, output.Height
	}
	if total <= 0 {
		return errors.New("i3 output has no usable geometry")
	}
	target := ratios[0]
	if !first {
		nearest := 0
		best := total + 1
		for i, ratio := range ratios {
			delta := current - total*ratio/100
			if delta < 0 {
				delta = -delta
			}
			if delta < best {
				best, nearest = delta, i
			}
		}
		target = ratios[(nearest+1)%len(ratios)]
	}
	size := total * target / 100
	width, height := window.Width, window.Height
	if axis == "height" {
		height = size
	} else {
		width = size
	}
	return runCommand(fmt.Sprintf("[con_id=%d] floating enable; [con_id=%d] resize set width %d px height %d px",
		id, id, width, height))
}

func centerFocusedWindow() error {
	snapshot, err := readState()
	if err != nil {
		return err
	}
	window, err := focusedWindow(snapshot)
	if err != nil {
		return err
	}
	output, err := outputForWindow(snapshot, window)
	if err != nil {
		return err
	}
	id, err := requiredWindowID([]string{window.ID}, 0)
	if err != nil {
		return err
	}
	x := output.X + (output.Width-window.Width)/2
	y := output.Y + (output.Height-window.Height)/2
	return runCommand(fmt.Sprintf("[con_id=%d] floating enable; [con_id=%d] move position %d px %d px",
		id, id, x, y))
}

func maximizeFocusedWindow() error {
	snapshot, err := readState()
	if err != nil {
		return err
	}
	window, err := focusedWindow(snapshot)
	if err != nil {
		return err
	}
	output, err := outputForWindow(snapshot, window)
	if err != nil {
		return err
	}
	id, err := requiredWindowID([]string{window.ID}, 0)
	if err != nil {
		return err
	}
	return runCommand(fmt.Sprintf("[con_id=%d] floating enable; [con_id=%d] move position %d px %d px; [con_id=%d] resize set width %d px height %d px",
		id, id, output.X, output.Y, id, output.Width, output.Height))
}

func placeWindow(args []string) error {
	if len(args) < 6 {
		return errors.New("act window.place: expected window id, x, y, width, height and output name")
	}
	id, err := requiredWindowID(args, 0)
	if err != nil {
		return err
	}
	values := make([]int, 4)
	names := []string{"x", "y", "width", "height"}
	for i := range values {
		values[i], err = strconv.Atoi(args[i+1])
		if err != nil {
			return fmt.Errorf("act window.place: %s must be an integer", names[i])
		}
	}
	x, y, width, height, outputName := values[0], values[1], values[2], values[3], args[5]
	if width <= 0 || height <= 0 || strings.TrimSpace(outputName) == "" {
		return errors.New("act window.place: width/height and output name must be valid")
	}
	snapshot, err := readState()
	if err != nil {
		return err
	}
	var output Output
	found := false
	for _, candidate := range snapshot.Outputs {
		if candidate.Name == outputName {
			output, found = candidate, true
			break
		}
	}
	if !found {
		return fmt.Errorf("act window.place: output %q is not active", outputName)
	}
	globalX, globalY := output.X+x, output.Y+y
	return runCommand(fmt.Sprintf("[con_id=%d] floating enable; [con_id=%d] move container to output %s; [con_id=%d] resize set width %d px height %d px; [con_id=%d] move position %d px %d px",
		id, id, quoteToken(outputName), id, width, height, id, globalX, globalY))
}
