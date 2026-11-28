#!/usr/bin/env python3
# Copyright (C) 2026 The Gesher HaMeitarim Authors (גשר המיתרים); SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
"""The Control Center's settings column can be resized (no build needed).

The gap between the apps list and the settings column is a transparent GridSplitter with limits on
both columns, a name for screen readers and keyboard steps. Dragging and the arrow keys are
checked by hand (docs/he/11-wave6-manual-checks.md).
"""
import json
import re
import unittest
import xml.dom.minidom
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class PanelResize(unittest.TestCase):
    def test_splitter(self):
        text = (ROOT / "tools/package/gesher-panel-dashboard.xaml").read_text(encoding="utf-8")
        xml.dom.minidom.parseString(text.encode("utf-8"))
        splitter = re.search(r"<GridSplitter[^>]*>", text, re.S).group(0)
        self.assertIn('Grid.Column="1"', splitter)
        self.assertIn('ResizeBehavior="PreviousAndNext"', splitter)
        self.assertIn('Background="Transparent"', splitter)
        self.assertIn("KeyboardIncrement", splitter)
        self.assertIn("Text_cp_panel_resize", splitter)
        columns = re.search(r'<ColumnDefinition Width="\*" MinWidth="(\d+)"/>\s*<ColumnDefinition Width="28"/>\s*'
                            r'<ColumnDefinition Width="272" MinWidth="(\d+)" MaxWidth="(\d+)"/>', text)
        self.assertTrue(columns, "the three columns lost their limits")
        apps_min, rail_min, rail_max = map(int, columns.groups())
        self.assertLess(rail_min, 272)
        self.assertGreater(rail_max, 272)
        self.assertGreaterEqual(apps_min, 300)

    def test_name_in_both_languages(self):
        catalog = json.loads((ROOT / "tools/i18n/messages.json").read_text(encoding="utf-8"))["messages"]
        self.assertEqual(set(catalog["cp_panel_resize"]), {"en", "he"})


if __name__ == "__main__":
    unittest.main()
