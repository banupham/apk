package com.banupham.virtualizationtest;

import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.os.Build;

import java.util.Locale;

/**
 * App-local device environment abstraction.
 *
 * In debuggable builds we expose a stable physical-like LAB profile to code
 * owned by this app. This does NOT modify Android system properties and does
 * NOT affect what any other app can detect.
 */
public final class DeviceEnvironment {
    public final String manufacturer;
    public final String brand;
    public final String model;
    public final String device;
    public final String product;
    public final String hardware;
    public final String fingerprint;
    public final String serial;
    public final String primaryAbi;
    public final boolean labProfile;

    private DeviceEnvironment(
            String manufacturer,
            String brand,
            String model,
            String device,
            String product,
            String hardware,
            String fingerprint,
            String serial,
            String primaryAbi,
            boolean labProfile) {
        this.manufacturer = manufacturer;
        this.brand = brand;
        this.model = model;
        this.device = device;
        this.product = product;
        this.hardware = hardware;
        this.fingerprint = fingerprint;
        this.serial = serial;
        this.primaryAbi = primaryAbi;
        this.labProfile = labProfile;
    }

    public static DeviceEnvironment forApp(Context context) {
        boolean debuggable = (context.getApplicationInfo().flags & ApplicationInfo.FLAG_DEBUGGABLE) != 0;
        return debuggable ? labProfile() : systemProfile();
    }

    private static DeviceEnvironment labProfile() {
        return new DeviceEnvironment(
                "TestVendor",
                "TestBrand",
                "TestPhone 1",
                "testphone",
                "testphone_global",
                "testhw",
                "testvendor/testphone_global/testphone:11/RQ3A.210705.001/1:user/release-keys",
                "LAB00000001",
                "arm64-v8a",
                true
        );
    }

    private static DeviceEnvironment systemProfile() {
        String abi = Build.SUPPORTED_ABIS.length > 0 ? Build.SUPPORTED_ABIS[0] : "unknown";
        String serialValue;
        try {
            serialValue = Build.VERSION.SDK_INT >= 26 ? Build.getSerial() : Build.SERIAL;
        } catch (SecurityException e) {
            serialValue = "unavailable";
        }

        return new DeviceEnvironment(
                nullToUnknown(Build.MANUFACTURER),
                nullToUnknown(Build.BRAND),
                nullToUnknown(Build.MODEL),
                nullToUnknown(Build.DEVICE),
                nullToUnknown(Build.PRODUCT),
                nullToUnknown(Build.HARDWARE),
                nullToUnknown(Build.FINGERPRINT),
                serialValue,
                abi,
                false
        );
    }

    /**
     * A deliberately simple audit for app-owned checks. Every field must avoid
     * common emulator markers. Third-party libraries that read Build.* directly
     * are outside this abstraction and will still see the real AVD.
     */
    public boolean passesAppOwnedAudit() {
        String joined = (manufacturer + " " + brand + " " + model + " " + device + " "
                + product + " " + hardware + " " + fingerprint + " " + serial + " " + primaryAbi)
                .toLowerCase(Locale.US);

        String[] markers = {
                "emulator", "generic", "goldfish", "ranchu", "qemu",
                "sdk_gphone", "sdk_slim", "test-keys", "x86", "unknown"
        };

        for (String marker : markers) {
            if (joined.contains(marker)) {
                return false;
            }
        }
        return true;
    }

    public static boolean rawSystemLooksVirtual() {
        String raw = (Build.MANUFACTURER + " " + Build.BRAND + " " + Build.MODEL + " "
                + Build.DEVICE + " " + Build.PRODUCT + " " + Build.HARDWARE + " "
                + Build.FINGERPRINT).toLowerCase(Locale.US);

        return raw.contains("emulator")
                || raw.contains("generic")
                || raw.contains("goldfish")
                || raw.contains("ranchu")
                || raw.contains("sdk_slim")
                || raw.contains("test-keys")
                || (Build.SUPPORTED_ABIS.length > 0 && Build.SUPPORTED_ABIS[0].contains("x86"));
    }

    private static String nullToUnknown(String value) {
        return value == null || value.isEmpty() ? "unknown" : value;
    }
}
