# Zoom Lag Lab — v0.1.0-beta

The first public beta of a native macOS app that creates real, repeating network dropouts on your own Mac. Designed for private Zoom testing, it affects all apps on the selected Wi-Fi or Ethernet connection.

## Download and use

[Download Zoom Lag Lab beta for Mac](downloads/Zoom-Lag-Lab-v0.1.0-beta.zip?raw=true)

1. Unzip the download and open **Zoom Lag Lab.app**.
2. Choose **Choppy** or **Severe** and check your connection.
3. Leave **Keep running until I press Restore** checked for continuous operation.
4. Click **Start lag** and approve the standard macOS administrator prompt.
5. Click **Restore connection** when finished.

The app is ad-hoc signed and is not notarized. macOS may require review in **System Settings → Privacy & Security** before opening a downloaded copy. The app does not ask for camera or microphone access.

## Presets

| Effect | Packet-drop pattern | Default duration |
|---|---|---|
| Choppy | Drop for 1 second, allow 2 seconds | Until Restore |
| Severe | Drop for 3 seconds, allow 1 second | Until Restore |
| Complete interruption | Block continuously | Until Restore |

Optional timed mode lasts 30 seconds for Choppy/Severe or 5 seconds for Complete interruption. These are packet-drop patterns, not fixed latency or bandwidth settings. Severe loss may disconnect a meeting.

## Requirements and scope

- macOS Tahoe 26 or later; the download contains Apple Silicon and Intel binaries.
- Administrator access for temporary packet-filter rules.
- Internet Sharing off, VPN disconnected, and one active internet connection.
- PF must initially be disabled with no existing connection states; the helper refuses incompatible configurations.

Only the selected connection on this Mac is configured. All its apps are affected. Other devices must not be using this Mac as a router.

See the [testing instructions](docs/TESTING.md) and [full guide](Guide.md).

## Build from source

Install an Xcode toolchain with the macOS 26 SDK, then run from this repository:

```sh
bash source/build.sh
open 'dist/Zoom Lag Lab.app'
```

The build script creates the app bundle, builds both architectures, and ad-hoc signs the result. It does not change network settings. The prebuilt download is in `downloads/`.

## Regression checks

```sh
python3 source/test_helper.py
```

These checks use mocked commands and do not change networking or need administrator access.

## Recovery

Click **Restore connection**. The worker also restores if the controlling app exits. If the worker itself is force-killed, reopen the app and click Restore. A Mac restart clears its temporary rules. Turning Wi-Fi off and back on does not remove packet-filter rules.

## Implementation

`source/App.swift` provides the AppKit interface. `lag.sh` manages only the app’s child PF anchor and its own enable reference. It does not edit `/etc/pf.conf`, reload global rules, or flush existing firewall states. This beta uses packet blocking; it does not provide precise dummynet latency or bandwidth controls.
