package com.banupham.virtualizationtest;

import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.hardware.Sensor;
import android.hardware.SensorManager;
import android.os.BatteryManager;
import android.os.Build;
import android.provider.Settings;
import android.util.Log;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.net.InetAddress;
import java.net.NetworkInterface;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Enumeration;
import java.util.List;
import java.util.Locale;

/**
 * Independent, app-level emulator detectability audit.
 *
 * This class deliberately reads the real environment visible to an ordinary
 * Android app. It does not use DeviceEnvironment, hidden system-property APIs,
 * root, shell commands, spoofing, or hooks.
 */
public final class EmulatorDetector {
    private static final String TAG = "EmulatorDetector";

    public static final class Signal {
        public final String name;
        public final String status;
        public final String detail;
        public final int weight;

        Signal(String name, String status, String detail, int weight) {
            this.name = name;
            this.status = status;
            this.detail = detail;
            this.weight = weight;
        }
    }

    public static final class Report {
        public final List<Signal> signals = new ArrayList<>();
        public int score;
        public int detectedCount;

        void detected(String name, String detail, int weight) {
            signals.add(new Signal(name, "DETECTED", detail, weight));
            detectedCount++;
            score = Math.min(100, score + weight);
        }

        void clean(String name, String detail) {
            signals.add(new Signal(name, "CLEAN", detail, 0));
        }

        void notVisible(String name, String detail) {
            signals.add(new Signal(name, "NOT VISIBLE", detail, 0));
        }

        void info(String name, String detail) {
            signals.add(new Signal(name, "INFO", detail, 0));
        }

        public boolean strictPass() {
            return detectedCount == 0;
        }

        public String verdict() {
            if (strictPass()) return "PASS";
            if (score >= 70) return "FAIL / HIGHLY DETECTABLE";
            if (score >= 35) return "FAIL / DETECTABLE";
            return "FAIL / LOW-SIGNAL DETECTION";
        }

        public String toDisplayText() {
            StringBuilder out = new StringBuilder();
            out.append("Strict result: ").append(strictPass() ? "PASS" : "FAIL").append('\n');
            out.append("Verdict: ").append(verdict()).append('\n');
            out.append("Detectability score: ").append(score).append("/100\n");
            out.append("Detected signals: ").append(detectedCount).append("\n\n");

            for (Signal signal : signals) {
                out.append('[').append(signal.status).append("] ").append(signal.name);
                if (signal.weight > 0) {
                    out.append(" (+").append(signal.weight).append(')');
                }
                out.append('\n').append("  ").append(signal.detail).append("\n\n");
            }
            return out.toString();
        }

        public void log() {
            Log.i(TAG, "STRICT_RESULT=" + (strictPass() ? "PASS" : "FAIL")
                    + " SCORE=" + score + " DETECTED=" + detectedCount);
            for (Signal signal : signals) {
                Log.i(TAG, signal.status + " | " + signal.name + " | " + signal.detail);
            }
        }
    }

    private EmulatorDetector() {}

    public static Report run(Context context) {
        Report report = new Report();

        report.info("Runtime",
                "Android " + Build.VERSION.RELEASE + " / API " + Build.VERSION.SDK_INT);
        report.info("Android ID", safeAndroidId(context));

        checkProductIdentity(report);
        checkHardware(report);
        checkFingerprint(report);
        checkAbi(report);
        checkSensors(context, report);
        checkVirtualFiles(report);
        checkNetwork(report);
        checkCpu(report);
        checkSerial(report);
        checkBattery(context, report);

        return report;
    }

    private static void checkProductIdentity(Report report) {
        String detail = "manufacturer=" + Build.MANUFACTURER
                + ", brand=" + Build.BRAND
                + ", model=" + Build.MODEL
                + ", device=" + Build.DEVICE
                + ", product=" + Build.PRODUCT;
        String lower = detail.toLowerCase(Locale.US);

        String marker = firstMarker(lower,
                "emulator", "generic", "goldfish", "ranchu", "sdk_slim",
                "sdk_gphone", "android atd", "built for x86");
        if (marker != null) {
            report.detected("Build product identity", detail + " ; marker=" + marker, 25);
        } else {
            report.clean("Build product identity", detail);
        }
    }

