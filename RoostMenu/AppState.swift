import Foundation
import AppKit
import Combine

struct PendingSetpoint: Equatable { var heat: Double?; var cool: Double? }
enum SetpointSide { case heat, cool }

@MainActor
final class AppState: ObservableObject {
    let auth = AuthManager()
    private(set) lazy var client = SDMClient(auth: auth)
    let demo = CommandLine.arguments.contains("--demo")

    @Published var devices: [SDMDevice] = []
    @Published var lastUpdated: Date?
    @Published var errorMessage: String?
    @Published var editingPins = false
    @Published var pending: [String: PendingSetpoint] = [:]
    /// Live streams by device id. Any number can run at once.
    @Published var streams: [String: StreamSession] = [:]
    private(set) var videoWindows: [String: StreamWindowController] = [:]
    /// When on, clicking a camera opens it straight into its own window.
    @Published var openInWindows: Bool = UserDefaults.standard.bool(forKey: "openInWindows") {
        didSet { UserDefaults.standard.set(openInWindows, forKey: "openInWindows") }
    }
    /// Manual device order (device ids). Devices not listed fall in after, in default order.
    @Published private(set) var order: [String] = UserDefaults.standard.stringArray(forKey: "deviceOrder") ?? []
    /// nil = the user never chose, so everything is shown.
    @Published private(set) var pinnedIDs: Set<String>?

    private let pollBase: TimeInterval = 45          // within the 30–60 s the brief asks for
    private var interval: TimeInterval = 45
    private var pollTask: Task<Void, Never>?
    private var lastFetch = Date.distantPast
    private var sendTasks: [String: Task<Void, Never>] = [:]
    private var bag = Set<AnyCancellable>()

