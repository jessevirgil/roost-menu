import Foundation

enum DeviceKind { case thermostat, camera, other }

struct SDMDevice: Identifiable, Equatable {
    /// Full resource name: enterprises/<project>/devices/<id>
    let id: String
    let type: String
    var traits: [String: JSON]
    var roomName: String?

    private static let prefix = "sdm.devices.traits."
    func trait(_ short: String) -> JSON? { traits[Self.prefix + short] }

    var kind: DeviceKind {
        if type.hasSuffix(".THERMOSTAT") { return .thermostat }
        if trait("CameraLiveStream") != nil { return .camera }
        return .other
    }

    var displayName: String {
        if let n = trait("Info")?["customName"]?.string, !n.isEmpty { return n }
        if let r = roomName, !r.isEmpty { return r }
        switch type {
        case let t where t.hasSuffix(".DOORBELL"): return "Doorbell"
        case let t where t.hasSuffix(".CAMERA"): return "Camera"
        case let t where t.hasSuffix(".THERMOSTAT"): return "Thermostat"
        default: return "Device"
        }
    }

    var isDoorbell: Bool { type.hasSuffix(".DOORBELL") }
    var isOnline: Bool { trait("Connectivity")?["status"]?.string != "OFFLINE" }
    var supportsWebRTC: Bool {
        trait("CameraLiveStream")?["supportedProtocols"]?.strings.contains("WEB_RTC") ?? false
    }

    // MARK: Thermostat accessors (all Celsius, as the API reports)
    var usesFahrenheit: Bool { trait("Settings")?["temperatureScale"]?.string == "FAHRENHEIT" }
    var ambientC: Double? { trait("Temperature")?["ambientTemperatureCelsius"]?.double }
    var humidity: Double? { trait("Humidity")?["ambientHumidityPercent"]?.double }
    var thermostatMode: String { trait("ThermostatMode")?["mode"]?.string ?? "OFF" }
    var availableModes: [String] { trait("ThermostatMode")?["availableModes"]?.strings ?? ["HEAT", "COOL", "HEATCOOL", "OFF"] }
    var hvacStatus: String { trait("ThermostatHvac")?["status"]?.string ?? "OFF" }
    var ecoActive: Bool { trait("ThermostatEco")?["mode"]?.string == "MANUAL_ECO" }
    var ecoAvailable: Bool { trait("ThermostatEco")?["availableModes"]?.strings.contains("MANUAL_ECO") ?? false }
    var heatSetpointC: Double? { trait("ThermostatTemperatureSetpoint")?["heatCelsius"]?.double }
    var coolSetpointC: Double? { trait("ThermostatTemperatureSetpoint")?["coolCelsius"]?.double }
}

private struct DeviceListDTO: Decodable { let devices: [DeviceDTO]? }
private struct DeviceDTO: Decodable {
    struct Parent: Decodable { let parent: String?; let displayName: String? }
    let name: String
    let type: String
    let traits: [String: JSON]?
    let parentRelations: [Parent]?
}

extension SDMDevice {
    static func decodeList(_ data: Data) throws -> [SDMDevice] {
        let dto = try JSONDecoder().decode(DeviceListDTO.self, from: data)
        return (dto.devices ?? []).map {
            SDMDevice(id: $0.name, type: $0.type, traits: $0.traits ?? [:],
                      roomName: $0.parentRelations?.first?.displayName)
        }
    }
}

// MARK: Temperature helpers

enum Temp {
    static func toF(_ c: Double) -> Double { c * 9 / 5 + 32 }
    static func toC(_ f: Double) -> Double { (f - 32) * 5 / 9 }

    static func text(_ c: Double?, fahrenheit: Bool) -> String {
        guard let c else { return "–" }
        if fahrenheit { return "\(Int(toF(c).rounded()))°" }
        let r = (c * 2).rounded() / 2
        return r == r.rounded() ? "\(Int(r))°" : String(format: "%.1f°", r)
    }

    /// Move a Celsius setpoint by one UI step (1°F or 0.5°C).
    static func step(_ c: Double, up: Bool, fahrenheit: Bool) -> Double {
        let sign: Double = up ? 1 : -1
        if fahrenheit { return toC(toF(c).rounded() + sign) }
        return ((c * 2).rounded() / 2) + 0.5 * sign
    }
}
