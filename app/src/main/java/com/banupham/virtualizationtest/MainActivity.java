package com.banupham.virtualizationtest;

import android.app.Activity;
import android.os.Bundle;
import android.view.Gravity;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

public class MainActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        EmulatorDetector.Report report = EmulatorDetector.run(this);
        report.log();

        int pad = (int) (20 * getResources().getDisplayMetrics().density);

        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setPadding(pad, pad, pad, pad);

        TextView title = new TextView(this);
        title.setText(report.strictPass()
                ? "INDEPENDENT EMULATOR AUDIT: PASS"
                : "INDEPENDENT EMULATOR AUDIT: FAIL");
        title.setTextSize(23);
        title.setGravity(Gravity.CENTER_HORIZONTAL);

        TextView note = new TextView(this);
        note.setTextSize(14);
        note.setPadding(0, pad / 2, 0, pad / 2);
        note.setText(
                "Real app-visible environment only. No mock profile, root, shell, " +
                "hidden system-property API, spoofing, or hooks are used.\n"
        );

        TextView details = new TextView(this);
        details.setTextSize(14);
        details.setTextIsSelectable(true);
        details.setText(report.toDisplayText());

        content.addView(title);
        content.addView(note);
        content.addView(details);

        ScrollView scroll = new ScrollView(this);
        scroll.addView(content);
        setContentView(scroll);
    }
}
