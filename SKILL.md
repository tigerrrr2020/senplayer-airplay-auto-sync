---
name: senplayer-airplay-auto-sync
description: Install, verify, diagnose, update, or remove automatic SenPlayer audio-delay switching on macOS for AirPort Express and AirPlay speakers, with an optional importable Shortcuts control. Use when a user wants SenPlayer to use about -2 seconds of compensation for an AirPlay/AirPort output and automatically return to 0 seconds for Mac speakers, HDMI, USB audio, or headphones; wants a visible manual shortcut alongside the background automation; needs a reusable setup for another person's Mac; or reports that the LaunchAgent has stopped switching correctly.
---

# SenPlayer AirPlay Auto Sync

Use the bundled native macOS watcher to keep SenPlayer's global audio delay synchronized with the current default output device. AirPlay/AirPort defaults to `-2.0`; every other output defaults to `0.0`.

## Safety and invariants

- Support macOS only. Do not attempt installation on iPhone, iPad, Windows, or Linux.
- Do not delete, replace, or edit existing Shortcuts. Offer the bundled shortcut only when requested, and import it as a separate optional control.
- The setting is specific to SenPlayer on the Mac. Do not alter AirPort Express firmware or system-wide audio timing.
- Restart SenPlayer only when the target delay differs from the stored value. The watcher already enforces this rule.
- Before uninstalling, require explicit confirmation. Run `uninstall --yes` only after the user confirms.
- Treat `-2.0` as the default starting value, not a universal calibration. Accept the user's measured value when supplied.

## Workflow

Resolve this skill's directory and run the bundled manager from there:

```bash
bash scripts/manage.sh <command>
```

### 1. Probe the Mac

Run the read-only probe first:

```bash
bash scripts/manage.sh probe
```

Confirm that:

- SenPlayer has been opened at least once, so its sandbox preference container exists.
- The listed default output is identified correctly as AirPlay or local.
- Apple Command Line Tools provide `swiftc`.

CoreAudio may return no devices in a restricted sandbox. If that happens, rerun the same probe with permission to access the user's logged-in macOS session; do not conclude that the Mac has no audio devices.

### 2. Install or update

Installation is authorized when the user asks to set up, create, install, or enable this automation. Use the user's requested compensation, otherwise use `-2.0`:

```bash
bash scripts/manage.sh install --airplay-delay -2.0
```

The manager compiles the Swift source for the current Mac, ad-hoc signs it, installs it under the current user's Library, creates a per-user LaunchAgent, and starts it. It does not require administrator privileges.

If the user also wants a visible manual control, install the watcher and open the bundled shortcut import screen in one command:

```bash
bash scripts/manage.sh install --airplay-delay -2.0 --with-shortcut
```

To offer the shortcut after the watcher is already installed:

```bash
bash scripts/manage.sh install-shortcut
```

The shortcut is named `SenPlayer · 自动同步`. It starts or repairs the LaunchAgent and shows a notification; automatic switching does not depend on clicking it. Opening the signed `.shortcut` file displays Apple's import screen. Let the user review and confirm the final import rather than replacing any shortcut silently.

### 3. Verify

Always verify after install or update:

```bash
bash scripts/manage.sh status
```

Report the detected output, current SenPlayer delay, LaunchAgent state, configured AirPlay delay, and whether the log shows the watcher waiting for output changes. A healthy idle watcher is expected to keep running.

If practical, ask the user to switch once between the Mac speaker and AirPort/AirPlay, then rerun `status`. Do not change their output device without authorization.

### 4. Operate and diagnose

Apply the rule once without reinstalling:

```bash
bash scripts/manage.sh once
```

Show service state and recent logs:

```bash
bash scripts/manage.sh status
bash scripts/manage.sh logs
```

Read [troubleshooting.md](references/troubleshooting.md) when detection, preference writes, relaunching, signing, or launchd behavior is abnormal.

### 5. Remove

After explicit confirmation:

```bash
bash scripts/manage.sh uninstall --yes
```

This removes only the files installed by this skill. It leaves SenPlayer, its delay preference, imported Shortcuts, and the diagnostic log untouched. Tell the user that they can manually delete the optional shortcut and set SenPlayer back to `0.0` if desired.

## Behavior to explain

- AirPort Express/AirPlay buffering is normally around two seconds and cannot be eliminated by changing an AirPort setting.
- The value `-2.0` is SenPlayer-side A/V compensation used only on the Mac running SenPlayer.
- iPhone and iPad playback do not inherit this Mac preference. Music usually needs no compensation because there is no picture to synchronize.
- SenPlayer is gracefully quit and reopened only after an actual delay change because it may cache this preference while running.
