import SwiftUI
import AppKit

final class PreferencesModel: ObservableObject {
    @Published var config: GestureConfig {
        didSet { config.save() }
    }

    init() {
        config = GestureConfig.load()
    }

    func reset() {
        config = GestureConfig.resetToDefaults()
    }
}

struct PreferencesView: View {
    @ObservedObject var model: PreferencesModel

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "slider.horizontal.3") }
            gesturesTab
                .tabItem { Label("Gestos", systemImage: "hand.draw") }
        }
        .padding(20)
        .frame(width: 520, height: 620)
    }

    private var generalTab: some View {
        Form {
            Section("Puntero y scroll") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Velocidad del puntero")
                        Spacer()
                        Text(String(format: "%.1f", model.config.pointerSpeed))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $model.config.pointerSpeed, in: 0.4...3.5, step: 0.1)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Velocidad de scroll")
                        Spacer()
                        Text(String(format: "%.2f", model.config.scrollSpeed))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $model.config.scrollSpeed, in: 0.05...1.2, step: 0.05)
                }

                Toggle("Scroll natural", isOn: $model.config.invertScroll)
            }

            Section("Clics por toque (1 dedo)") {
                Toggle("Toque → clic izquierdo", isOn: $model.config.tapToClick)
                Toggle("Doble toque → maximizar ventana", isOn: $model.config.doubleTapMaximize)
                Text("El clic físico del pad sigue aparte. El doble toque usa el botón Zoom (verde) de la ventana frontal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Duración máx. toque 1 dedo")
                        Spacer()
                        Text("\(Int(model.config.tapMaxDuration * 1000)) ms")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $model.config.tapMaxDuration, in: 0.12...0.50, step: 0.02)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Movimiento máx. toque 1 dedo")
                        Spacer()
                        Text("\(Int(model.config.tapMaxMove))")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: Binding(
                        get: { Double(model.config.tapMaxMove) },
                        set: { model.config.tapMaxMove = CGFloat($0) }
                    ), in: 20...120, step: 2)
                }
            }

            Section("Toque 2 dedos vs scroll") {
                Toggle("Toque 2 dedos → clic derecho", isOn: $model.config.twoFingerTap)
                Text("El scroll con 2 dedos es nativo. El clic derecho solo si el contacto es corto y casi sin movimiento — umbrales más estrictos que el toque de 1 dedo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Duración máx. toque 2 dedos")
                        Spacer()
                        Text("\(Int(model.config.twoFingerTapMaxDuration * 1000)) ms")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $model.config.twoFingerTapMaxDuration, in: 0.10...0.35, step: 0.02)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Movimiento máx. (clic derecho)")
                        Spacer()
                        Text("\(Int(model.config.twoFingerTapMaxMove))")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: Binding(
                        get: { Double(model.config.twoFingerTapMaxMove) },
                        set: { model.config.twoFingerTapMaxMove = CGFloat($0) }
                    ), in: 8...40, step: 1)
                    Text("Si al soltar el scroll sale clic derecho, bájalo. Si el clic derecho casi no entra, súbelo un poco.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Bloqueo scroll (anti clic derecho)")
                        Spacer()
                        Text("\(Int(model.config.twoFingerScrollIntentMove))")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: Binding(
                        get: { Double(model.config.twoFingerScrollIntentMove) },
                        set: { model.config.twoFingerScrollIntentMove = CGFloat($0) }
                    ), in: 10...60, step: 1)
                    Text("Al superar este movimiento, el gesto es scroll. Tras soltar hay ~0,55 s de bloqueo para fantasmas de levantada.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Gestos") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Umbral de swipe (3/4 dedos)")
                        Spacer()
                        Text("\(Int(model.config.swipeThreshold))")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: Binding(
                        get: { Double(model.config.swipeThreshold) },
                        set: { model.config.swipeThreshold = CGFloat($0) }
                    ), in: 40...250, step: 5)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Umbral de pinch (zoom)")
                        Spacer()
                        Text("\(Int(model.config.pinchThreshold))")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: Binding(
                        get: { Double(model.config.pinchThreshold) },
                        set: { model.config.pinchThreshold = CGFloat($0) }
                    ), in: 30...200, step: 5)
                }
            }

            Section {
                Button("Restablecer valores por defecto") {
                    model.reset()
                }
            }
        }
        .formStyle(.grouped)
    }

    private var gesturesTab: some View {
        Form {
            Section("Tres dedos") {
                actionPicker("Arriba ↑", selection: $model.config.threeFingerUp)
                actionPicker("Abajo ↓", selection: $model.config.threeFingerDown)
                actionPicker("Izquierda ←", selection: $model.config.threeFingerLeft)
                actionPicker("Derecha →", selection: $model.config.threeFingerRight)
            }
            Section("Cuatro dedos") {
                actionPicker("Arriba ↑", selection: $model.config.fourFingerUp)
                actionPicker("Abajo ↓", selection: $model.config.fourFingerDown)
            }
            Section {
                Text(L10n.t(
                    "El touchpad compatible reporta hasta 2 posiciones XY por frame; el número de dedos viene en finger_count. Desliza con 3 o 4 dedos para disparar el gesto. (Hardware documentado: Logitech T650.)",
                    "The compatible touchpad reports up to 2 XY positions per frame; finger count comes from finger_count. Swipe with 3 or 4 fingers to fire the gesture. (Documented hardware: Logitech T650.)"
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }

    private func actionPicker(_ title: String, selection: Binding<GestureAction>) -> some View {
        Picker(title, selection: selection) {
            ForEach(GestureAction.allCases) { action in
                Text(action.displayName).tag(action)
            }
        }
    }
}

final class PreferencesWindowController: NSObject {
    private var window: NSWindow?
    private let model = PreferencesModel()

    func show() {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let root = PreferencesView(model: model)
        let hosting = NSHostingController(rootView: root)
        let win = NSWindow(contentViewController: hosting)
        win.title = L10n.preferencesWindowTitle
        win.styleMask = [.titled, .closable, .miniaturizable]
        win.setContentSize(NSSize(width: 520, height: 620))
        win.center()
        win.isReleasedWhenClosed = false
        win.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window = win

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: win
        )
    }

    @objc private func windowWillClose(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
