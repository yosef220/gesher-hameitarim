// Copyright (C) 2026 The Gesher HaMeitarim Authors (גשר המיתרים); SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
package com.gesher.server;

import android.os.Binder;
import android.os.IBinder;
import android.os.Parcel;
import android.os.RemoteException;

import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.util.Properties;

/**
 * {@code gesher.web_settings}: the system server's side of the Control Center's WebView
 * settings (<code>&lt;data&gt;/system/webview.properties</code>, each off when absent). An app
 * process cannot read data/system, so its WebView asks here, as the camera does
 * ({@link CameraSourceService}). The answer is a bare yes or no and holds nothing of the user's.
 * The name, descriptor and transaction code are repeated in
 * com.gesher.app.webview.IntentFallback, the client; tools/tests/test_web_intent_fallback.py
 * checks that they agree. A change in the file applies to the next question.
 */
public final class WebSettingsService extends Binder {
    public static final String NAME = "gesher.web_settings";
    static final String DESCRIPTOR = "com.gesher.IWebSettings";
    /** "intent_browser_fallback": open the web address an unhandled intent: link carries. */
    static final int INTENT_FALLBACK = IBinder.FIRST_CALL_TRANSACTION;
    static final String INTENT_FALLBACK_KEY = "intent_browser_fallback";

    /** Host tests set the data directory instead of {@link Device#dataDir()}. */
    static volatile String sDataDirForTest;

    public WebSettingsService() {
        super(DESCRIPTOR);
    }

    static File file() {
        String dataDir = sDataDirForTest != null ? sDataDirForTest : Device.dataDir();
        return dataDir == null || dataDir.isEmpty() ? null : new File(dataDir, "system/webview.properties");
    }

    /** Whether the setting is on; false when the file is missing or unreadable. */
    static boolean intentFallbackEnabled() {
        try {
            File file = file();
            if (file == null || !file.isFile()) return false;
            Properties props = new Properties();
            try (FileInputStream in = new FileInputStream(file)) {
                props.load(in);
            }
            return "true".equalsIgnoreCase(props.getProperty(INTENT_FALLBACK_KEY, "").trim());
        } catch (IOException | RuntimeException | LinkageError e) {
            return false;
        }
    }

    @Override
    protected boolean onTransact(int code, Parcel data, Parcel reply, int flags)
            throws RemoteException {
        if (code != INTENT_FALLBACK) return super.onTransact(code, data, reply, flags);
        data.enforceInterface(DESCRIPTOR);
        data.enforceNoDataAvail();
        reply.writeNoException();
        reply.writeBoolean(intentFallbackEnabled());
        return true;
    }
}
