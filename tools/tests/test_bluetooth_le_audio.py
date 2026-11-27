#!/usr/bin/env python3
# Copyright (C) 2026 The Gesher HaMeitarim Authors (גשר המיתרים); SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
"""BluetoothLeAudio proxy wiring and the service numbers it relies on (no build needed).

The LE Audio services are named by Bluetooth SIG assigned numbers: Audio Stream Control 0x184E and
Published Audio Capabilities 0x1850. The proxy lists a paired device only when Windows reports
both; the adapter hands out the proxy for BluetoothProfile.LE_AUDIO (22) and counts it in
getProfileConnectionState. Behavior with real devices is checked by hand
(docs/he/11-wave6-manual-checks.md).
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


def short_uuid(text, name):
    value = re.search(r'%s = UUID\.fromString\("([0-9a-f]{8})-0000-1000-8000-00805f9b34fb"\)' % name, text).group(1)
    return int(value, 16)


class LeAudio(unittest.TestCase):
    def test_service_numbers(self):
        server = read("app/java/com/gesher/server/BluetoothManagerService.java")
        self.assertEqual(short_uuid(server, "LE_AUDIO_STREAM_CONTROL"), 0x184E)
        self.assertEqual(short_uuid(server, "LE_AUDIO_CAPABILITIES"), 0x1850)
        self.assertIn("d.has(LE_AUDIO_STREAM_CONTROL) && d.has(LE_AUDIO_CAPABILITIES)", server)

    def test_adapter_hands_out_the_proxy(self):
        adapter = read("app/java/android/bluetooth/BluetoothAdapter.java")
        self.assertIn("case BluetoothProfile.LE_AUDIO:\n                proxy = new BluetoothLeAudio(context);", adapter)
        self.assertIn("profile == BluetoothProfile.LE_AUDIO && BluetoothAudioProfile.isLeAudio(d)", adapter)
        self.assertEqual(int(re.search(r"int LE_AUDIO = (\d+);", read("app/java/android/bluetooth/BluetoothProfile.java")).group(1)), 22)

    def test_proxy_claims_nothing_it_does_not_know(self):
        proxy = read("app/java/android/bluetooth/BluetoothLeAudio.java")
        self.assertIn("return GROUP_ID_INVALID;", proxy)
        self.assertIn("extends BluetoothAudioProfile", proxy)
        # Connecting is Windows': no connect or disconnect that pretends to succeed.
        self.assertNotRegex(proxy, r"boolean\s+(connect|disconnect)\(")


if __name__ == "__main__":
    unittest.main()
