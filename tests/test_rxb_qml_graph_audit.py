import importlib.util
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "audit-rxb-qml-graph.py"
SPEC = importlib.util.spec_from_file_location("audit_rxb_qml_graph", SCRIPT)
AUDIT = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(AUDIT)


class LoaderSourceAuditTests(unittest.TestCase):
    def test_ignores_image_and_video_source_properties(self):
        source = """
Image { source: root.wallpaperUrl }
AnimatedImage { source: animatedPath }
MediaPlayer { source: player.source }
"""
        self.assertEqual([], AUDIT.loader_source_expressions(source))

    def test_collects_only_loader_source_properties(self):
        source = """
Loader {
    active: true
    source: Qt.resolvedUrl("panels/Panel.qml")
    Image { source: root.wallpaperUrl }
}
"""
        self.assertEqual(
            [(4, 'Qt.resolvedUrl("panels/Panel.qml")')],
            AUDIT.loader_source_expressions(source),
        )

    def test_ignores_nested_child_source_and_finds_nested_loader_separately(self):
        source = """
Loader {
    source: root.panelUrl
    Item {
        Image { source: imageUrl }
        Loader { source: root.childComponentUrl }
    }
}
"""
        self.assertEqual(
            [(3, "root.panelUrl"), (6, "root.childComponentUrl")],
            AUDIT.loader_source_expressions(source),
        )

    def test_ignores_comments_and_braces_inside_strings(self):
        source = r'''
Loader {
    // source: "commented.qml"
    property string note: "a brace } and source: ignored.qml"
    source: Qt.resolvedUrl("real.qml")
}
'''
        self.assertEqual(
            [(5, 'Qt.resolvedUrl("real.qml")')],
            AUDIT.loader_source_expressions(source),
        )

    def test_does_not_treat_identifier_suffix_as_source_property(self):
        source = """
Loader {
    sourceSize: Qt.size(100, 100)
    sourceComponent: panelComponent
    source: dynamicPanelUrl
}
"""
        self.assertEqual([(4, "dynamicPanelUrl")], AUDIT.loader_source_expressions(source))


if __name__ == "__main__":
    unittest.main()
