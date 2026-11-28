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

# Shown in a dialog or in the Control Center (not printed by gesher-app). cp_about_body is not
# listed: its value is a version number (digits and dots), and the About dialog's contract test
# (tests/windows/shell/Issue32And33Contracts.ps1) expects the version run exactly as inserted.
DIALOG_KEYS = [
    "install_request", "removal_request",
    "cp_uninstall_confirm", "cp_uninstall_failed", "cp_install_failed", "cp_proxy_invalid",
    "cp_proxy_app_title", "cp_proxy_app_value", "cp_open_logs_failed",
    "cp_camera_image_picker_failed", "cp_proxy_save_failed",
    "cp_downloading", "cp_installing", "cp_update_exit_code", "cp_action_failed",
    "cp_accounts_remove_confirm", "cp_web_intent_fallback_failed",
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


    def test_hebrew_hint_has_no_scrambled_latin_runs(self):
        # Seen in the Control Center preview (control-center-preview.ps1): "(intent://)" inside a
        # Hebrew sentence was shown scrambled, and a Latin word followed by a full stop at the end
        # of a sentence is shown with the stop on the wrong side. The text for non-technical readers
        # leaves the scheme name out and ends its sentences in Hebrew.
        hint = CATALOG["cp_web_intent_fallback_hint"]["he"]
        self.assertNotIn("intent", hint)
        self.assertNotRegex(hint, r"[A-Za-z][.,:;)]")
        self.assertNotRegex(hint, r"[(][A-Za-z]")


if __name__ == "__main__":
    unittest.main()
