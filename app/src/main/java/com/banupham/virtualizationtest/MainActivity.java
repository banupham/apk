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

        int pad = (int) (24 * getResources().getDisplayMetrics().density);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setGravity(Gravity.CENTER_VERTICAL);
        root.setPadding(pad, pad, pad, pad);

        TextView title = new TextView(this);
        title.setText("VM SMOKE TEST: PASS");
        title.setTextSize(24);
        title.setGravity(Gravity.CENTER_HORIZONTAL);

        TextView details = new TextView(this);
        details.setTextSize(16);
        details.setPadding(0, pad, 0, 0);
        details.setText(
            "Android API: " + Build.VERSION.SDK_INT + "\n" +
            "Android: " + Build.VERSION.RELEASE + "\n" +
            "Device: " + Build.MANUFACTURER + " " + Build.MODEL + "\n" +
            "ABI: " + Build.SUPPORTED_ABIS[0] + "\n\n" +
            "Nếu bạn thấy màn hình này trên AVD, chuỗi boot -> adb install -> launch đã hoạt động."
        );

        root.addView(title);
        root.addView(details);
        setContentView(root);
    }
}
