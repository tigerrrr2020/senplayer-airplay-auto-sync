# Troubleshooting SenPlayer AirPlay Auto Sync

## What the automation changes

The watcher writes SenPlayer's sandbox preference:

- Domain path: `~/Library/Containers/com.wuziqi.SenPlayer/Data/Library/Preferences/com.wuziqi.SenPlayer`
- Key: `kGlobalAudioDelay`
- AirPlay/AirPort default: `-2.0`
- Other outputs: `0.0`

It monitors CoreAudio's default output-device property. It classifies a device as AirPlay when CoreAudio reports the AirPlay transport type or the device name/UID contains `AirPlay` or `AirPort`.

## No audio devices are listed

A sandboxed terminal can prevent CoreAudio from initializing in the logged-in GUI audio session. Rerun `probe` or `status` outside that restricted sandbox. An empty `[]` is not enough evidence that the Mac has no devices.

The LaunchAgent must run in the user's Aqua session. Do not wrap the executable in `/usr/bin/env -i`; stripping the environment can prevent CoreAudio initialization.

## SenPlayer preference container is missing

Install SenPlayer and open it once. The App Sandbox container should then exist. Do not invent another preference domain unless inspection of the installed app proves the bundle identifier has changed.

If a future SenPlayer version changes the preference key, inspect its preferences before modifying the Swift source. Do not write guessed keys.

## Output is misclassified

Run `probe` and inspect the default device's `transport`, `name`, and `uid`.

- AirPlay normally reports CoreAudio's AirPlay transport.
- A renamed AirPort Express may have no `AirPort` text in its display name, so transport is the primary signal.
- Aggregate, virtual, multi-output, or third-party routing devices may require an explicit detection rule. Confirm the desired behavior with the user before adding a name/UID match.

## Delay changed but playback still uses the old timing

SenPlayer may cache `kGlobalAudioDelay` while running. The watcher gracefully terminates and reopens it only when the value changes. If termination does not finish within five seconds, it skips the preference write rather than force-quitting during playback.

Do not force-quit automatically unless the user explicitly accepts the risk of losing playback state.

## LaunchAgent will not start

Check:

```bash
bash scripts/manage.sh status
bash scripts/manage.sh logs
```

Common causes:

- The binary was replaced while launchd still held its old code-signing identity. The installer avoids this by booting out the service before an atomic replacement.
- Swift compilation failed because Command Line Tools are missing.
- The plist does not pass `plutil -lint`.
- The process is outside the active GUI session.

Re-running `install` is the supported repair path; it is idempotent and preserves the configured delay passed on that invocation.

## Optional Shortcut will not import or run

Run `install-shortcut` to reopen the signed asset. Apple intentionally requires the user to review and confirm imported shortcuts; do not bypass that screen or edit the Shortcuts database directly.

The shortcut named `SenPlayer · 自动同步` does not implement audio detection itself. It starts or repairs `com.codex.senplayer-airplay-auto-sync`, so install the watcher before using it. If the shortcut reports that the service is missing, run `install` again.

Do not overwrite a shortcut with the same name. Ask the user to rename or remove the old copy before importing if Shortcuts reports a conflict.

## Calibrating a different delay

AirPlay latency can vary by receiver generation and firmware. Reinstall with the measured compensation:

```bash
bash scripts/manage.sh install --airplay-delay -2.15
```

Negative values match the SenPlayer convention used by this automation. Verify lip sync with spoken dialogue, claps, or hard cuts. Do not assume music playback is out of sync simply because AirPlay buffers audio; without a picture, the startup buffer is not an A/V synchronization error.

## iPhone and iPad

The Mac's SenPlayer preference and LaunchAgent do not affect iOS or iPadOS. AirPlay-aware apps generally account for receiver latency through the platform. If one iOS app has lip-sync problems, troubleshoot that app and route separately; do not copy this Mac preference to the AirPort device.
