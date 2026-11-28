#!/usr/bin/env python3
# Copyright (C) 2026 The Gesher HaMeitarim Authors (גשר המיתרים); SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
"""The WebView setting "open the web address an unhandled intent: link carries" (off by default).

Checks that the client (com.gesher.app.webview.IntentFallback) and the system server's service
(com.gesher.server.WebSettingsService) agree on the name, descriptor and transaction, that the
Control Center writes the key the server reads, and runs the client's address parser against
minimal android.os stubs when a JDK is installed (the parser needs no framework).
"""
import json
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CLIENT = ROOT / "app/java/com/gesher/app/webview/IntentFallback.java"
SERVER = ROOT / "app/java/com/gesher/server/WebSettingsService.java"


def constant(text, name):
    return re.search(r'%s\s*=\s*"([^"]+)"' % name, text).group(1)


STUBS = {
    "android/os/IBinder.java": "package android.os; public interface IBinder { int FIRST_CALL_TRANSACTION = 1; boolean transact(int c, Parcel d, Parcel r, int f) throws RemoteException; }",
    "android/os/Parcel.java": "package android.os; public class Parcel { public static Parcel obtain(){return new Parcel();} public void recycle(){} public void writeInterfaceToken(String s){} public void readException(){} public boolean readBoolean(){return false;} }",
    "android/os/RemoteException.java": "package android.os; public class RemoteException extends Exception {}",
    "android/os/ServiceManager.java": "package android.os; public class ServiceManager { public static IBinder getService(String n){return null;} }",
}

# (link, the address, or None when no address is opened)
CASES = [
    ("intent://scan/#Intent;scheme=zxing;package=com.x;S.browser_fallback_url=https%3A%2F%2Fexample.com%2Fa%3Fb%3D1;end", "https://example.com/a?b=1"),
    ("intent://x#Intent;S.browser_fallback_url=http%3A%2F%2Fexample.com%2F;end", "http://example.com/"),
    ("INTENT://x#Intent;S.browser_fallback_url=https%3A%2F%2Fe.com%2F;end", "https://e.com/"),
    ("intent://x#Intent;S.browser_fallback_url=https%3A%2F%2Fe.com%2Fa+b;end", "https://e.com/a+b"),
    ("intent://x#Intent;S.browser_fallback_url=https%3A%2F%2Fe.com%2Fa%20b;end", "https://e.com/a b"),
    ("intent://x#Intent;S.browser_fallback_url=https%3A%2F%2Fe.com%2F%D7%90;end", "https://e.com/א"),
    ("intent://x#Intent;scheme=a;end", None),
    ("https://e.com/#Intent;S.browser_fallback_url=https%3A%2F%2Fe.com;end", None),
    ("intent://x", None),
    ("intent://x#Intent;S.browser_fallback_url=javascript%3Aalert(1);end", None),
    ("intent://x#Intent;S.browser_fallback_url=file%3A%2F%2F%2Fc%3A%2Fx;end", None),
    ("intent://x#Intent;S.browser_fallback_url=market%3A%2F%2Fdetails%3Fid%3Da;end", None),
    ("intent://x#Intent;S.browser_fallback_url=https%3A%2F%2F;end", None),
    ("intent://x#Intent;S.browser_fallback_url=https%3A%2F%2Fe.com%ZZ;end", None),
    ("intent://x#Intent;S.browser_fallback_url=;end", None),
    ("intent://x#Intent;S.browser_fallback_url=https%3A%2F%2Fe.com%2F" + "a" * 2100 + ";end", None),
]


def java_string(value):
    return '"' + "".join(c if 32 <= ord(c) < 127 and c not in '"\\' else "\\u%04x" % ord(c) for c in value) + '"'


