# Helper APK (com.umd.helper)

A 4 KB exported activity whose only job is to run a command **inside Termux**
from anywhere else on the phone (launcher shortcut, tasker, etc.). It fires
Termux's `com.termux.RUN_COMMAND` intent service, which executes the command
in Termux's own process — the same process the umd stack runs in — so the
command has Termux's environment and, crucially, survives a launch from
outside the Termux UI.

## Why it exists

The whole stack lives inside the Termux app process, and Android is free to
kill or restart apps (battery management, reboots, app updates). For the stack
to be genuinely *always-on*, something has to relaunch it **without opening
the Termux UI** — after boot, after a kill, on a schedule. Android's only
sanctioned way to execute something inside Termux from the outside is the
permission-gated `RUN_COMMAND` intent, and this APK is the thinnest possible
thing that can fire it.

It is strictly optional: if you always start the stack by hand inside Termux
(`termux/umd-start`), you can skip the APK entirely.

Typical use: a launcher shortcut that keeps the stack alive or restarts it,
e.g.

```sh
am start -n com.umd.helper/.MainActivity \
  --es cmd "$HOME/umd/restart.sh"
```

Logs to `/sdcard/umd/helper.log`; command output lands in `/sdcard/umd/rc/`.

## Build

`build_apk.py` needs only Python; it emits `out/unsigned.apk` from the binary
manifest it generates plus a `classes.dex` that you must produce first. A full
build on a host with the Android build tools:

```sh
javac -source 8 -target 8 -d out src/com/umd/helper/MainActivity.java
d8 --release --min-api 26 --output out out/com/umd/helper/*.class   # → out/classes.dex
python3 build_apk.py          # → out/unsigned.apk
apksigner sign --ks ks.jks out/unsigned.apk                         # → out/unsigned.apk (signed)
mv out/unsigned.apk out/helper.apk
```

`d8` and `apksigner` come from the Android SDK build-tools (or the
`com.android.tools:r8` jar for d8). The APK targets SDK 33, so a **v2**
signature is required — plain `jarsigner` (v1 only) will not install on
Android 11+.

Signs with the bundled `ks.jks` dev key. Rebuild with the same key or
Termux's `RUN_COMMAND` permission grant will not carry over.

Requires Termux installed and, once, granting the helper the
`com.termux.permission.RUN_COMMAND` permission (Termux → Settings →
"Additional permissions").
