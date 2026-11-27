/*
 * Copyright (C) 2026 The Gesher Authors
 * SPDX-License-Identifier: Apache-2.0
 */
package android.bluetooth;

import android.content.Context;
import com.gesher.server.BluetoothManagerService;
import com.gesher.server.WindowsBluetooth;
import java.util.ArrayList;
import java.util.List;

/**
 * What the A2DP and headset proxies share: the paired devices Windows has connected that
 * offer the profile's service (an A2DP sink; hands-free or headset), from the paired
 * devices' SDP service classes. Windows, not the app, connects and disconnects them.
 *
 * @hide
 */
abstract class BluetoothAudioProfile implements BluetoothProfile {
    private final Context mContext;

    BluetoothAudioProfile(Context context) {
        mContext = context;
    }

    abstract boolean offers(WindowsBluetooth.Device device);

    Context context() {
        return mContext;
    }

    @Override
    public List<BluetoothDevice> getConnectedDevices() {
        return getDevicesMatchingConnectionStates(new int[] {STATE_CONNECTED});
    }

    @Override
    public List<BluetoothDevice> getDevicesMatchingConnectionStates(int[] states) {
        BluetoothHost.enforceConnect(mContext);
        List<BluetoothDevice> out = new ArrayList<>();
        if (states == null) return out;
        for (WindowsBluetooth.Device d : BluetoothHost.bonded()) {
            if (!offers(d)) continue;
            int state = d.connected ? STATE_CONNECTED : STATE_DISCONNECTED;
            for (int s : states) {
                if (s == state) {
                    out.add(BluetoothHost.device(WindowsBluetooth.address(d.address), d.addressType,
                            mContext));
                    break;
                }
            }
        }
        return out;
    }

    @Override
    public int getConnectionState(BluetoothDevice device) {
        BluetoothHost.enforceConnect(mContext);
        if (device == null) return STATE_DISCONNECTED;
        for (WindowsBluetooth.Device d : BluetoothHost.bonded()) {
            if (WindowsBluetooth.address(d.address).equals(device.getAddress()) && offers(d)) {
                return d.connected ? STATE_CONNECTED : STATE_DISCONNECTED;
            }
        }
        return STATE_DISCONNECTED;
    }

    static boolean isA2dp(WindowsBluetooth.Device d) {
        return BluetoothManagerService.isA2dp(d);
    }

    static boolean isLeAudio(WindowsBluetooth.Device d) {
        return BluetoothManagerService.isLeAudio(d);
    }

    static boolean isHeadset(WindowsBluetooth.Device d) {
        return BluetoothManagerService.isHeadset(d);
    }
}