class WebIntentFallback(unittest.TestCase):
    def test_client_and_server_agree(self):
        client, server = CLIENT.read_text(encoding="utf-8"), SERVER.read_text(encoding="utf-8")
        self.assertEqual(constant(client, "SERVICE"), constant(server, "NAME"))
        self.assertEqual(constant(client, "DESCRIPTOR"), constant(server, "DESCRIPTOR"))
        self.assertIn("INTENT_FALLBACK = IBinder.FIRST_CALL_TRANSACTION;", client)
        self.assertIn("INTENT_FALLBACK = IBinder.FIRST_CALL_TRANSACTION;", server)
        services = (ROOT / "app/java/com/gesher/server/Services.java").read_text(encoding="utf-8")
        self.assertIn("services.put(WebSettingsService.NAME, new WebSettingsService());", services)

    def test_control_center_writes_the_key_the_server_reads(self):
        key = constant(SERVER.read_text(encoding="utf-8"), "INTENT_FALLBACK_KEY")
        script = (ROOT / "tools/package/gesher-control-panel.ps1").read_text(encoding="utf-8")
        self.assertIn("data/system/webview.properties", script)
        self.assertIn(key + "=true", script)
        dashboard = (ROOT / "tools/package/gesher-panel-dashboard.xaml").read_text(encoding="utf-8")
        self.assertIn('Name="WebIntentFallback"', dashboard)
        # Off by default: nothing in the Control Center or the server turns it on by itself.
        self.assertNotIn("IsChecked=\"True\"", dashboard[dashboard.index('Name="WebIntentFallback"'):][:400])

    def test_the_setting_is_explained_in_both_languages(self):
        catalog = json.loads((ROOT / "tools/i18n/messages.json").read_text(encoding="utf-8"))["messages"]
        for key in ("cp_web_title", "cp_web_intent_fallback", "cp_web_intent_fallback_hint",
                    "cp_web_intent_fallback_saved", "cp_web_intent_fallback_failed"):
            self.assertEqual(set(catalog[key]), {"en", "he"}, key)
        hint = catalog["cp_web_intent_fallback_hint"]
        self.assertIn("Android", hint["en"])
        self.assertIn("Android", hint["he"])
        # The visible text says it differs from Android and is off by default.
        self.assertRegex(hint["en"].lower(), r"differs from android")
        self.assertRegex(hint["en"].lower(), r"off by default")

    @unittest.skipUnless(shutil.which("javac") and shutil.which("java"), "no JDK")
    def test_address_parser(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            for name, text in STUBS.items():
                path = tmp / "stubs" / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text, encoding="utf-8")
            package = tmp / "src/com/gesher/app/webview"
            package.mkdir(parents=True)
            (package / "IntentFallback.java").write_text(CLIENT.read_text(encoding="utf-8"), encoding="utf-8")
            rows = ",\n".join("{%s, %s}" % (java_string(link), java_string(want) if want else "null")
                               for link, want in CASES)
            (package / "Cases.java").write_text(
                "package com.gesher.app.webview;\npublic class Cases {\n"
                "  public static void main(String[] a) {\n"
                "    String[][] cases = {\n" + rows + "};\n"
                "    int bad = 0;\n"
                "    for (String[] c : cases) {\n"
                "      String got = IntentFallback.address(c[0]);\n"
                "      if (!java.util.Objects.equals(c[1], got)) { bad++; System.out.println(\"FAIL \" + c[0] + \" -> \" + got); }\n"
                "    }\n"
                "    if (IntentFallback.enabled()) { bad++; System.out.println(\"FAIL enabled without a service\"); }\n"
                "    if (IntentFallback.address(null) != null) { bad++; System.out.println(\"FAIL null\"); }\n"
                "    System.exit(bad == 0 ? 0 : 1);\n  }\n}\n", encoding="utf-8")
            out = tmp / "out"
            out.mkdir()
            sources = [str(p) for p in (package / "Cases.java", package / "IntentFallback.java")]
            # --release 8: the class files run on any Java, also when javac is newer than the java on
            # the PATH (JDK 21's javac with a Java 11 runtime failed with UnsupportedClassVersionError).
            subprocess.run(["javac", "--release", "8", "-Xlint:-options", "-d", str(out),
                            "-sourcepath", str(tmp / "stubs"), *sources],
                           check=True, capture_output=True, text=True)
            run = subprocess.run(["java", "-cp", str(out), "com.gesher.app.webview.Cases"],
                                 capture_output=True, text=True)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)


if __name__ == "__main__":
    unittest.main()
