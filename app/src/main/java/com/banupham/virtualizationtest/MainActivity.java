package com.banupham.virtualizationtest;

import android.app.Activity;
import android.os.Build;
import android.os.Bundle;
import android.view.Gravity;
import android.widget.LinearLayout;
import android.widget.TextView;

public class MainActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        DeviceEnvironment env = DeviceEnvironment.forApp(this);
        boolean appAuditPass = env.passesAppOwnedAudit();
        boolean rawVirtual = DeviceEnvironment.rawSystemLooksVirtual();

        int pad = (int) (24 * getResources().getDisplayMetrics().density);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setGravity(Gravity.CENTER_VERTICAL);
        root.setPadding(pad, pad, pad, pad);

        TextView title = new TextView(this);
        title.setText(appAuditPass ? "APP-LOCAL DEVICE AUDIT: PASS" : "APP-LOCAL DEVICE AUDIT: FAIL");
        title.setTextSize(24);
        title.setGravity(Gravity.CENTER_HORIZONTAL);

        TextView details = new TextView(this);
        details.setTextSize(15);
        details.setPadding(0, pad, 0, 0);
        details.setText(
            "Profile mode: " + (env.labProfile ? "LAB / DEBUG" : "SYSTEM / RELEASE") + "\n" +
            "Android API: " + Build.VERSION.SDK_INT + "\n" +
            "Android: " + Build.VERSION.RELEASE + "\n\n" +
            "Effective app-owned profile\n" +
            "Manufacturer: " + env.manufacturer + "\n" +
            "Brand: " + env.brand + "\n" +
            "Model: " + env.model + "\n" +
            "Device: " + env.device + "\n" +
            "Product: " + env.product + "\n" +
            "Hardware: " + env.hardware + "\n" +
            "ABI: " + env.primaryAbi + "\n" +
            "Serial: " + env.serial + "\n" +
            "Fingerprint: " + env.fingerprint + "\n\n" +
            "App-owned audit: " + (appAuditPass ? "PASS" : "FAIL") + "\n" +
            "Raw OS still reports virtual environment: " + (rawVirtual ? "YES" : "NO") + "\n\n" +
            "This lab profile is visible only through DeviceEnvironment inside this app. " +
            "It does not alter Android system properties or other apps."
        );

        root.addView(title);
        root.addView(details);
        setContentView(root);
    }
}
