import AppKit

func command(_ path: String, _ arguments: [String]) -> (Int32, String) {
    let task = Process(), pipe = Pipe()
    task.executableURL = URL(fileURLWithPath: path)
    task.arguments = arguments
    task.standardOutput = pipe
    task.standardError = pipe
    do { try task.run() } catch { return (-1, error.localizedDescription) }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()
    return (task.terminationStatus, String(data: data, encoding: .utf8) ?? "")
}
func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

final class Lab: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    let profiles = NSPopUpButton(), interfaces = NSPopUpButton()
    let keepRunning = NSButton(checkboxWithTitle: "Keep running until I press Restore", target: nil, action: nil)
    let detail = NSTextField(wrappingLabelWithString: "")
    let stateTitle = NSTextField(labelWithString: "Ready to start")
    let stateDetail = NSTextField(wrappingLabelWithString: "Your connection has not been changed.")
    let progress = NSProgressIndicator()
    let start = NSButton(title: "Start 30-second test", target: nil, action: nil)
    let stop = NSButton(title: "Restore connection", target: nil, action: nil)
    var devices: [String] = []
    var busy = false, restoring = false, sawState = false, active = false
    var timer: Timer?
    var knownPhase = "idle"
    var lastProfile = "choppy"
    var observer: NSObjectProtocol?
    let preview = CommandLine.arguments.contains("--preview")
    let identifiers = ["choppy", "severe", "blackout"]
    let durations = [30.0, 30.0, 5.0]
    var resources: URL { Bundle.main.resourceURL! }

    func label(_ text: String, size: CGFloat = 13, color: NSColor = .labelColor) -> NSTextField {
        let v = NSTextField(wrappingLabelWithString: text)
        v.font = .systemFont(ofSize: size)
        v.textColor = color
        return v
    }
    func row(_ views: [NSView]) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .horizontal; s.spacing = 12; s.alignment = .centerY
        return s
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let menu = NSMenu(), item = NSMenuItem(), submenu = NSMenu()
        submenu.addItem(withTitle: "About Zoom Lag Lab", action: #selector(about), keyEquivalent: "")
        submenu.addItem(.separator())
        submenu.addItem(withTitle: "Quit Zoom Lag Lab", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = submenu; menu.addItem(item); NSApp.mainMenu = menu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 570, height: 620), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Zoom Lag Lab"; window.delegate = self
        let stack = NSStackView()
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 25)
        ])
        stack.addArrangedSubview(label("LOCAL CONNECTION CONTROL", size: 11, color: .secondaryLabelColor))
        let title = label("Make your meeting choppy", size: 26)
        title.font = .systemFont(ofSize: 26, weight: .bold)
        stack.addArrangedSubview(title)
        stack.addArrangedSubview(label("Create real packet dropouts for Zoom’s camera and microphone. Start the effect, then press Restore connection when you are done.", color: .secondaryLabelColor))
        profiles.addItems(withTitles: ["Choppy", "Severe", "Complete interruption"])
        profiles.target = self; profiles.action = #selector(profileChanged)
        profiles.widthAnchor.constraint(equalToConstant: 305).isActive = true
        let testLabel = label("Effect"); testLabel.widthAnchor.constraint(equalToConstant: 75).isActive = true
        stack.addArrangedSubview(row([testLabel, profiles]))
        detail.font = .systemFont(ofSize: 12); detail.textColor = .secondaryLabelColor
        stack.addArrangedSubview(detail)
        keepRunning.state = .on
        keepRunning.target = self; keepRunning.action = #selector(profileChanged)
        stack.addArrangedSubview(keepRunning)
        let connection = label("Connection"); connection.widthAnchor.constraint(equalToConstant: 75).isActive = true
        interfaces.widthAnchor.constraint(equalToConstant: 305).isActive = true
        let refresh = NSButton(title: "Refresh", target: self, action: #selector(refreshDevices))
        stack.addArrangedSubview(row([connection, interfaces, refresh]))
        stack.addArrangedSubview(label("Affects all apps on this connection. Disconnect VPNs and turn off Internet Sharing. Use one active internet connection.", size: 12, color: .secondaryLabelColor))
        let divider = NSBox(); divider.boxType = .separator
        stack.addArrangedSubview(divider); divider.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stateTitle.font = .systemFont(ofSize: 17, weight: .semibold)
        stack.addArrangedSubview(stateTitle)
        stateDetail.font = .systemFont(ofSize: 13); stateDetail.textColor = .secondaryLabelColor
        stack.addArrangedSubview(stateDetail)
        progress.style = .bar; progress.isIndeterminate = false; progress.minValue = 0; progress.maxValue = 1
        stack.addArrangedSubview(progress); progress.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        start.target = self; start.action = #selector(startTest); start.bezelStyle = .rounded
        start.keyEquivalent = "\r"
        stop.target = self; stop.action = #selector(restore); stop.bezelStyle = .rounded
        stack.addArrangedSubview(row([start, stop]))
        let help = NSButton(title: "How it works & help", target: self, action: #selector(about))
        help.bezelStyle = .rounded; stack.addArrangedSubview(help)
        stack.addArrangedSubview(label("macOS will ask for administrator approval to change network settings. No Terminal commands are needed.", size: 11, color: .tertiaryLabelColor))
        for view in [detail, stateDetail] { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        profileChanged(); refreshDevices(); updateStatus()
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in self?.updateStatus() }
        window.contentView!.layoutSubtreeIfNeeded()
        window.setContentSize(NSSize(width: 570, height: stack.fittingSize.height + 50))
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc func profileChanged() {
        let i = max(0, profiles.indexOfSelectedItem)
        let continuous = keepRunning.state == .on
        let ending = continuous ? " Repeats until you press Restore." : " Repeats for 30 seconds."
        detail.stringValue = [
            "Drops packets for 1 second, then allows 2 seconds of recovery." + ending,
            "Drops packets for 3 seconds, then allows 1 second of recovery." + ending,
            continuous ? "Blocks this connection until you press Restore. Your meeting may disconnect." : "Drops all packets for 5 seconds, then restores the connection."
        ][i]
        start.title = continuous ? "Start lag" : "Start \(Int(durations[i]))-second run"
    }
    @objc func refreshDevices() {
        guard !busy else { return }
        interfaces.removeAllItems(); devices.removeAll()
        if preview {
            interfaces.addItem(withTitle: "Wi-Fi (en0) — preview only"); devices = ["en0"]
        } else {
            let (_, output) = command("/usr/sbin/networksetup", ["-listallhardwareports"])
            var name = "Connection"
            for line in output.components(separatedBy: .newlines) {
                if line.hasPrefix("Hardware Port: ") { name = String(line.dropFirst(15)) }
                if line.hasPrefix("Device: ") {
                    let device = String(line.dropFirst(8)).trimmingCharacters(in: .whitespaces)
                    if device.range(of: "^en[0-9]+$", options: .regularExpression) != nil {
                        devices.append(device); interfaces.addItem(withTitle: "\(name) (\(device))")
                    }
                }
            }
            let (_, route) = command("/sbin/route", ["-n", "get", "default"])
            let current = route.components(separatedBy: .newlines).first { $0.contains("interface:") }?.components(separatedBy: "interface:").last?.trimmingCharacters(in: .whitespaces)
            if let current = current, let index = devices.firstIndex(of: current) { interfaces.selectItem(at: index) }
            if current?.hasPrefix("utun") == true {
                stateTitle.stringValue = "Disconnect your VPN first"
                stateDetail.stringValue = "Then click Refresh to find your Wi-Fi or Ethernet connection."
                devices.removeAll(); interfaces.removeAllItems()
            }
        }
        if devices.isEmpty {
            interfaces.addItem(withTitle: "No usable connection found")
            if stateTitle.stringValue != "Disconnect your VPN first" {
                stateTitle.stringValue = "Check your connection"
                stateDetail.stringValue = "Connect to Wi-Fi or Ethernet, then click Refresh."
            }
        } else if !active {
            stateTitle.stringValue = "Ready to start"
            stateDetail.stringValue = "Start with Choppy in a private meeting."
        }
        start.isEnabled = !devices.isEmpty && !active && !preview
    }
    func privileged(_ action: String, completion: @escaping (Int32, String) -> Void) {
        let runner = resources.appendingPathComponent("RunPrivileged.applescript").path
        let helper = resources.appendingPathComponent("lag.sh")
        guard let script = try? String(contentsOf: helper, encoding: .utf8) else {
            completion(-1, "The app’s network helper is missing. Extract a fresh copy of the app.")
            return
        }
        // Read bundled code as the user before elevation: root cannot read protected Documents paths.
        let shell = "/bin/bash -c " + quote(script) + " zoom-lag-lab " + action
        DispatchQueue.global(qos: .userInitiated).async {
            let result = command("/usr/bin/osascript", [runner, shell])
            DispatchQueue.main.async { completion(result.0, result.1) }
        }
    }
    @objc func startTest() {
        guard !busy && !active && !preview, devices.indices.contains(interfaces.indexOfSelectedItem) else { return }
        busy = true; sawState = false; progress.doubleValue = 0
        lastProfile = identifiers[profiles.indexOfSelectedItem]
        start.isEnabled = false; profiles.isEnabled = false; interfaces.isEnabled = false; stop.isEnabled = false
        stateTitle.stringValue = "Approve to start"
        stateDetail.stringValue = "Use the macOS administrator prompt. The effect starts after setup succeeds."
        let mode = keepRunning.state == .on ? "continuous" : "timed"
        let action = "start " + lastProfile + " " + quote(devices[interfaces.indexOfSelectedItem]) + " " + mode + " " + String(ProcessInfo.processInfo.processIdentifier)
        privileged(action) { [weak self] code, output in
            guard let self = self else { return }
            self.busy = false; self.profiles.isEnabled = true; self.interfaces.isEnabled = true; self.stop.isEnabled = !self.restoring
            self.updateStatus()
            if code == 0 {
                if self.knownPhase == "idle" {
                    self.stateTitle.stringValue = "Connection restored"
                    self.stateDetail.stringValue = "The temporary packet-drop rules have been removed."
                    self.progress.doubleValue = 1
                }
            } else if output.contains("-128") {
                self.stateTitle.stringValue = "Start canceled"
                self.stateDetail.stringValue = "Administrator approval was canceled."
            } else {
                self.showError("The effect stopped with an error", output)
            }
        }
    }
    @objc func restore() {
        guard !restoring && !preview else { return }
        if !FileManager.default.fileExists(atPath: "/var/run/zoom-lag-lab") {
            stateTitle.stringValue = "No effect is active"
            stateDetail.stringValue = "There are no saved Zoom Lag Lab changes to restore."
            return
        }
        restoring = true; stop.isEnabled = false; start.isEnabled = false
        stateTitle.stringValue = "Restoring connection…"
        stateDetail.stringValue = "Approve the macOS prompt if it appears."
        privileged("stop") { [weak self] code, output in
            guard let self = self else { return }
            self.restoring = false; self.stop.isEnabled = true; self.updateStatus()
            if code == 0 && self.knownPhase == "idle" {
                self.stateTitle.stringValue = "Connection restored"
                self.stateDetail.stringValue = "No Zoom Lag Lab network changes remain."
                self.progress.doubleValue = 1
            } else if code != 0 { self.showError("Restore needs attention", output) }
        }
    }
    func updateStatus() {
        guard !preview else { start.isEnabled = false; stop.isEnabled = false; return }
        let path = "/var/run/zoom-lag-lab/status"
        let fallback = FileManager.default.fileExists(atPath: "/var/run/zoom-lag-lab") ? "error\n0\n\n\n" : "idle\n0\n\n\n"
        let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? fallback
        let fields = text.components(separatedBy: .newlines)
        let phase = fields.first ?? "idle"
        knownPhase = phase; active = phase != "idle"
        let continuous = phase == "active" && fields.count > 1 && fields[1] == "0"
        if progress.isIndeterminate != continuous {
            progress.isIndeterminate = continuous
            if continuous { progress.startAnimation(nil) } else { progress.stopAnimation(nil) }
        }
        if active { sawState = true }
        if !restoring {
            if phase == "active", fields.count >= 4 {
                let remaining = max(0, Int(ceil((Double(fields[1]) ?? 0) - Date().timeIntervalSince1970)))
                let duration = fields[3] == "blackout" ? 5.0 : 30.0
                stateTitle.stringValue = continuous ? "Lag is running · until Restore" : (remaining > 0 ? "Lag active · \(remaining) seconds left" : "Finishing…")
                let interval = fields.count > 4 && fields[4] == "recovery" ? "Recovery interval" : "Dropping packets"
                stateDetail.stringValue = "\(interval) on \(fields[2]). Click Restore connection to stop."
                if !continuous { progress.doubleValue = min(1, max(0, 1 - Double(remaining) / duration)) }
            } else if phase == "preparing" {
                stateTitle.stringValue = "Starting lag…"
                stateDetail.stringValue = "Checking and setting up temporary network controls."
            } else if phase == "restoring" {
                stateTitle.stringValue = "Restoring connection…"
                stateDetail.stringValue = "Removing the temporary packet-drop rules."
            } else if phase == "error" {
                stateTitle.stringValue = "Restore needs attention"
                stateDetail.stringValue = "Click Restore connection to retry. If it keeps failing, restart your Mac."
            } else if phase == "idle" && sawState && !busy {
                stateTitle.stringValue = "Connection restored"
                stateDetail.stringValue = "The temporary packet-drop rules have been removed."
                progress.doubleValue = 1
            }
        }
        start.isEnabled = !busy && !restoring && !active && !devices.isEmpty
        stop.isEnabled = !restoring && (!busy || active)
        profiles.isEnabled = !busy && !active
        interfaces.isEnabled = !busy && !active
        keepRunning.isEnabled = !busy && !active && !restoring
    }
    func showError(_ title: String, _ message: String) {
        let alert = NSAlert(); alert.messageText = title
        alert.informativeText = String(message.suffix(2200))
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    @objc func about() {
        let alert = NSAlert()
        alert.messageText = "Real dropouts, until you press Restore"
        alert.informativeText = "macOS temporarily blocks packets on this Mac’s selected connection, then removes the block. Both incoming and outgoing Zoom audio and video traffic are affected. The short recovery intervals produce repeated dropouts; this app does not add precise latency or cap bandwidth.\n\n1. Join a private meeting and watch from another device.\n2. Choose Choppy or Severe, then click Start lag.\n3. Approve the macOS password prompt.\n4. Click Restore connection when you are done. Uncheck Keep running for a short timed run.\n\nAll apps on the chosen connection are affected. Internet Sharing must be off. Avoid VPNs and multiple active connections. If the controlling app exits, its worker restores the connection. A worker crash or system failure may require reopening Restore or restarting the Mac.\n\nReal packet blocking and recovery verified on macOS Tahoe 26.6.2. The appearance of Zoom audio/video still needs a private meeting check."
        alert.addButton(withTitle: "Got it"); alert.addButton(withTitle: "Full guide")
        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.open(resources.appendingPathComponent("Guide.html"))
        }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if busy || active || restoring {
            let alert = NSAlert(); alert.messageText = "Lag or restoration is still running"
            alert.informativeText = "Keep the app open to see restoration complete. Click Restore connection to stop the effect before quitting."
            alert.addButton(withTitle: "Keep open")
            alert.runModal(); window.makeKeyAndOrderFront(nil)
            return .terminateCancel
        }
        return .terminateNow
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApp.terminate(nil)
        return false
    }
}
let app = NSApplication.shared
let delegate = Lab()
app.delegate = delegate
app.run()
