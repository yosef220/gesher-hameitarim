// Copyright (C) 2026 The Gesher HaMeitarim Authors (גשר המיתרים); SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
package android.bluetooth;

import android.content.Context;
import com.gesher.server.WindowsBluetooth;
import java.util.List;

/**
 * BluetoothLeAudio with the Bluetooth module's public API: the paired devices that offer LE
 * Audio (their stream control and capabilities services, as Windows reports them) and their
 * connection state, which Windows owns. What this device does not know it does not claim:
 * a device's coordinated-set group is unknown (getGroupId answers GROUP_ID_INVALID), and
 * connecting or disconnecting is Windows' (Settings).
 */
public final class BluetoothLeAudio extends BluetoothAudioProfile implements AutoCloseable {
    public static final String ACTION_LE_AUDIO_CONNECTION_STATE_CHANGED =
            "android.bluetooth.action.LE_AUDIO_CONNECTION_STATE_CHANGED";
    public static final String ACTION_LE_AUDIO_ACTIVE_DEVICE_CHANGED =
            "android.bluetooth.action.LE_AUDIO_ACTIVE_DEVICE_CHANGED";
    public static final int GROUP_ID_INVALID = -1;

    BluetoothLeAudio(Context context) {
        super(context);
    }

    @Override
    boolean offers(WindowsBluetooth.Device device) {
        return isLeAudio(device);
    }

    /** The device's coordinated-set group: not known here. */
    public int getGroupId(BluetoothDevice device) {
        BluetoothHost.enforceConnect(context());
        return GROUP_ID_INVALID;
    }

    /** The connected devices (Windows chooses the audio endpoint): the first one, if any. */
    public List<BluetoothDevice> getActiveDevices() {
        List<BluetoothDevice> connected = getConnectedDevices();
        return connected.isEmpty() ? connected : connected.subList(0, 1);
    }

    @Override
    public void close() {
        // Nothing is bound: the proxy reads Windows' state when asked.
    }
}
