#!/usr/bin/env python3
# Copyright (C) 2026 The Gesher HaMeitarim Authors (גשר המיתרים); SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
"""מפענח Brotli ב-Http2Transport (פריט 19, גל 6).

בודק שני דברים: שהמפענח המצורף מפענח זרם Brotli קבוע לטקסט המקורי, ושה-Http2Transport
מקבל Content-Encoding: br ומפעיל את המפענח. התנהגות מול שרת אמיתי נבדקת ידנית
(docs/he/11-wave6-manual-checks.md).
"""
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
# 'שלום מיתר, Hello Brotli. ' פעמים 40, מכווץ ב-Brotli
STREAM = "1b2705f82d0e781373e50456bb0ee967a8bc6601f1183b67190a1b2d84542627415ce8922ded2d3c0c181e8c117082ae33c6af00"
HARNESS = """
import org.brotli.dec.BrotliInputStream;
import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;
public class H {
    public static void main(String[] a) throws Exception {
        byte[] in = new byte[a[0].length() / 2];
        for (int i = 0; i < in.length; i++) in[i] = (byte) Integer.parseInt(a[0].substring(2 * i, 2 * i + 2), 16);
        String out = new String(new BrotliInputStream(new ByteArrayInputStream(in)).readAllBytes(), StandardCharsets.UTF_8);
        System.out.print(out.equals(a[1]) ? "OK" : "DIFFERENT");
    }
}
"""


class BrotliDecoder(unittest.TestCase):
    @unittest.skipUnless(shutil.which("javac") and shutil.which("java"), "אין JDK")
    def test_decodes_known_stream(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            sources = [str(p) for p in (ROOT / "app/java/org/brotli").rglob("*.java")]
            (tmp / "H.java").write_text(HARNESS, encoding="utf-8")
            subprocess.run(["javac", "--release", "11", "-nowarn", "-encoding", "UTF-8", "-d", str(tmp), *sources, str(tmp / "H.java")],
                           check=True, capture_output=True)
            expected = "שלום מיתר, Hello Brotli. " * 40
            run = subprocess.run(["java", "-Dfile.encoding=UTF-8", "-cp", str(tmp), "H", STREAM, expected],
                                 check=True, capture_output=True, text=True, encoding="utf-8")
            self.assertEqual(run.stdout.strip(), "OK")

    def test_transport_accepts_br_and_uses_decoder(self):
        text = (ROOT / "app/java/android/net/http/Http2Transport.java").read_text(encoding="utf-8")
        self.assertIn('!encoding.equalsIgnoreCase("br")', text)
        self.assertIn('new BrotliInputStream(raw)', text)
        self.assertEqual(text.count('equalsIgnoreCase("br")'), 3)

    def test_license_is_shipped(self):
        self.assertIn("Permission is hereby granted", (ROOT / "app/java/org/brotli/LICENSE").read_text(encoding="utf-8"))
        self.assertIn("brotli", (ROOT / "NOTICE.md").read_text(encoding="utf-8").lower())


if __name__ == "__main__":
    unittest.main()
