import importlib.util
import pathlib
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "scripts" / "apply-upstream-overlay.py"
SPEC = importlib.util.spec_from_file_location("rxb_overlay", SCRIPT)
OVERLAY = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(OVERLAY)


class X11PanelOverlayTests(unittest.TestCase):
    def test_static_and_dynamic_layer_mapping(self):
        self.assertEqual(OVERLAY._convert_x11_layer("WlrLayer.Overlay"), "true")
        self.assertEqual(
            OVERLAY._convert_x11_layer(
                "dock.stageEditing ? WlrLayer.Overlay : (dock.autohide ? WlrLayer.Top : WlrLayer.Bottom)"
            ),
            "dock.stageEditing ? true : (dock.autohide ? true : false)",
        )

    def test_dynamic_layer_enum_is_compared_not_coerced(self):
        self.assertEqual(
            OVERLAY._convert_x11_layer("shown ? shownLayer : WlrLayer.Bottom"),
            "shown ? (shownLayer === WlrLayer.Top || shownLayer === WlrLayer.Overlay) : false",
        )

    def test_keyboard_focus_mapping(self):
        self.assertEqual(
            OVERLAY._convert_x11_focus(
                "root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None"
            ),
            "root.open ? true : false",
        )
        self.assertEqual(
            OVERLAY._convert_x11_focus(
                "shown ? shownKeyboardFocus : WlrKeyboardFocus.None"
            ),
            "shown ? !!shownKeyboardFocus : false",
        )

    def test_wm_adapter_keeps_x11_windows_without_wayland_capture_handles(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            qml = root / "ryoku" / "ui" / "Singletons" / "Wm.qml"
            qml.parent.mkdir(parents=True)
            qml.write_text(
                "import Quickshell.WindowManager\n"
                "import Quickshell.Wayland\n"
                "    // Bound at declaration so the Wayland registry binds early; the lists fill in\n"
                "    // asynchronously after connect.\n"
                "    readonly property var _windowsets: WindowManager.windowsets\n"
                "    property var _toplevelModel: ToplevelManager.toplevels\n"
                "    readonly property var toplevels: root._toplevelModel ? root._toplevelModel.values : []\n"
                "            const tl = (arr && at < arr.length) ? arr[at] : null;\n"
                "                id: s.name,\n"
                "                name: s.name,\n"
                "                active: s.active === true,\n"
                "                urgent: s.urgent === true,\n"
                "                canActivate: s.canActivate === true,\n"
                "                windows: 0,\n"
                "                occupied: false,\n"
                "                fullscreen: false,\n"
                "                special: false,\n"
                '                output: "",\n'
                '                layout: ""'
            )
            OVERLAY.patch_wm_qml(root)
            result = qml.read_text()
            self.assertIn("import Quickshell.I3", result)
            self.assertIn("toplevel: null", result)
            self.assertIn("const tl = entry ? (entry.toplevel ?? entry) : null;", result)

    def test_panel_properties_are_rewritten_for_x11(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            qml = root / "Panel.qml"
            qml.write_text(
                'PanelWindow {\n'
                '    WlrLayershell.namespace: "rxb-test"\n'
                '    WlrLayershell.layer: WlrLayer.Overlay\n'
                '    WlrLayershell.keyboardFocus: (root.open)\n'
                '        ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None\n'
                '}\n'
            )
            OVERLAY.patch_x11_panel_properties(root)
            result = qml.read_text()
            self.assertIn("aboveWindows: true", result)
            self.assertIn("focusable: (root.open) ? true : false", result)
            self.assertNotIn("WlrLayershell.", result)


if __name__ == "__main__":
    unittest.main()
