// Copyright (C) 2026 The Gesher HaMeitarim Authors (גשר המיתרים); SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
package com.gesher.app.webview;

import android.os.IBinder;
import android.os.Parcel;
import android.os.RemoteException;
import android.os.ServiceManager;

import java.io.UnsupportedEncodingException;
import java.net.URI;
import java.net.URISyntaxException;
import java.net.URLDecoder;
import java.util.Locale;

/**
 * The Control Center's setting "open the web address an unhandled app link carries", off by
 * default. A page can navigate to an {@code intent://...#Intent;...;S.browser_fallback_url=ADDRESS;end}
 * link, which is meant to open an app and names a web address for when none handles it. Android's
 * WebView does not open that address by itself: the page fails to load, and an app may handle the
 * link in shouldOverrideUrlLoading. With the setting on and the app not having taken the
 * navigation, the address is opened instead. That differs from Android, so it is the user's
 * choice and every use is logged; with the setting off nothing changes.
 */
final class IntentFallback {
    // The system server's WebSettingsService (com.gesher.server), repeated: a test compares them.
    static final String SERVICE = "gesher.web_settings";
    static final String DESCRIPTOR = "com.gesher.IWebSettings";
    static final int INTENT_FALLBACK = IBinder.FIRST_CALL_TRANSACTION;

    private static final String PARAMETER = "S.browser_fallback_url=";
    private static final int MAX_ADDRESS = 2048;

    private IntentFallback() {
    }

    /**
     * The http or https address an {@code intent:} link names as its browser fallback, or null
     * when the link is not one, names none, or names anything else (a scheme other than http and
     * https, no host, or an address longer than 2048 characters).
     */
    static String address(String url) {
        if (url == null || !url.regionMatches(true, 0, "intent:", 0, 7)) return null;
        int start = url.indexOf("#Intent;");
        if (start < 0) return null;
        for (String part : url.substring(start + "#Intent;".length()).split(";")) {
            if (part.startsWith(PARAMETER)) {
                return webAddress(part.substring(PARAMETER.length()));
            }
        }
        return null;
    }

    private static String webAddress(String encoded) {
        try {
            // Android's Uri.encode writes a space as %20: a raw '+' is a plus.
            String value = URLDecoder.decode(encoded.replace("+", "%2B"), "UTF-8");
            if (value.isEmpty() || value.length() > MAX_ADDRESS) return null;
            // A raw space is a malformed address for java.net.URI, and a browser loads it.
            URI uri = new URI(value.replace(" ", "%20"));
            String scheme = uri.getScheme();
            if (scheme == null) return null;
            scheme = scheme.toLowerCase(Locale.ROOT);
            if (!scheme.equals("http") && !scheme.equals("https")) return null;
            String host = uri.getHost();
            return host == null || host.isEmpty() ? null : value;
        } catch (IllegalArgumentException | UnsupportedEncodingException | URISyntaxException e) {
            return null;
        }
    }

    /** Whether the setting is on, as the system server answers; false when it cannot be asked. */
    static boolean enabled() {
        Parcel data = Parcel.obtain();
        Parcel reply = Parcel.obtain();
        try {
            IBinder service = ServiceManager.getService(SERVICE);
            if (service == null) return false;
            data.writeInterfaceToken(DESCRIPTOR);
            if (!service.transact(INTENT_FALLBACK, data, reply, 0)) return false;
            reply.readException();
            return reply.readBoolean();
        } catch (RemoteException | RuntimeException e) {
            return false;
        } finally {
            data.recycle();
            reply.recycle();
        }
    }
}
