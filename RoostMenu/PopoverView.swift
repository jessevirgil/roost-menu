import SwiftUI
import WebKit

struct PopoverView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            if let msg = state.errorMessage {
                Divider()
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            footer
        }
        .frame(width: 360)
    }

    private var header: some View {
        HStack {
            Text("Nest").font(.headline)
            Spacer()
            if state.demo { Text("DEMO").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2).background(.orange.opacity(0.25), in: Capsule()) }
            Button { state.openInWindows.toggle() } label: {
                Image(systemName: state.openInWindows ? "rectangle.on.rectangle.fill" : "rectangle.on.rectangle")
            }
            .buttonStyle(.borderless)
            .help(state.openInWindows ? "Cameras open in their own windows (click to turn off)"
                                      : "Open each camera in its own window, so you can watch several at once")
            Button { Task { await state.refresh(force: true) } } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless).help("Refresh now")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    @ViewBuilder private var content: some View {
        if !state.demo && !(state.auth.isConfigured && state.auth.isSignedIn) {
            VStack(spacing: 10) {
                Image(systemName: "key.horizontal").font(.largeTitle).foregroundStyle(.secondary)
                Text(state.auth.isConfigured ? "Sign in to Google to see your devices." : "Finish setup to connect your Nest devices.")
                    .multilineTextAlignment(.center)
                Button("Open Settings") { openSettings() }.buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity).padding(24)
        } else if state.editingPins {
            pinPicker
        } else if state.visibleDevices.isEmpty {
            Text(state.devices.isEmpty ? "Loading devices…" : "Nothing pinned. Tap “Choose devices” below.")
                .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(24)
        } else {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(state.visibleDevices) { d in
                        switch d.kind {
                        case .thermostat: ThermostatCard(device: d)
                        case .camera: CameraCard(device: d)
                        case .other: EmptyView()
                        }
                    }
                }
                .padding(12)
            }
            .frame(height: Self.contentHeight)
        }
    }

    /// A MenuBarExtra window sizes itself to its content's ideal size, and a ScrollView's is tiny,
    /// so give it an explicit height: tall enough for a thermostat plus an open camera feed, but
    /// never taller than the screen.
    static var contentHeight: CGFloat {
        let screen = NSScreen.main?.visibleFrame.height ?? 800
        return min(max(screen - 160, 420), 720)
    }

    private var pinPicker: some View {
        ScrollView { pinPickerList }.frame(height: Self.contentHeight)
    }

    private var pinPickerList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Choose the devices to show in this menu.")
                .font(.caption).foregroundStyle(.secondary).padding(12)
            let all = state.orderedDevices
            ForEach(Array(all.enumerated()), id: \.element.id) { index, d in
                HStack {
                    Toggle(isOn: Binding(get: { state.isPinned(d) }, set: { _ in state.togglePin(d) })) {
                        HStack {
                            Image(systemName: d.kind == .thermostat ? "thermometer.medium" : (d.isDoorbell ? "bell.fill" : "video.fill"))
                                .frame(width: 20)
                            Text(d.displayName)
                            if !d.isOnline { Text("offline").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    .toggleStyle(.checkbox)
                    Spacer()
                    Button { state.move(d, up: true) } label: { Image(systemName: "chevron.up") }
                        .buttonStyle(.borderless).disabled(index == 0).help("Move up")
                    Button { state.move(d, up: false) } label: { Image(systemName: "chevron.down") }
                        .buttonStyle(.borderless).disabled(index == all.count - 1).help("Move down")
                }
                .padding(.horizontal, 12).padding(.vertical, 5)
            }
            Spacer(minLength: 8)
        }
    }

    private var footer: some View {
        HStack {
            if state.auth.isSignedIn || state.demo {
                Button(state.editingPins ? "Done" : "Choose devices") { state.editingPins.toggle() }
                    .buttonStyle(.borderless)
            }
            if let t = state.lastUpdated {
                Text("Updated \(t.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button { openSettings() } label: { Image(systemName: "gearshape") }.buttonStyle(.borderless).help("Settings")
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }.buttonStyle(.borderless).help("Quit")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private func openSettings() {
        openWindow(id: "settings")
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: Thermostat

struct ThermostatCard: View {
    @EnvironmentObject var state: AppState
    let device: SDMDevice

    private var f: Bool { device.usesFahrenheit }
    private var mode: String { device.thermostatMode }
    private var editable: Bool { !device.ecoActive && ["HEAT", "COOL", "HEATCOOL"].contains(mode) && device.isOnline }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(device.displayName, systemImage: "thermometer.medium").font(.subheadline.bold())
                Spacer()
                if !device.isOnline { Text("Offline").font(.caption).foregroundStyle(.red) }
                else if device.hvacStatus != "OFF" {
                    Text(device.hvacStatus.capitalized)
                        .font(.caption.bold())
                        .foregroundStyle(device.hvacStatus == "HEATING" ? .orange : .cyan)
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(Temp.text(device.ambientC, fahrenheit: f)).font(.system(size: 40, weight: .light))
                VStack(alignment: .leading) {
                    Text("Inside").font(.caption).foregroundStyle(.secondary)
                    if let h = device.humidity { Text("Humidity \(Int(h))%").font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
            }

            Picker("Mode", selection: Binding(get: { mode }, set: { m in Task { await state.setMode(device, mode: m) } })) {
                ForEach(device.availableModes.filter { $0 != "MANUAL_ECO" }, id: \.self) { m in
                    Text(label(for: m)).tag(m)
                }
            }
            .pickerStyle(.segmented).labelsHidden()
            .disabled(!device.isOnline)

            if device.ecoAvailable {
                Toggle("Eco", isOn: Binding(get: { device.ecoActive }, set: { on in Task { await state.setEco(device, on: on) } }))
                    .toggleStyle(.switch).controlSize(.small)
                    .disabled(!device.isOnline)
            }

            if device.ecoActive {
                Text("Eco mode is on. Setpoints can’t be changed while Eco is active.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if mode == "OFF" {
                Text("System is off.").font(.caption).foregroundStyle(.secondary)
            } else {
                if mode == "HEAT" || mode == "HEATCOOL" { setpointRow("Heat to", .heat) }
                if mode == "COOL" || mode == "HEATCOOL" { setpointRow("Cool to", .cool) }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private func label(for m: String) -> String {
        switch m { case "HEAT": "Heat"; case "COOL": "Cool"; case "HEATCOOL": "Auto"; case "OFF": "Off"; default: m.capitalized }
    }

    private func setpointRow(_ title: String, _ side: SetpointSide) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Button { state.nudge(device, side: side, up: false) } label: { Image(systemName: "minus.circle.fill").font(.title2) }
                .buttonStyle(.borderless).disabled(!editable)
            Text(Temp.text(state.setpoint(device, side), fahrenheit: f))
                .font(.title3.monospacedDigit()).frame(minWidth: 52)
            Button { state.nudge(device, side: side, up: true) } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                .buttonStyle(.borderless).disabled(!editable)
        }
    }
}

// MARK: Camera

struct CameraCard: View {
    @EnvironmentObject var state: AppState
    let device: SDMDevice

    private var session: StreamSession? { state.streams[device.id] }
    private var isStreaming: Bool { session != nil }

    var body: some View {
        VStack(spacing: 8) {
            Button { state.toggleStream(device) } label: {
                HStack {
                    Image(systemName: device.isDoorbell ? "bell.fill" : "video.fill").frame(width: 22)
                    Text(device.displayName).font(.subheadline.bold())
                    Circle().fill(device.isOnline ? Color.green : Color.red).frame(width: 7, height: 7)
                    Spacer()
                    if !device.supportsWebRTC {
                        Text("No WebRTC").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Image(systemName: isStreaming ? "stop.circle.fill" : "play.circle.fill").font(.title2)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!device.isOnline || !device.supportsWebRTC)

            if let s = session { StreamPanel(session: s) }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .opacity(device.isOnline ? 1 : 0.6)
    }
}

struct StreamPanel: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var session: StreamSession

    var body: some View {
        if session.detached {
            HStack {
                Image(systemName: "rectangle.on.rectangle")
                Text("Playing in a separate window").font(.caption)
                Spacer()
                Button("Show") { state.showVideoWindow(session.device.id) }.buttonStyle(.borderless).font(.caption)
            }
            .foregroundStyle(.secondary)
        } else {
            ZStack {
                WebViewHost(webView: session.webView)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .background(Color.black, in: RoundedRectangle(cornerRadius: 6))
                StreamStatusOverlay(state: session.state)
            }
            .overlay(alignment: .topTrailing) {
                OverlayButton(symbol: "arrow.up.left.and.arrow.down.right", help: "Open in a larger window") {
                    state.detachStream(session.device.id)
                }
                .padding(6)
            }
            .overlay(alignment: .bottomTrailing) {
                if session.state == .live {
                    OverlayButton(symbol: session.muted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                                  help: session.muted ? "Unmute" : "Mute") {
                        session.setMuted(!session.muted)
                    }
                    .padding(6)
                }
            }
        }
    }
}

struct WebViewHost: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
