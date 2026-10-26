import Foundation
import CoreGraphics

enum GestureAction: String, CaseIterable, Identifiable {
    case none
    case missionControl
    case appExpose
    case dismiss
    case desktop
    case spaceLeft
    case spaceRight
    case launchpad
    case notificationCenter
    case zoomIn
    case zoomOut
    case lookup
    case maximize

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return L10n.t("Ninguno", "None")
        case .missionControl: return "Mission Control (toggle)"
        case .appExpose: return "App Exposé"
        case .dismiss: return L10n.t("Cerrar overlay (Esc)", "Dismiss overlay (Esc)")
        case .desktop: return L10n.t("Escritorio", "Desktop")
        case .spaceLeft: return "Space ←"
        case .spaceRight: return "Space →"
        case .launchpad: return "Launchpad"
        case .notificationCenter: return L10n.t("Centro de notificaciones", "Notification Center")
        case .zoomIn: return "Zoom +"
        case .zoomOut: return "Zoom −"
        case .lookup: return "Look Up"
        case .maximize: return L10n.t("Maximizar ventana", "Maximize window")
        }
    }
}

extension Notification.Name {
    static let hidexConfigDidChange = Notification.Name("HidexConfigDidChange")
}

struct GestureConfig: Equatable {
    var pointerSpeed: Double = 1.2
    var scrollSpeed: Double = 0.35
    var invertScroll: Bool = true

    /// 1-finger tap → left click (injected; dual HID does not provide soft taps).
    var tapToClick: Bool = true
    /// 1-finger double-tap → maximize/zoom front window (AX Zoom button).
    var doubleTapMaximize: Bool = true
    var doubleTapInterval: TimeInterval = 0.38
    var doubleTapSlop: CGFloat = 90

    /// Soft taps on Unifying pads often land ~200–380 ms.
    var tapMaxDuration: TimeInterval = 0.40
    var tapMaxMove: CGFloat = 64

    /// 2-finger tap → right click. Kept *much* tighter than 1F / scroll so a
    /// short scroll flick does not become a right-click (dual HID scrolls natively).
    var twoFingerTap: Bool = true
    var twoFingerTapMaxDuration: TimeInterval = 0.22
    var twoFingerTapMaxMove: CGFloat = 16
    /// Mid-gesture: centroid travel OR path length past this → scroll, no right-click.
    var twoFingerScrollIntentMove: CGFloat = 18
    /// After a 2F scroll, ignore right-click ghosts from lift/re-contact (seconds).
    var twoFingerTapCooldownAfterScroll: TimeInterval = 0.55

    var swipeThreshold: CGFloat = 90
    var pinchThreshold: CGFloat = 80

    var threeFingerUp: GestureAction = .missionControl
    var threeFingerDown: GestureAction = .dismiss
    var threeFingerLeft: GestureAction = .spaceLeft
    var threeFingerRight: GestureAction = .spaceRight
    var fourFingerUp: GestureAction = .desktop
    var fourFingerDown: GestureAction = .launchpad

    static let defaultsKey = "HidexGestureConfig"

    static func load() -> GestureConfig {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(CodableConfig.self, from: data)
        else { return GestureConfig() }
        var c = decoded.toConfig()
        if !UserDefaults.standard.bool(forKey: "migratedDismissDown"),
           c.threeFingerDown == .appExpose {
            c.threeFingerDown = .dismiss
            UserDefaults.standard.set(true, forKey: "migratedDismissDown")
            c.save()
        }
        // One-shot: relax factory tap window if the user never customized it.
        if !UserDefaults.standard.bool(forKey: "migratedTapWindow401"),
           abs(c.tapMaxDuration - 0.28) < 0.001,
           abs(c.tapMaxMove - 48) < 0.5 {
            c.tapMaxDuration = 0.40
            c.tapMaxMove = 64
            UserDefaults.standard.set(true, forKey: "migratedTapWindow401")
            c.save()
            AppLog.log("Migrated tap window → 400ms / move 64")
        }
        if !UserDefaults.standard.bool(forKey: "migratedTwoFingerTapSep403") {
            c.twoFingerTapMaxDuration = 0.22
            c.twoFingerTapMaxMove = 16
            c.twoFingerScrollIntentMove = 18
            c.doubleTapMaximize = true
            UserDefaults.standard.set(true, forKey: "migratedTwoFingerTapSep403")
            c.save()
            AppLog.log("Migrated 2F tap vs scroll + double-tap maximize defaults")
        }
        // Tighten further: lift ghosts after scroll were still firing right-click.
        if !UserDefaults.standard.bool(forKey: "migratedTwoFingerTapSep404") {
            c.twoFingerTapMaxDuration = 0.22
            c.twoFingerTapMaxMove = 16
            c.twoFingerScrollIntentMove = 18
            c.twoFingerTapCooldownAfterScroll = 0.55
            UserDefaults.standard.set(true, forKey: "migratedTwoFingerTapSep404")
            c.save()
            AppLog.log("Migrated 2F tap: tighter window + post-scroll cooldown")
        }
        return c
    }

