# Zoom Lag Lab beta — user guide

Zoom Lag Lab creates real packet dropouts on your Mac’s selected Wi-Fi or Ethernet interface. All apps using that connection are affected, including Zoom audio and video. It does not configure the router or other devices, and it does not provide a precise latency or bandwidth cap.

## Start and stop

1. Open Zoom Lag Lab.app and choose your active connection.
2. Choose Choppy or Severe. Leave Keep running until I press Restore checked for continuous operation.
3. Click Start lag and approve the standard macOS administrator prompt.
4. Click Restore connection when finished. Wait for Connection restored.

| Preset | Drop packets | Allow recovery | Default run length |
|---|---|---|---|
| Choppy | 1 second | 2 seconds | Until Restore |
| Severe | 3 seconds | 1 second | Until Restore |
| Complete interruption | Continuously | None | Until Restore |

Uncheck Keep running to use the optional timed mode: 30 seconds for Choppy/Severe or 5 seconds for Complete interruption. Timing is approximate. Heavy loss can disconnect a meeting instead of merely making it choppy.

## Requirements

Use macOS Tahoe 26 or later and an administrator account. Disconnect VPNs, turn off Internet Sharing, and use one active internet connection. The helper refuses to start when PF is already enabled, existing connection states could bypass the effect, forwarding is enabled, or its required Apple anchor is missing.

Internet Sharing must remain off throughout the session so this Mac is not carrying other devices’ traffic. Multiple active interfaces may let an app bypass the selected connection.

## Recovery

Continuous mode has no automatic time limit. Use Restore connection to stop it. The worker also watches the controlling app’s process and removes its rules if that process exits. If the worker itself is force-killed or cleanup fails, reopen the app and click Restore connection. Restart the Mac if recovery repeatedly fails; the app installs no startup service. Toggling Wi-Fi alone does not remove PF rules.

Connection restored confirms removal of this app’s controls; it does not diagnose unrelated internet problems. Sleep or a system failure can delay cleanup.

## How it works

The Swift/AppKit interface reads its helper before requesting administrator access. The helper installs temporary packet-drop rules in its own PF child anchor, com.apple/000.zoom-lag-lab, and holds its own PF enable reference. Restore empties that child anchor and releases the reference.

It does not edit /etc/pf.conf, reload the global ruleset, flush other firewall states, or configure other devices. The app stores no password and does not request camera or microphone access.

## Optional Terminal commands

Open Terminal in the source repository folder containing lag.sh:

```sh
# Show the intended behavior without changing networking.
/bin/bash ./lag.sh preview severe en0 continuous

# Start continuous severe dropouts on en0.
sudo /bin/bash -c "$(/bin/cat ./lag.sh)" zoom-lag-lab start severe en0 continuous

# Restore from another Terminal window in the same folder.
sudo /bin/bash -c "$(/bin/cat ./lag.sh)" zoom-lag-lab stop
```

Press Control-C to stop a foreground Terminal run. Replace en0 with the intended physical interface if necessary; networksetup -listallhardwareports lists names. Reading the helper before elevation avoids asking a privileged shell to open a privacy-protected Documents path.

## Check your own Zoom session

Use a private meeting with a second device as receiver. Check received video/audio and Zoom’s media statistics before, during, and after the effect. The local camera preview can keep moving when outgoing traffic is being dropped. Zoom’s adaptation and loss concealment mean exact received stutter and sound vary.

## Distribution

The download contains Apple Silicon and Intel binaries. It is ad-hoc signed, not notarized. macOS may require review in System Settings, Privacy & Security before opening a downloaded copy. The source includes build and mocked regression-check scripts.