    private static void checkHardware(Report report) {
        String detail = "hardware=" + Build.HARDWARE + ", board=" + Build.BOARD;
        String lower = detail.toLowerCase(Locale.US);
        String marker = firstMarker(lower, "ranchu", "goldfish", "qemu", "emulator");
        if (marker != null) {
            report.detected("Hardware / board", detail + " ; marker=" + marker, 20);
        } else {
            report.clean("Hardware / board", detail);
        }
    }

    private static void checkFingerprint(Report report) {
        String detail = "fingerprint=" + Build.FINGERPRINT + ", tags=" + Build.TAGS;
        String lower = detail.toLowerCase(Locale.US);
        String marker = firstMarker(lower,
                "generic", "sdk_slim", "sdk_gphone", "test-keys", "emulator", "goldfish", "ranchu");
        if (marker != null) {
            report.detected("Build fingerprint / tags", detail + " ; marker=" + marker, 20);
        } else {
            report.clean("Build fingerprint / tags", detail);
        }
    }

    private static void checkAbi(Report report) {
        String detail = Arrays.toString(Build.SUPPORTED_ABIS);
        String lower = detail.toLowerCase(Locale.US);
        if (lower.contains("x86")) {
            report.detected("CPU ABI", detail + " ; x86-family ABI visible", 15);
        } else {
            report.clean("CPU ABI", detail);
        }
    }

    private static void checkSensors(Context context, Report report) {
        SensorManager manager = (SensorManager) context.getSystemService(Context.SENSOR_SERVICE);
        if (manager == null) {
            report.notVisible("Sensor identity", "SensorManager unavailable");
            return;
        }

        List<Sensor> sensors = manager.getSensorList(Sensor.TYPE_ALL);
        String match = null;
        for (Sensor sensor : sensors) {
            String candidate = sensor.getName() + " / " + sensor.getVendor();
            String lower = candidate.toLowerCase(Locale.US);
            if (lower.contains("goldfish") || lower.contains("ranchu")
                    || lower.contains("qemu") || lower.contains("emulator")) {
                match = candidate;
                break;
            }
        }

        if (match != null) {
            report.detected("Sensor identity", "virtual sensor=" + match, 15);
        } else {
            report.clean("Sensor identity", "No common emulator marker in " + sensors.size() + " sensors");
        }
    }

    private static void checkVirtualFiles(Report report) {
        String[] paths = {
                "/dev/qemu_pipe",
                "/dev/socket/qemud",
                "/sys/qemu_trace",
                "/dev/goldfish_pipe"
        };
        List<String> visible = new ArrayList<>();
        for (String path : paths) {
            try {
                if (new File(path).exists()) {
                    visible.add(path);
                }
            } catch (SecurityException ignored) {
                // From an app-level audit, an inaccessible file is not a visible signal.
            }
        }

        if (!visible.isEmpty()) {
            report.detected("Known virtual-device files", visible.toString(), 15);
        } else {
            report.clean("Known virtual-device files", "No known path visible from app sandbox");
        }
    }

    private static void checkNetwork(Report report) {
        List<String> addresses = new ArrayList<>();
        boolean emulatorSubnet = false;

        try {
            Enumeration<NetworkInterface> interfaces = NetworkInterface.getNetworkInterfaces();
            if (interfaces == null) {
                report.notVisible("Network fingerprint", "No network interfaces returned");
                return;
            }

            for (NetworkInterface networkInterface : Collections.list(interfaces)) {
                for (InetAddress address : Collections.list(networkInterface.getInetAddresses())) {
                    if (address.isLoopbackAddress()) continue;
                    String host = address.getHostAddress();
                    addresses.add(networkInterface.getName() + "=" + host);
                    if (host != null && (host.equals("10.0.2.15") || host.equals("10.0.2.16"))) {
                        emulatorSubnet = true;
                    }
                }
            }
        } catch (Exception e) {
            report.notVisible("Network fingerprint", e.getClass().getSimpleName() + ": " + e.getMessage());
            return;
        }

        if (emulatorSubnet) {
            report.detected("Network fingerprint", addresses.toString() + " ; Android-emulator address visible", 10);
        } else {
            report.clean("Network fingerprint", addresses.toString());
        }
    }

