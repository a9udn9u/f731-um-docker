package com.umd.helper;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.util.Log;
import java.io.FileOutputStream;

public class MainActivity extends Activity {
    private void log(String msg) {
        try {
            FileOutputStream f = new FileOutputStream("/sdcard/umd/helper.log", true);
            f.write((System.currentTimeMillis() + " " + msg + "\n").getBytes());
            f.close();
        } catch (Exception e) {
        }
        Log.i("UMDHELPER", msg);
    }

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        log("onCreate");
        Intent src = getIntent();
        Intent svc = new Intent("com.termux.RUN_COMMAND");
        svc.setClassName("com.termux", "com.termux.app.RunCommandService");
        String path = src.getStringExtra("path");
        if (path == null) path = "/data/data/com.termux/files/usr/bin/sh";
        String cmd = src.getStringExtra("cmd");
        String[] args = src.getStringArrayExtra("args");
        if (cmd != null) {
            args = new String[]{"-c", cmd};
        }
        if (args == null) {
            args = new String[]{"-c", "echo HELPER_NULL_CMD > /sdcard/umd/rc.out"};
        }
        String workdir = src.getStringExtra("workdir");
        if (workdir == null) workdir = "/data/data/com.termux/files/home";
        boolean bg = src.getBooleanExtra("bg", true);
        svc.putExtra("com.termux.RUN_COMMAND_PATH", path);
        svc.putExtra("com.termux.RUN_COMMAND_ARGUMENTS", args);
        svc.putExtra("com.termux.RUN_COMMAND_WORKDIR", workdir);
        svc.putExtra("com.termux.RUN_COMMAND_BACKGROUND", bg);
        svc.putExtra("com.termux.RUN_COMMAND_RESULT_DIRECTORY", "/sdcard/umd/rc");
        log("starting: " + svc.toString());
        try {
            startService(svc);
            log("startService returned");
        } catch (Exception e) {
            log("EXCEPTION: " + e.toString());
        }
        finish();
    }
}