    init() {
        if let saved = UserDefaults.standard.array(forKey: "pinnedIDs") as? [String] { pinnedIDs = Set(saved) }
        auth.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
        auth.$isSignedIn.removeDuplicates().dropFirst().sink { [weak self] signedIn in
            if signedIn { self?.interval = self?.pollBase ?? 45; Task { await self?.refresh(force: true) } }
            else { self?.devices = []; self?.stopAllStreams() }
        }.store(in: &bag)

        // Popover opened -> refresh (throttled). Popover lost focus -> stop any live stream.
        NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification).sink { [weak self] _ in
            Task { await self?.refresh(force: false) }
        }.store(in: &bag)
        NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification).sink { [weak self] note in
            // Ignore the Settings window; only the popover going away should end a stream.
            if let w = note.object as? NSWindow, w.title == "Roost Menu Settings" { return }
            // Streams in their own windows live until that window is closed; only the ones
            // shown inside the popover end when it goes away.
            self?.stopInlineStreams()
        }.store(in: &bag)

        startPolling()
    }

    // MARK: Polling

    private func startPolling() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh(force: true)
                try? await Task.sleep(for: .seconds(self.interval))
            }
        }
    }

    func refresh(force: Bool) async {
        if demo { if devices.isEmpty { devices = DemoData.devices; lastUpdated = Date() }; return }
        guard auth.isConfigured, auth.isSignedIn else { return }
        if !force && Date().timeIntervalSince(lastFetch) < 15 { return }
        lastFetch = Date()
        do {
            let list = try await client.listDevices()
            // Don't clobber a setpoint the user is mid-edit on.
            devices = list
            lastUpdated = Date()
            errorMessage = nil
            interval = pollBase
        } catch let e as SDMError where e.isRateLimit || e.isServerSide {
            interval = min(interval * 2, 300)
            errorMessage = e.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
            if case AuthError.reauthRequired = error { interval = pollBase }
        }
    }

    // MARK: Pins

    var supportedDevices: [SDMDevice] { devices.filter { $0.kind != .other } }

    /// All supported devices in the user's manual order (new devices go last, thermostats first, then by name).
    var orderedDevices: [SDMDevice] {
        let base = supportedDevices.sorted { a, b in
            if a.kind != b.kind { return a.kind == .thermostat }
            return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
        }
        let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        // Stable: ranked devices by saved position, then unranked devices in their default order.
        return base.enumerated().sorted { a, b in
            switch (rank[a.element.id], rank[b.element.id]) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return a.offset < b.offset
            }
        }.map(\.element)
    }

    var visibleDevices: [SDMDevice] {
        let all = orderedDevices
        guard let pins = pinnedIDs else { return all }
        return all.filter { pins.contains($0.id) }
    }

    func move(_ d: SDMDevice, up: Bool) {
        var ids = orderedDevices.map(\.id)
        guard let i = ids.firstIndex(of: d.id) else { return }
        let j = up ? i - 1 : i + 1
        guard ids.indices.contains(j) else { return }
        ids.swapAt(i, j)
        order = ids
        UserDefaults.standard.set(ids, forKey: "deviceOrder")
    }

    func isPinned(_ d: SDMDevice) -> Bool { pinnedIDs?.contains(d.id) ?? true }

    func togglePin(_ d: SDMDevice) {
        var set = pinnedIDs ?? Set(supportedDevices.map(\.id))
        if set.contains(d.id) { set.remove(d.id) } else { set.insert(d.id) }
        pinnedIDs = set
        UserDefaults.standard.set(Array(set), forKey: "pinnedIDs")
        if !set.contains(d.id) { stopStream(d.id) }
    }

    /// The thermostat that drives the menu bar title.
    var primaryThermostat: SDMDevice? { visibleDevices.first { $0.kind == .thermostat } }

    // MARK: Thermostat

    func setpoint(_ d: SDMDevice, _ side: SetpointSide) -> Double? {
        let p = pending[d.id]
        switch side {
        case .heat: return p?.heat ?? d.heatSetpointC
        case .cool: return p?.cool ?? d.coolSetpointC
        }
    }

    func nudge(_ d: SDMDevice, side: SetpointSide, up: Bool) {
        guard let current = setpoint(d, side) else { return }
        var next = Temp.step(current, up: up, fahrenheit: d.usesFahrenheit)
        next = min(max(next, 9), 32)
        var p = pending[d.id] ?? PendingSetpoint(heat: d.heatSetpointC, cool: d.coolSetpointC)
        let gap = 1.5
        switch side {
        case .heat:
            p.heat = next
            if d.thermostatMode == "HEATCOOL", let c = p.cool, c < next + gap { p.cool = min(32, next + gap) }
        case .cool:
            p.cool = next
            if d.thermostatMode == "HEATCOOL", let h = p.heat, h > next - gap { p.heat = max(9, next - gap) }
        }
        pending[d.id] = p
        // Debounce so repeated +/- taps become one API call (kinder to rate limits).
        sendTasks[d.id]?.cancel()
        sendTasks[d.id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            await self?.commitSetpoint(deviceID: d.id)
        }
    }

    private func commitSetpoint(deviceID: String) async {
        guard let d = devices.first(where: { $0.id == deviceID }), let p = pending[deviceID] else { return }
        defer { pending[deviceID] = nil }
        if demo { return }
        do {
            switch d.thermostatMode {
            case "HEAT":
                if let h = p.heat { try await client.execute(d, command: "sdm.devices.commands.ThermostatTemperatureSetpoint.SetHeat", params: ["heatCelsius": .number(h)]) }
            case "COOL":
                if let c = p.cool { try await client.execute(d, command: "sdm.devices.commands.ThermostatTemperatureSetpoint.SetCool", params: ["coolCelsius": .number(c)]) }
            case "HEATCOOL":
                if let h = p.heat, let c = p.cool { try await client.execute(d, command: "sdm.devices.commands.ThermostatTemperatureSetpoint.SetRange", params: ["heatCelsius": .number(h), "coolCelsius": .number(c)]) }
            default: return
            }
            errorMessage = nil
            try? await Task.sleep(for: .seconds(2))
            await refresh(force: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setMode(_ d: SDMDevice, mode: String) async {
        if demo { patch(d) { $0.traits["sdm.devices.traits.ThermostatMode"] = ["mode": .string(mode), "availableModes": $0.trait("ThermostatMode")?["availableModes"] ?? .null] }; return }
        do {
            try await client.execute(d, command: "sdm.devices.commands.ThermostatMode.SetMode", params: ["mode": .string(mode)])
            errorMessage = nil
            try? await Task.sleep(for: .seconds(2))
            await refresh(force: true)
        } catch { errorMessage = error.localizedDescription }
    }

    func setEco(_ d: SDMDevice, on: Bool) async {
        if demo { return }
        do {
            try await client.execute(d, command: "sdm.devices.commands.ThermostatEco.SetMode", params: ["mode": .string(on ? "MANUAL_ECO" : "OFF")])
            errorMessage = nil
            try? await Task.sleep(for: .seconds(2))
            await refresh(force: true)
        } catch { errorMessage = error.localizedDescription }
    }

    private func patch(_ d: SDMDevice, _ f: (inout SDMDevice) -> Void) {
        guard let i = devices.firstIndex(where: { $0.id == d.id }) else { return }
        f(&devices[i])
    }

    // MARK: Streams

    func toggleStream(_ d: SDMDevice) {
        if streams[d.id] != nil { stopStream(d.id); return }
        if demo {
            errorMessage = "Demo mode: live streams are disabled."
            return
        }
        let s = StreamSession(device: d, client: client)
        streams[d.id] = s
        s.start()
        if openInWindows { detachStream(d.id) }
    }

    func stopStream(_ id: String) {
        let w = videoWindows[id]
        videoWindows[id] = nil
        w?.close()
        streams[id]?.stop()
        streams[id] = nil
    }

    /// Streams shown inside the popover end when the popover goes away.
    func stopInlineStreams() {
        for (id, s) in streams where !s.detached { stopStream(id) }
    }

    func stopAllStreams() {
        for id in Array(streams.keys) { stopStream(id) }
    }

    /// Move a live video out of the popover into its own resizable window.
    func detachStream(_ id: String) {
        guard let s = streams[id] else { return }
        if let w = videoWindows[id] { w.show(); return }
        s.detached = true
        let w = StreamWindowController(session: s) { [weak self] in
            self?.videoWindows[id] = nil     // user closed it: end that stream too
            self?.stopStream(id)
        }
        videoWindows[id] = w
        w.show()
    }

    func showVideoWindow(_ id: String) { videoWindows[id]?.show() }
}
