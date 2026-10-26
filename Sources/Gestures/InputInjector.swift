import AppKit
import ApplicationServices
import CoreGraphics

/// System gesture injection.
/// - Mission Control open/close: toggle via Mission Control.app (no Automation) — do not change lightly.
/// - Spaces: System Events via SpaceSwitcher (no Automation pre-check; no per-swipe prompts).
enum InputInjector {

    private static var leftDown = false
    private static var missionControlOpen = false
    /// One-shot soft notice for Spaces permission issues (no Settings spam).
    private static var didNoteSpacesPermission = false

    private static let keyLeft: CGKeyCode = 0x7B
    private static let keyRight: CGKeyCode = 0x7C
    private static let keyDown: CGKeyCode = 0x7D
    private static let keyEscape: CGKeyCode = 0x35
    private static let keyControl: CGKeyCode = 0x3B
    private static let keyCommand: CGKeyCode = 0x37
    private static let keyShift: CGKeyCode = 0x38
    private static let keyOption: CGKeyCode = 0x3A
    private static let keyF11: CGKeyCode = 0x67

    private static let missionControlURL = URL(fileURLWithPath: "/System/Applications/Mission Control.app")

    // MARK: - Pointer

    static func movePointer(dx: CGFloat, dy: CGFloat) {
        let cdx = max(-120, min(120, dx))
        let cdy = max(-120, min(120, dy))
        guard abs(cdx) > 0.01 || abs(cdy) > 0.01 else { return }
        let loc = NSEvent.mouseLocation
        guard let screen = NSScreen.main else { return }
        let cgPoint = CGPoint(x: loc.x + cdx, y: (screen.frame.height - loc.y) + cdy)
        let type: CGEventType = leftDown ? .leftMouseDragged : .mouseMoved
        if let move = CGEvent(mouseEventSource: nil, mouseType: type,
                              mouseCursorPosition: cgPoint, mouseButton: .left) {
            move.post(tap: .cghidEventTap)
        }
    }

    static func setLeftButton(_ down: Bool) {
        guard down != leftDown else { return }
        leftDown = down
        let loc = cgMouseLocation()
        let src = CGEventSource(stateID: .hidSystemState)
        let type: CGEventType = down ? .leftMouseDown : .leftMouseUp
        if let e = CGEvent(mouseEventSource: src, mouseType: type,
                           mouseCursorPosition: loc, mouseButton: .left) {
            e.post(tap: .cghidEventTap)
        }
    }

    /// Soft tap → click. Uses HID-system source + Quartz cursor coords (not AppKit Y-flip),
    /// which is what actually registers on recent macOS; bare `nil` source often no-ops.
    static func click(button: CGMouseButton = .left) {
        let loc = cgMouseLocation()
        let src = CGEventSource(stateID: .hidSystemState)
        let downType: CGEventType = button == .left ? .leftMouseDown :
            (button == .right ? .rightMouseDown : .otherMouseDown)
        let upType: CGEventType = button == .left ? .leftMouseUp :
            (button == .right ? .rightMouseUp : .otherMouseUp)

        guard let down = CGEvent(mouseEventSource: src, mouseType: downType,
                                 mouseCursorPosition: loc, mouseButton: button),
              let up = CGEvent(mouseEventSource: src, mouseType: upType,
                               mouseCursorPosition: loc, mouseButton: button)
        else {
            AppLog.log("Click inject create failed button=\(button.rawValue)")
            return
        }
        if button == .center {
            down.setIntegerValueField(.mouseEventButtonNumber, value: 2)
            up.setIntegerValueField(.mouseEventButtonNumber, value: 2)
        }
        down.setIntegerValueField(.mouseEventClickState, value: 1)
        up.setIntegerValueField(.mouseEventClickState, value: 1)
        down.post(tap: .cghidEventTap)
        // Zero-gap down/up is often dropped by WindowServer on macOS 15+.
        usleep(16_000)
        up.post(tap: .cghidEventTap)
    }

