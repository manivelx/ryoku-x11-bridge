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
            (root / "helpers.js").write_text("function value() { return 1 }\n", encoding="utf-8")
            (root / "shell.qml").write_text(
                'import "parts"\nimport "helpers.js" as Helpers\nShellRoot { Widget { } }\n', encoding="utf-8"
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
            self.assertEqual(report["unresolved_local_imports"], [])
            self.assertEqual(report["non_qml_local_imports"], ["shell.qml: helpers.js"])

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

    def test_follows_literal_dynamic_qml_paths_and_reports_profiles(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "shell"
            pages = root / "pages"
            pages.mkdir(parents=True)
            (root / "shell.qml").write_text(
                'Loader { source: Qt.resolvedUrl("pages/Settings.qml") }\\n'
                'property string activeProfile: "desktop"\\n',
                encoding="utf-8",
            )
            (pages / "Settings.qml").write_text("Item { }\\n", encoding="utf-8")
            report = MODULE.graph(root, root / "shell.qml")
            self.assertIn("pages/Settings.qml", report["reachable_qml_files"])
            self.assertEqual(report["dynamic_references"][0]["resolution"], "resolved-local")
            self.assertIn("shell.qml", report["profile_dependent_files"])

    def test_reports_non_literal_dynamic_sources_and_external_modules(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "shell"
            root.mkdir(parents=True)
            (root / "shell.qml").write_text(
                'import Quickshell.Services.Pipewire\\n'
                'Loader { source: Config.profilePage }\\n',
                encoding="utf-8",
            )
            report = MODULE.graph(root, root / "shell.qml")
            self.assertEqual(len(report["unresolved_dynamic_references"]), 1)
            self.assertIn("Quickshell.Services.Pipewire", report["external_module_imports"])

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
