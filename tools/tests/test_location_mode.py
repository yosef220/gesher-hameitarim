#!/usr/bin/env python3
# Copyright (C) 2026 The Gesher HaMeitarim Authors (גשר המיתרים); SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
"""Settings.Secure.location_mode follows the location service (no build needed).

The setting used to be a fixed "0" (off) whatever Windows' location setting was, so an app that
reads it (a Wi-Fi scanner library, for example) concluded location was off and refused to scan.
SettingsProvider now answers from the location service on every read path (GET, LIST, query all
go through visible()). Behavior is checked on Windows by hand (docs/he/11-wave6-manual-checks.md).
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class LocationMode(unittest.TestCase):
    def test_every_read_path_goes_through_visible(self):
        text = (ROOT / "app/java/com/gesher/server/SettingsProvider.java").read_text(encoding="utf-8")
        for path in ('valueBundle(visible(table, arg, rows.get(arg)))',
                     'visible(table, e.getKey(), e.getValue())',
                     'visible(args.table, entry.getKey(), entry.getValue())'):
            self.assertIn(path, text)
        body = text[text.index("private String visible("):]
        body = body[:body.index("private String verifiedCheckerSelection")]
        self.assertIn("Settings.Secure.LOCATION_MODE.equals(name)", body)
        self.assertIn("LOCATION_MODE_HIGH_ACCURACY", body)
        self.assertIn("LOCATION_MODE_OFF", body)
        # A failing location query leaves the stored value, never an exception for the reader.
        self.assertIn("catch (RuntimeException e)", body)

    def test_the_service_is_wired_in(self):
        services = (ROOT / "app/java/com/gesher/server/Services.java").read_text(encoding="utf-8")
        self.assertRegex(services, r"SettingsProvider\.sLocationEnabled = \(\) -> location\.isLocationEnabledForUser\(0\);")


if __name__ == "__main__":
    unittest.main()
