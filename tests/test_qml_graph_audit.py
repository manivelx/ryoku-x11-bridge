import importlib.util
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "audit-rxb-qml-graph.py"
SPEC = importlib.util.spec_from_file_location("qml_graph_audit", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(MODULE)


class QmlGraphAuditTests(unittest.TestCase):
    def test_follows_local_imports_and_component_types_but_excludes_unreachable(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "shell"
            parts = root / "parts"
            parts.mkdir(parents=True)
            (root / "shell.qml").write_text(
                'import "parts"\nShellRoot { Widget { } }\n', encoding="utf-8"
            )
            (parts / "Widget.qml").write_text(
                'import Quickshell.Wayland\nPanel { WlrLayershell.layer: 1 }\n',
                encoding="utf-8",
            )
            (parts / "Unused.qml").write_text(
                'import Quickshell.Wayland\nWlSessionLock { }\n', encoding="utf-8"
            )
            report = MODULE.graph(root, root / "shell.qml")
            self.assertEqual(
                report["reachable_qml_files"], ["parts/Widget.qml", "shell.qml"]
            )
            self.assertEqual(report["api_occurrences"]["Quickshell.Wayland"], 1)
            self.assertEqual(report["api_occurrences"]["WlrLayershell"], 1)
            self.assertEqual(report["api_occurrences"]["WlSessionLock"], 0)
            self.assertEqual(report["unreachable_qml_files"], ["parts/Unused.qml"])

    def test_follows_qmldir_module_imports(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "shell"
            services = root / "services"
            services.mkdir(parents=True)
            (services / "qmldir").write_text("module shell.services\n", encoding="utf-8")
            (root / "shell.qml").write_text(
                "import shell.services\nAudioService { }\n", encoding="utf-8"
            )
            (services / "AudioService.qml").write_text(
                "QtObject { property bool ready: true }\n", encoding="utf-8"
            )
            report = MODULE.graph(root, root / "shell.qml")
            self.assertIn("services/AudioService.qml", report["reachable_qml_files"])

    def test_reports_dynamic_loading_as_a_caveat(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "shell"
            root.mkdir(parents=True)
            (root / "shell.qml").write_text(
                'import QtQuick\nLoader { source: Config.dynamicPage }\n',
                encoding="utf-8",
            )
            report = MODULE.graph(root, root / "shell.qml")
            self.assertEqual(report["dynamic_loading_files"], ["shell.qml"])


if __name__ == "__main__":
    unittest.main()