    func save() {
        let c = CodableConfig(from: self)
        if let data = try? JSONEncoder().encode(c) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
        NotificationCenter.default.post(name: .hidexConfigDidChange, object: nil)
    }

    static func resetToDefaults() -> GestureConfig {
        let c = GestureConfig()
        c.save()
        return c
    }
}

private struct CodableConfig: Codable {
    var pointerSpeed: Double
    var scrollSpeed: Double
    var invertScroll: Bool
    var tapToClick: Bool
    var twoFingerTap: Bool?
    var tapMaxDuration: Double?
    var tapMaxMove: Double?
    var doubleTapMaximize: Bool?
    var doubleTapInterval: Double?
    var doubleTapSlop: Double?
    var twoFingerTapMaxDuration: Double?
    var twoFingerTapMaxMove: Double?
    var twoFingerScrollIntentMove: Double?
    var twoFingerTapCooldownAfterScroll: Double?
    var swipeThreshold: Double?
    var pinchThreshold: Double?
    var threeFingerUp: String
    var threeFingerDown: String
    var threeFingerLeft: String
    var threeFingerRight: String
    var fourFingerUp: String
    var fourFingerDown: String

    init(from c: GestureConfig) {
        pointerSpeed = c.pointerSpeed
        scrollSpeed = c.scrollSpeed
        invertScroll = c.invertScroll
        tapToClick = c.tapToClick
        twoFingerTap = c.twoFingerTap
        tapMaxDuration = c.tapMaxDuration
        tapMaxMove = Double(c.tapMaxMove)
        doubleTapMaximize = c.doubleTapMaximize
        doubleTapInterval = c.doubleTapInterval
        doubleTapSlop = Double(c.doubleTapSlop)
        twoFingerTapMaxDuration = c.twoFingerTapMaxDuration
        twoFingerTapMaxMove = Double(c.twoFingerTapMaxMove)
        twoFingerScrollIntentMove = Double(c.twoFingerScrollIntentMove)
        twoFingerTapCooldownAfterScroll = c.twoFingerTapCooldownAfterScroll
        swipeThreshold = Double(c.swipeThreshold)
        pinchThreshold = Double(c.pinchThreshold)
        threeFingerUp = c.threeFingerUp.rawValue
        threeFingerDown = c.threeFingerDown.rawValue
        threeFingerLeft = c.threeFingerLeft.rawValue
        threeFingerRight = c.threeFingerRight.rawValue
        fourFingerUp = c.fourFingerUp.rawValue
        fourFingerDown = c.fourFingerDown.rawValue
    }

    func toConfig() -> GestureConfig {
        var c = GestureConfig()
        c.pointerSpeed = pointerSpeed
        c.scrollSpeed = scrollSpeed
        c.invertScroll = invertScroll
        c.tapToClick = tapToClick
        c.twoFingerTap = twoFingerTap ?? true
        if let d = tapMaxDuration { c.tapMaxDuration = d }
        if let m = tapMaxMove { c.tapMaxMove = CGFloat(m) }
        if let v = doubleTapMaximize { c.doubleTapMaximize = v }
        if let v = doubleTapInterval { c.doubleTapInterval = v }
        if let v = doubleTapSlop { c.doubleTapSlop = CGFloat(v) }
        if let v = twoFingerTapMaxDuration { c.twoFingerTapMaxDuration = v }
        if let v = twoFingerTapMaxMove { c.twoFingerTapMaxMove = CGFloat(v) }
        if let v = twoFingerScrollIntentMove { c.twoFingerScrollIntentMove = CGFloat(v) }
        if let v = twoFingerTapCooldownAfterScroll { c.twoFingerTapCooldownAfterScroll = v }
        if let s = swipeThreshold { c.swipeThreshold = CGFloat(s) }
        if let p = pinchThreshold { c.pinchThreshold = CGFloat(p) }
        c.threeFingerUp = GestureAction(rawValue: threeFingerUp) ?? .missionControl
        c.threeFingerDown = GestureAction(rawValue: threeFingerDown) ?? .dismiss
        c.threeFingerLeft = GestureAction(rawValue: threeFingerLeft) ?? .spaceLeft
        c.threeFingerRight = GestureAction(rawValue: threeFingerRight) ?? .spaceRight
        c.fourFingerUp = GestureAction(rawValue: fourFingerUp) ?? .desktop
        c.fourFingerDown = GestureAction(rawValue: fourFingerDown) ?? .launchpad
        return c
    }
}
