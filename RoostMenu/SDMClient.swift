import Foundation

enum SDMError: LocalizedError {
    case http(status: Int, message: String)

    var isRateLimit: Bool { if case .http(let s, _) = self { return s == 429 }; return false }
    var isServerSide: Bool { if case .http(let s, _) = self { return s >= 500 }; return false }

    var errorDescription: String? {
        switch self {
        case .http(let status, let message):
            switch status {
            case 429: return "Google rate limit hit; slowing down. (\(message))"
            case 403: return "Access denied (403). Check the Project ID, that the SDM API is enabled, and that you granted access to your devices. \(message)"
            case 404: return "Not found (404). Check the Device Access Project ID. \(message)"
            default: return "Google returned \(status): \(message)"
            }
        }
    }
}

struct WebRtcOffer { let answerSdp: String; let mediaSessionId: String; let expiresAt: Date }

@MainActor
final class SDMClient {
    let auth: AuthManager
    private let base = "https://smartdevicemanagement.googleapis.com/v1"

    init(auth: AuthManager) { self.auth = auth }

    func listDevices() async throws -> [SDMDevice] {
        let data = try await send("GET", path: "/enterprises/\(auth.projectID.trimmed)/devices", body: nil)
        return try SDMDevice.decodeList(data)
    }

    @discardableResult
    func execute(_ device: SDMDevice, command: String, params: [String: JSON] = [:]) async throws -> JSON {
        try await execute(deviceName: device.id, command: command, params: params)
    }

    @discardableResult
    func execute(deviceName: String, command: String, params: [String: JSON] = [:]) async throws -> JSON {
        let body = try JSONEncoder().encode(JSON.object(["command": .string(command), "params": .object(params)]))
        let data = try await send("POST", path: "/\(deviceName):executeCommand", body: body)
        return (try? JSONDecoder().decode(JSON.self, from: data)) ?? .null
    }

    // MARK: WebRTC

    func generateWebRtc(deviceName: String, offerSdp: String) async throws -> WebRtcOffer {
        let r = try await execute(deviceName: deviceName,
                                  command: "sdm.devices.commands.CameraLiveStream.GenerateWebRtcStream",
                                  params: ["offerSdp": .string(offerSdp)])
        guard let results = r["results"],
              let answer = results["answerSdp"]?.string,
              let id = results["mediaSessionId"]?.string else {
            throw SDMError.http(status: 0, message: "Unexpected stream response")
        }
        return WebRtcOffer(answerSdp: answer, mediaSessionId: id,
                           expiresAt: Self.parseDate(results["expiresAt"]?.string) ?? Date().addingTimeInterval(290))
    }

    func extendWebRtc(deviceName: String, mediaSessionId: String) async throws -> Date {
        let r = try await execute(deviceName: deviceName,
                                  command: "sdm.devices.commands.CameraLiveStream.ExtendWebRtcStream",
                                  params: ["mediaSessionId": .string(mediaSessionId)])
        return Self.parseDate(r["results"]?["expiresAt"]?.string) ?? Date()
    }

    func stopWebRtc(deviceName: String, mediaSessionId: String) async {
        _ = try? await execute(deviceName: deviceName,
                               command: "sdm.devices.commands.CameraLiveStream.StopWebRtcStream",
                               params: ["mediaSessionId": .string(mediaSessionId)])
    }

    static func parseDate(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    // MARK: HTTP

    private func send(_ method: String, path: String, body: Data?, retried: Bool = false) async throws -> Data {
        guard auth.isConfigured else { throw AuthError.notConfigured }
        let token = try await auth.accessToken()
        var req = URLRequest(url: URL(string: base + path)!)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        req.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 && !retried {
            auth.invalidateAccessToken()
            return try await send(method, path: path, body: body, retried: true)
        }
        guard (200..<300).contains(status) else {
            let msg = (try? JSONDecoder().decode(JSON.self, from: data))?["error"]?["message"]?.string
                ?? String(data: data, encoding: .utf8) ?? ""
            throw SDMError.http(status: status, message: msg)
        }
        return data
    }
}
