#!/usr/bin/env python3
# Copyright (C) 2026 The Gesher HaMeitarim Authors (גשר המיתרים); SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
"""Hebrew dialog texts isolate every value they insert (no build needed).

A value inserted into a Hebrew sentence (a package name, a version, an exception message in
English) takes the sentence's direction at its edges unless it is isolated: punctuation next to it
lands on the wrong side. The texts below are shown in dialogs and the Control Center, so each
{N} must sit between U+2068 (first strong isolate) and U+2069. Console messages are not listed:
a legacy console prints the isolates as boxes. The rendering itself is checked by hand
(docs/he/11-wave6-manual-checks.md).
"""
import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOG = json.loads((ROOT / "tools/i18n/messages.json").read_text(encoding="utf-8"))["messages"]

# Shown in a dialog or in the Control Center (not printed by gesher-app).
DIALOG_KEYS = [
    "install_request", "removal_request",
    "cp_uninstall_confirm", "cp_uninstall_failed", "cp_install_failed", "cp_proxy_invalid",
    "cp_proxy_app_title", "cp_proxy_app_value", "cp_open_logs_failed",
    "cp_camera_image_picker_failed", "cp_proxy_save_failed", "cp_about_body",
    "cp_downloading", "cp_installing", "cp_update_exit_code", "cp_action_failed",
]


class DialogBidi(unittest.TestCase):
    def test_every_inserted_value_is_isolated(self):
        for key in DIALOG_KEYS:
            he = CATALOG[key]["he"]
            placeholders = list(re.finditer(r"\{\d+\}", he))
            self.assertTrue(placeholders, key)
            for match in placeholders:
                before = he[match.start() - 1] if match.start() else ""
                after = he[match.end()] if match.end() < len(he) else ""
                self.assertEqual((before, after), ("⁨", "⁩"),
                                 "%s: %s is not isolated" % (key, match.group()))


if __name__ == "__main__":
    unittest.main()
