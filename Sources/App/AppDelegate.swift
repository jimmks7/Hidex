import Cocoa
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, HIDPPSessionDelegate {
    private var statusItem: NSStatusItem!
    private var accessibilityTimer: Timer?
    private let session = HIDPPSession()
    private let engine = GestureEngine()
    private let preferences = PreferencesWindowController()
    private let gestureLab = GestureLabWindowController()
    private var statusTitle = L10n.searchingDevice
    private var enabled = true
    private var battery = BatteryInfo.unknown

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLog.reset()
        AppLog.log("\(L10n.appName) launched (\(L10n.versionLabel)) lang=\(L10n.lang)")
        session.delegate = self
        setupMenuBar()
        enableLoginItemOnFirstLaunch()
        ensureAccessibilityAndStart()

        NotificationCenter.default.addObserver(
            forName: .hidexConfigDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            self?.engine.reloadConfig()
            self?.rebuildMenu()
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(onSystemWake),
            name: NSWorkspace.didWakeNotification, object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppLog.log("Terminating — disable raw mode")
        session.stop()
        Thread.sleep(forTimeInterval: 0.35)
    }

    // MARK: - HIDPPSessionDelegate

    func hidppSession(_ session: HIDPPSession, didReceive frame: TouchPadRawFrame) {
        guard enabled else { return }
        engine.applyInfo(session.touchPadInfo)
        engine.handle(frame: frame)
    }

    func hidppSession(_ session: HIDPPSession, statusChanged message: String) {
        statusTitle = message
        AppLog.log(message)
        updateStatusItemAppearance()
        rebuildMenu()
    }

    func hidppSession(_ session: HIDPPSession, batteryUpdated info: BatteryInfo) {
        battery = info
        updateStatusItemAppearance()
        rebuildMenu()
    }

    // MARK: - Lifecycle

    @objc private func onSystemWake() {
        AppLog.log("Wake — reconnect in 2s")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.session.forceReconnect()
        }
    }

    private func ensureAccessibilityAndStart() {
        enabled = true
        engine.deferPointerToNative = true
        session.start()
        updateStatusItemAppearance()
        rebuildMenu()

        let ax = AXIsProcessTrusted()
        AppLog.log(
            "Accessibility trusted=\(ax) — Spaces ←→ need AX+Automation; " +
            "MC ↑/↓ uses Mission Control.app (no AX)"
        )
        if ax {
            statusTitle = L10n.gesturesActive
            updateStatusItemAppearance()
        } else {
            statusTitle = L10n.enableAccessibility
            updateStatusItemAppearance()
            // Recent macOS often never shows the TCC popup — open Settings + help alert.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                InputInjector.requestAccessibilityFromMenu()
            }
            accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
                guard let self else { return }
                if AXIsProcessTrusted() {
                    AppLog.log("Accessibility trusted=true — Spaces ready")
                    timer.invalidate()
                    self.statusTitle = L10n.gesturesActive
                    self.updateStatusItemAppearance()
                    self.rebuildMenu()
                }
            }
        }
    }

    // MARK: - Menu / touchpad+battery icon

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateStatusItemAppearance()
        rebuildMenu()
    }

    private func updateStatusItemAppearance() {
        guard let btn = statusItem?.button else { return }
        btn.image = StatusItemIcon.image(percent: battery.percent, charging: battery.charging)
        btn.imagePosition = .imageOnly
        btn.title = ""
        btn.toolTip = "\(L10n.appName) — \(statusTitle)"
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let cfg = engine.config

        let title = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        let batLabel: String
        if let pct = battery.percent {
            batLabel = L10n.batteryPercent(pct, charging: battery.charging)
        } else if battery.charging {
            batLabel = L10n.batteryChargingUnknown
        } else {
            batLabel = L10n.batteryUnknown
        }
        let batItem = NSMenuItem(title: batLabel, action: nil, keyEquivalent: "")
        batItem.isEnabled = false
        menu.addItem(batItem)
        menu.addItem(.separator())

        let prefs = NSMenuItem(title: L10n.preferences, action: #selector(openPreferences(_:)), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)

        let toggle = NSMenuItem(
            title: enabled ? L10n.pauseGestures : L10n.resumeGestures,
            action: #selector(toggleEnabled(_:)), keyEquivalent: "p"
        )
        toggle.target = self
        menu.addItem(toggle)

        let reconnect = NSMenuItem(title: L10n.reconnectHID, action: #selector(reconnect(_:)), keyEquivalent: "r")
        reconnect.target = self
        menu.addItem(reconnect)

        menu.addItem(.separator())

        let gestures = NSMenuItem(title: L10n.currentGestures, action: nil, keyEquivalent: "")
        gestures.isEnabled = false
        menu.addItem(gestures)
        menu.addItem(infoItem("3↑  \(cfg.threeFingerUp.displayName)"))
        menu.addItem(infoItem("3↓  \(cfg.threeFingerDown.displayName)"))
        menu.addItem(infoItem("3/4←→ \(cfg.threeFingerLeft.displayName) / \(cfg.threeFingerRight.displayName)"))
        menu.addItem(infoItem("4↑  \(cfg.fourFingerUp.displayName)"))
        menu.addItem(infoItem("4↓  \(cfg.fourFingerDown.displayName)"))
        menu.addItem(infoItem(L10n.twoFingerNativeScroll))
        if cfg.doubleTapMaximize {
            menu.addItem(infoItem(L10n.t("2× toque  Maximizar", "2× tap  Maximize")))
        }

        menu.addItem(.separator())

        let labItem = NSMenuItem(
            title: L10n.gestureLab,
            action: #selector(openGestureLab(_:)), keyEquivalent: "g"
        )
        labItem.target = self
        menu.addItem(labItem)

        let diagItem = NSMenuItem(
            title: L10n.diagnoseSpaces,
            action: #selector(diagnoseSpaces(_:)), keyEquivalent: ""
        )
        diagItem.target = self
        menu.addItem(diagItem)

        let axItem = NSMenuItem(
            title: AXIsProcessTrusted() ? L10n.accessibilityOK : L10n.enableAccessibilityMenu,
            action: #selector(requestAccessibility(_:)), keyEquivalent: ""
        )
        axItem.target = self
        menu.addItem(axItem)

        let autoItem = NSMenuItem(
            title: L10n.allowAutomation,
            action: #selector(requestAutomation(_:)), keyEquivalent: ""
        )
        autoItem.target = self
        menu.addItem(autoItem)

        let relaunchItem = NSMenuItem(
            title: L10n.relaunchApp,
            action: #selector(relaunch(_:)), keyEquivalent: ""
        )
        relaunchItem.target = self
        menu.addItem(relaunchItem)

        let logItem = NSMenuItem(title: L10n.openLog, action: #selector(openLog(_:)), keyEquivalent: "l")
        logItem.target = self
        menu.addItem(logItem)

        let login = NSMenuItem(title: L10n.startAtLogin, action: #selector(toggleLogin(_:)), keyEquivalent: "")
        login.target = self
        login.state = UserDefaults.standard.bool(forKey: "startAtLogin") ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())

        let ver = NSMenuItem(title: L10n.versionLabel, action: #selector(showAbout(_:)), keyEquivalent: "")
        ver.target = self
        menu.addItem(ver)

        menu.addItem(NSMenuItem(title: L10n.quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    private func infoItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: "  " + title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // MARK: - Actions

    @objc private func openPreferences(_ sender: Any?) {
        preferences.show()
    }

    @objc private func toggleEnabled(_ sender: NSMenuItem) {
        enabled.toggle()
        rebuildMenu()
    }

    @objc private func reconnect(_ sender: Any?) {
        statusTitle = L10n.reconnecting
        updateStatusItemAppearance()
        rebuildMenu()
        session.forceReconnect()
    }

    @objc private func openLog(_ sender: Any?) {
        NSWorkspace.shared.open(AppLog.fileURL)
    }

    @objc private func openGestureLab(_ sender: Any?) {
        gestureLab.show()
    }

    @objc private func diagnoseSpaces(_ sender: Any?) {
        let text = SpaceSwitcher.diagnose()
        let alert = NSAlert()
        alert.messageText = L10n.spacesDiagnosisTitle
        alert.informativeText = text + "\n\n" + L10n.t(
            "Prueba también 3 dedos ←→ y revisa ~/.hidex.log",
            "Also try 3-finger ←→ and check ~/.hidex.log"
        )
        alert.addButton(withTitle: L10n.ok)
        if !AXIsProcessTrusted() {
            alert.addButton(withTitle: L10n.openAccessibility)
        }
        if alert.runModal() == .alertSecondButtonReturn {
            InputInjector.requestAccessibilityFromMenu()
        }
    }

    @objc private func requestAccessibility(_ sender: Any?) {
        InputInjector.requestAccessibilityFromMenu()
    }

    @objc private func relaunch(_ sender: Any?) {
        InputInjector.relaunchApp()
    }

    @objc private func requestAutomation(_ sender: Any?) {
        _ = InputInjector.ensureAutomationPermission(prompt: true)
        _ = SpaceSwitcher.move(.right)
    }

    @objc private func showAbout(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = L10n.appName
        alert.informativeText = L10n.t(
            """
            \(L10n.versionLabel)

            Gestos multitouch en espacio de usuario para touchpads inalámbricos HID++ en macOS.
            Hardware compatible documentado: Logitech T650 + receptor Unifying.

            No afiliado a Logitech ni Apple. Licencia MIT.
            """,
            """
            \(L10n.versionLabel)

            User-space multitouch gestures for wireless HID++ touchpads on macOS.
            Documented compatible hardware: Logitech T650 + Unifying receiver.

            Not affiliated with Logitech or Apple. MIT License.
            """
        )
        alert.addButton(withTitle: L10n.ok)
        alert.runModal()
    }

    @objc private func toggleLogin(_ sender: NSMenuItem) {
        let on = sender.state != .on
        sender.state = on ? .on : .off
        UserDefaults.standard.set(on, forKey: "startAtLogin")
        do {
            if on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            AppLog.log("SMAppService: \(error)")
        }
    }

    private func enableLoginItemOnFirstLaunch() {
        guard !UserDefaults.standard.bool(forKey: "didFirstLaunch") else { return }
        UserDefaults.standard.set(true, forKey: "didFirstLaunch")
        UserDefaults.standard.set(true, forKey: "startAtLogin")
        try? SMAppService.mainApp.register()
    }
}