    private static void checkCpu(Report report) {
        String cpu = readCpuInfo();
        if (cpu == null) {
            report.notVisible("/proc/cpuinfo", "Not readable from app process");
            return;
        }

        String lower = cpu.toLowerCase(Locale.US);
        boolean x86Abi = Arrays.toString(Build.SUPPORTED_ABIS).toLowerCase(Locale.US).contains("x86");
        if (x86Abi && (lower.contains("intel") || lower.contains("amd"))) {
            report.detected("/proc/cpuinfo", firstInterestingCpuLine(cpu), 5);
        } else {
            report.clean("/proc/cpuinfo", firstInterestingCpuLine(cpu));
        }
    }

    private static void checkSerial(Report report) {
        String serial = Build.SERIAL;
        try {
            if (Build.VERSION.SDK_INT >= 26) {
                serial = Build.getSerial();
            }
        } catch (SecurityException e) {
            if (serial == null || serial.isEmpty() || "unknown".equalsIgnoreCase(serial)) {
                report.notVisible("Device serial", "Restricted by Android app permissions");
                return;
            }
        }

        if (serial == null || serial.isEmpty() || "unknown".equalsIgnoreCase(serial)) {
            report.notVisible("Device serial", "Unavailable to ordinary app");
        } else if (serial.toLowerCase(Locale.US).contains("emulator")) {
            report.detected("Device serial", serial, 5);
        } else {
            report.clean("Device serial", serial);
        }
    }

    private static void checkBattery(Context context, Report report) {
        Intent battery = context.registerReceiver(null, new IntentFilter(Intent.ACTION_BATTERY_CHANGED));
        if (battery == null) {
            report.notVisible("Battery heuristic", "No sticky battery intent");
            return;
        }

        int level = battery.getIntExtra(BatteryManager.EXTRA_LEVEL, -1);
        int scale = battery.getIntExtra(BatteryManager.EXTRA_SCALE, -1);
        int plugged = battery.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0);
        int status = battery.getIntExtra(BatteryManager.EXTRA_STATUS, -1);
        int percent = (level >= 0 && scale > 0) ? Math.round(level * 100f / scale) : -1;

        String detail = "level=" + percent + "%"
                + ", plugged=" + plugged
                + ", status=" + status;

        if (percent == 100 && plugged != 0) {
            report.detected("Battery heuristic (weak)", detail, 2);
        } else {
            report.clean("Battery heuristic (weak)", detail);
        }
    }

    private static String safeAndroidId(Context context) {
        try {
            String value = Settings.Secure.getString(
                    context.getContentResolver(), Settings.Secure.ANDROID_ID);
            return value == null ? "unavailable" : value;
        } catch (Exception e) {
            return "unavailable: " + e.getClass().getSimpleName();
        }
    }

    private static String readCpuInfo() {
        StringBuilder out = new StringBuilder();
        try (BufferedReader reader = new BufferedReader(new FileReader("/proc/cpuinfo"))) {
            String line;
            int lines = 0;
            while ((line = reader.readLine()) != null && lines < 120 && out.length() < 12000) {
                out.append(line).append('\n');
                lines++;
            }
            return out.toString();
        } catch (Exception e) {
            return null;
        }
    }

    private static String firstInterestingCpuLine(String cpu) {
        String[] lines = cpu.split("\\n");
        for (String line : lines) {
            String lower = line.toLowerCase(Locale.US);
            if (lower.contains("model name") || lower.startsWith("hardware")
                    || lower.startsWith("processor")) {
                return line.trim();
            }
        }
        return "cpuinfo readable";
    }

    private static String firstMarker(String text, String... markers) {
        for (String marker : markers) {
            if (text.contains(marker)) return marker;
        }
        return null;
    }
}
