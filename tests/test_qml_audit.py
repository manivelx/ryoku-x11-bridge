from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "audit-rxb-qml.py"
SPEC = importlib.util.spec_from_file_location("audit_rxb_qml", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
AUDIT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(AUDIT)


class QMLAuditTests(unittest.TestCase):
    def test_reports_wayland_apis_by_separate_shell_root(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            repo = Path(temporary)
            shell = repo / "ryoku/shell/quickshell/shell"
            keys = repo / "ryoku/shell/quickshell/keys"
            hub = repo / "ryoku/hub/quickshell"
            picker = repo / "ryoku/shell/ryogami/picker/qml"
            shell.mkdir(parents=True)
            keys.mkdir(parents=True)
            hub.mkdir(parents=True)
            picker.mkdir(parents=True)
            (shell / "shell.qml").write_text(
                "import Quickshell.Wayland\\n"
                "PanelWindow { WlrLayershell.layer: WlrLayer.Top }\\n",
                encoding="utf-8",
            )
            (shell / "overview.qml").write_text(
                "ScreencopyView { }\\nToplevelManager { }\\n",
                encoding="utf-8",
            )
            (keys / "shell.qml").write_text(
                "import Quickshell.Wayland\\nWlSessionLock { }\\n",
                encoding="utf-8",
            )

            (hub / "Hub.qml").write_text(
                "import Quickshell.Wayland\\nWlrLayershell.layer: WlrLayer.Top\\n",
                encoding="utf-8",
            )
            (picker / "Picker.qml").write_text(
                "ScreencopyView { }\\n",
                encoding="utf-8",
            )

            report = AUDIT.build_report(repo)
            self.assertEqual(report["schema_version"], 1)
            self.assertEqual(report["roots"]["main_shell"]["qml_files"], 2)
            self.assertEqual(report["roots"]["key_hint_app"]["qml_files"], 1)
            self.assertEqual(report["roots"]["hub"]["qml_files"], 1)
            self.assertEqual(report["roots"]["ryogami_picker"]["qml_files"], 1)
            self.assertEqual(report["roots"]["main_shell"]["totals"]["wayland_import"], 1)
            self.assertEqual(report["roots"]["main_shell"]["totals"]["wlr_layershell"], 1)
            self.assertEqual(report["roots"]["main_shell"]["totals"]["screencopy_view"], 1)
            self.assertEqual(report["roots"]["main_shell"]["totals"]["toplevel_manager"], 1)
            self.assertEqual(report["roots"]["key_hint_app"]["totals"]["session_lock"], 1)
            self.assertEqual(report["roots"]["hub"]["totals"]["wlr_layershell"], 1)
            self.assertEqual(report["roots"]["ryogami_picker"]["totals"]["screencopy_view"], 1)
            self.assertIn("not proof", report["scope_note"])


if __name__ == "__main__":
    unittest.main()