    static func scroll(dx: CGFloat, dy: CGFloat) {
        let wheelY = Int32(dy.rounded())
        let wheelX = Int32(dx.rounded())
        guard wheelY != 0 || wheelX != 0 else { return }
        if let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                           wheelCount: 2, wheel1: wheelY, wheel2: wheelX, wheel3: 0) {
            e.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Mission Control (preserved behavior)

    private static func openMissionControlApp() {
        guard FileManager.default.fileExists(atPath: missionControlURL.path) else { return }
        NSWorkspace.shared.openApplication(at: missionControlURL, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: - Permissions (on-demand only)

    /// Query Automation without treating −600 (System Events not running) as denial.
    @discardableResult
    static func ensureAutomationPermission(prompt: Bool = false) -> Bool {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.systemevents")
        let status = AEDeterminePermissionToAutomateTarget(
            target.aeDesc, typeWildCard, typeWildCard, prompt
        )
        // -600 procNotFound: System Events idle — not a refusal.
        let ok = (status == OSStatus(noErr) || status == -600)
        AppLog.log("Automation System Events status=\(status) ok=\(ok) prompt=\(prompt)")
        if status == -1743 && prompt {
            openAutomationSettings()
        }
        return ok
    }

    static func openAutomationSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation",
            "x-apple.systempreferences:com.apple.Settings.PrivacySecurity.extension?Privacy_Automation"
        ]
        for s in urls {
            if let u = URL(string: s) {
                NSWorkspace.shared.open(u)
                return
            }
        }
    }

    static func openAccessibilitySettings() {
        // macOS 13–27: try several deep links; System Settings still uses the
        // x-apple.systempreferences scheme (not x-apple.systemsettings).
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.Settings.PrivacySecurity.extension?Privacy_Accessibility"
        ]
        for s in urls {
            if let u = URL(string: s), NSWorkspace.shared.open(u) {
                AppLog.log("Opened Accessibility settings via \(s)")
                return
            }
        }
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") {
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
            AppLog.log("Opened System Settings (no deep link worked)")
        }
    }

    /// Open Settings + explain: on recent macOS the system AX dialog often never appears.
    static func requestAccessibilityFromMenu() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(opts)
        AppLog.log("Accessibility request prompt; trusted=\(trusted)")
        openAccessibilitySettings()
        if !trusted {
            DispatchQueue.main.async {
                showAccessibilityHelpAlert()
            }
        }
    }

    /// Manual steps — required when macOS suppresses the TCC popup.
    static func showAccessibilityHelpAlert() {
        let alert = NSAlert()
        alert.messageText = L10n.t(
            "Activa Accesibilidad para Hidex",
            "Enable Accessibility for Hidex"
        )
        alert.informativeText = L10n.t(
            """
            En macOS reciente el aviso del sistema a menudo no aparece. Hazlo a mano:

            1. Ajustes → Privacidad y seguridad → Accesibilidad
            2. Pulsa + y elige /Applications/Hidex.app
            3. Activa el interruptor de Hidex
            4. Vuelve aquí → menú Hidex → Reiniciar app

            Sin esto, Spaces ←→ no funcionan (Mission Control ↑ sí).
            """,
            """
            On recent macOS the system prompt often never appears. Do it manually:

            1. Settings → Privacy & Security → Accessibility
            2. Click + and choose /Applications/Hidex.app
            3. Turn on Hidex
            4. Come back → Hidex menu → Relaunch app

            Without this, Spaces ←→ will not work (Mission Control ↑ still does).
            """
        )
        alert.addButton(withTitle: L10n.openAccessibility)
        alert.addButton(withTitle: L10n.ok)
        if alert.runModal() == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
    }

    static func relaunchApp() {
        let path = Bundle.main.bundlePath
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = ["-c", "sleep 1; /usr/bin/open \"\(path)\""]
        try? proc.run()
        NSApp.terminate(nil)
    }

    private static func noteSpacesFailureOnce() {
        guard !didNoteSpacesPermission else { return }
        didNoteSpacesPermission = true
        switch SpaceSwitcher.lastFailure {
        case .accessibilityRequired:
            AppLog.log(
                "Spaces: Accesibilidad efectiva ausente (AXIsProcessTrusted=" +
                "\(AXIsProcessTrusted())). Menú → Diagnosticar Spaces…"
            )
        case .automationDenied:
            AppLog.log("Spaces: Automatización denegada para System Events. Menú → Permitir Automatización…")
        case .other(let s):
            AppLog.log("Spaces: fallo \(s)")
        case .none:
            break
        }
    }

    // MARK: - System Events helpers (non-Spaces actions)

    @discardableResult
    private static func systemEventsKey(_ code: Int, control: Bool) -> Bool {
        let using = control ? " using control down" : ""
        let source = """
        tell application "System Events"
          key code \(code)\(using)
        end tell
        """
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return false }
        _ = script.executeAndReturnError(&error)
        if let error {
            let num = error[NSAppleScript.errorNumber] as? Int ?? -1
            let msg = error[NSAppleScript.errorMessage] as? String ?? "\(error)"
            AppLog.log("System Events key \(code) err=\(num) \(msg.prefix(120))")
            return false
        }
        return true
    }

    private static func postShortcut(key: CGKeyCode, flags: CGEventFlags) {
        let src = CGEventSource(stateID: .hidSystemState)
        var mods: [(CGKeyCode, CGEventFlags)] = []
        if flags.contains(.maskControl) { mods.append((keyControl, .maskControl)) }
        if flags.contains(.maskCommand) { mods.append((keyCommand, .maskCommand)) }
        if flags.contains(.maskShift) { mods.append((keyShift, .maskShift)) }
        if flags.contains(.maskAlternate) { mods.append((keyOption, .maskAlternate)) }
        var downFlags: CGEventFlags = []
        for (modKey, modFlag) in mods {
            downFlags.insert(modFlag)
            if let e = CGEvent(keyboardEventSource: src, virtualKey: modKey, keyDown: true) {
                e.flags = downFlags
                e.post(tap: .cghidEventTap)
            }
        }
        if let down = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true) {
            down.flags = flags
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false) {
            up.flags = flags
            up.post(tap: .cghidEventTap)
        }
        for (modKey, _) in mods.reversed() {
            if let e = CGEvent(keyboardEventSource: src, virtualKey: modKey, keyDown: false) {
                e.flags = []
                e.post(tap: .cghidEventTap)
            }
        }
    }

    static func perform(_ action: GestureAction) {
        DispatchQueue.main.async {
            switch action {
            case .none:
                break

            case .missionControl:
                // PRESERVE: only OPEN; re-open while open would close.
                if missionControlOpen {
                    AppLog.log("MC already open — ignore ↑ (use ↓ to close)")
                    return
                }
                openMissionControlApp()
                missionControlOpen = true
                AppLog.log("Inject MC OPEN")

            case .dismiss:
                // PRESERVE: close via Mission Control.app toggle when we opened it.
                if missionControlOpen {
                    openMissionControlApp()
                    missionControlOpen = false
                    AppLog.log("Inject MC CLOSE (toggle .app)")
                } else if systemEventsKey(53, control: false) {
                    AppLog.log("Inject dismiss Esc (System Events)")
                } else {
                    postShortcut(key: keyEscape, flags: [])
                    AppLog.log("Inject dismiss Esc (CGEvent)")
                }

            case .appExpose:
                if systemEventsKey(125, control: true) {
                    AppLog.log("Inject App Exposé OK")
                } else {
                    postShortcut(key: keyDown, flags: .maskControl)
                }

            case .desktop:
                // Show Desktop = F11 (key 103), not Ctrl+F11.
                if systemEventsKey(103, control: false) {
                    AppLog.log("Inject Desktop OK (F11)")
                } else {
                    postShortcut(key: keyF11, flags: [])
                    AppLog.log("Inject Desktop CGEvent F11")
                }

            case .spaceLeft:
                if SpaceSwitcher.move(.left) {
                    AppLog.log("Inject Space ← OK")
                } else {
                    noteSpacesFailureOnce()
                    AppLog.log("Inject Space ← FAILED")
                }

            case .spaceRight:
                if SpaceSwitcher.move(.right) {
                    AppLog.log("Inject Space → OK")
                } else {
                    noteSpacesFailureOnce()
                    AppLog.log("Inject Space → FAILED")
                }

            case .launchpad:
                openLaunchpad()

            case .notificationCenter:
                _ = systemEventsKey(160, control: false)

            case .zoomIn:
                postShortcut(key: 0x18, flags: .maskCommand)

            case .zoomOut:
                postShortcut(key: 0x1B, flags: .maskCommand)

            case .lookup:
                postShortcut(key: 0x02, flags: [.maskControl, .maskCommand])

            case .maximize:
                maximizeFrontWindow()
            }
        }
    }

    /// Fill the focused window to the screen’s visible frame (true maximize).
    /// Falls back to AX Zoom button. Needs Accessibility.
    private static func maximizeFrontWindow() {
        if maximizeFrontWindowAX() {
            AppLog.log("Inject Maximize (AX fill) OK")
            return
        }
        // Fallback: green Zoom button via System Events
        let source = """
        tell application "System Events"
          set frontProc to first application process whose frontmost is true
          tell frontProc
            if (count of windows) is 0 then return
            tell window 1
              try
                click (first button whose subrole is "AXZoomButton")
              end try
            end tell
          end tell
        end tell
        """
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            AppLog.log("Maximize: NSAppleScript create failed")
            return
        }
        _ = script.executeAndReturnError(&error)
        if let error {
            let num = error[NSAppleScript.errorNumber] as? Int ?? -1
            let msg = (error[NSAppleScript.errorMessage] as? String) ?? "\(error)"
            AppLog.log("Maximize err=\(num) \(msg.prefix(140))")
            if num == 1002 {
                noteSpacesFailureOnce()
            }
        } else {
            AppLog.log("Inject Maximize (AX Zoom fallback) OK")
        }
    }

    /// Resize focused window to the screen’s visible frame (AX top-left coords).
    @discardableResult
    private static func maximizeFrontWindowAX() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedAppRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedApplicationAttribute as CFString, &focusedAppRef
        ) == .success,
        let focusedApp = focusedAppRef else {
            AppLog.log("Maximize AX: no focused app")
            return false
        }
        let app = focusedApp as! AXUIElement

        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            app, kAXFocusedWindowAttribute as CFString, &windowRef
        ) == .success,
        let windowRef,
        CFGetTypeID(windowRef) == AXUIElementGetTypeID() else {
            AppLog.log("Maximize AX: no focused window")
            return false
        }
        let window = windowRef as! AXUIElement

        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef)
        _ = AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef)

        var origin = CGPoint.zero
        var currentSize = CGSize.zero
        if let posRef {
            AXValueGetValue(posRef as! AXValue, .cgPoint, &origin)
        }
        if let sizeRef {
            AXValueGetValue(sizeRef as! AXValue, .cgSize, &currentSize)
        }

        // Map AX top-left point → Cocoa, then pick the screen.
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        let cocoaPoint = NSPoint(x: origin.x, y: primaryH - origin.y)
        let screen = NSScreen.screens.first { NSMouseInRect(cocoaPoint, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return false }

        let vis = screen.visibleFrame
        let axOrigin = CGPoint(x: vis.origin.x, y: primaryH - vis.origin.y - vis.size.height)
        let axSize = CGSize(width: vis.size.width, height: vis.size.height)

        let nearlyFilled =
            abs(currentSize.width - axSize.width) < 48
            && abs(currentSize.height - axSize.height) < 48
            && abs(origin.x - axOrigin.x) < 48
            && abs(origin.y - axOrigin.y) < 48
        if nearlyFilled {
            var zoomed: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, "AXZoomed" as CFString, &zoomed) == .success {
                let isZoomed = (zoomed as? Bool) ?? CFBooleanGetValue((zoomed as! CFBoolean))
                let newVal: CFBoolean = isZoomed ? kCFBooleanFalse : kCFBooleanTrue
                if AXUIElementSetAttributeValue(window, "AXZoomed" as CFString, newVal) == .success {
                    return true
                }
            }
        }

        var o = axOrigin
        var s = axSize
        guard let posVal = AXValueCreate(.cgPoint, &o),
              let sizeVal = AXValueCreate(.cgSize, &s) else { return false }
        let pOK = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posVal) == .success
        let sOK = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeVal) == .success
        return pOK && sOK
    }

    /// Launchpad.app was removed on some macOS 27 installs — try paths, Dock, then App Exposé.
    private static func openLaunchpad() {
        let candidates = [
            "/System/Applications/Launchpad.app",
            "/Applications/Launchpad.app",
            "/System/Library/CoreServices/LaunchPad.app"
        ]
        for path in candidates {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                AppLog.log("Inject Launchpad via \(path)")
                return
            }
        }
        // Dock UI element (name localized — try Spanish + English)
        let dockScript = """
        tell application "System Events"
          tell process "Dock"
            set frontmost to true
            try
              click UI element "Launchpad" of list 1
              return "en"
            end try
            try
              click UI element "Launchpad" of list 1 of UI element 1
              return "en2"
            end try
          end tell
        end tell
        return "miss"
        """
        var error: NSDictionary?
        if let script = NSAppleScript(source: dockScript) {
            let result = script.executeAndReturnError(&error)
            if error == nil, let s = result.stringValue, s != "miss" {
                AppLog.log("Inject Launchpad via Dock (\(s))")
                return
            }
        }
        // Fallback: App Exposé (Control+Down) — useful 4-finger-down stand-in
        if systemEventsKey(125, control: true) {
            AppLog.log("Inject Launchpad fallback → App Exposé (Launchpad.app ausente)")
        } else {
            postShortcut(key: keyDown, flags: .maskControl)
            AppLog.log("Inject Launchpad fallback → App Exposé CGEvent")
        }
    }

    /// Quartz global cursor position (top-left origin). Prefer live CGEvent location
    /// over converting NSEvent.mouseLocation — Y-flip mistakes send clicks off-target.
    private static func cgMouseLocation() -> CGPoint {
        if let quartz = CGEvent(source: nil)?.location {
            return quartz
        }
        let loc = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(loc, $0.frame, false) })
                ?? NSScreen.main else {
            return CGPoint(x: loc.x, y: loc.y)
        }
        return CGPoint(x: loc.x, y: screen.frame.maxY - loc.y)
    }
}
