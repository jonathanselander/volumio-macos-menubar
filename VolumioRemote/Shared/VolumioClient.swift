import Foundation

/// What the widget and the app show about a player. Built from `/api/v1/getState`.
struct PlayerState: Equatable {
    var status: String = "stop"
    var title: String?
    var artist: String?
    var album: String?
    var service: String?
    var albumArtURL: URL?
    var volume: Int?
    var mute: Bool = false
    var volumeControlDisabled: Bool = false

    var isPlaying: Bool { status == "play" }

    var statusText: String {
        let label: String
        switch status {
        case "play": label = "Playing"
        case "pause": label = "Paused"
        default: label = "Stopped"
        }
        if let service, !service.isEmpty, service != "mpd" {
            return "\(label) · \(service)"
        }
        return label
    }

    static let preview = PlayerState(
        status: "play",
        title: "So What",
        artist: "Miles Davis",
        album: "Kind of Blue",
        service: "tidal",
        volume: 42
    )
}

/// Minimal Volumio REST client shared by the app and the widget.
/// See the repository's CLAUDE.md for the endpoints.
enum VolumioClient {
    static let defaultPort = 3000

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 4
        configuration.timeoutIntervalForResource = 8
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    /// Accepts "192.168.1.40", "volumio.local", "192.168.1.40:3000" or "http://192.168.1.40/".
    static func baseURL(for address: String) -> URL? {
        var text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["http://", "https://"] where text.lowercased().hasPrefix(prefix) {
            text.removeFirst(prefix.count)
        }
        if let slash = text.firstIndex(of: "/") {
            text = String(text[..<slash])
        }
        guard !text.isEmpty, !text.contains(" ") else { return nil }

        var components = URLComponents()
        components.scheme = "http"
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        if parts.count == 2, let port = Int(parts[1]) {
            components.host = String(parts[0])
            components.port = port
        } else if parts.count == 1 {
            components.host = text
            components.port = defaultPort
        } else {
            return nil
        }
        return components.url
    }

    static func state(at address: String) async throws -> PlayerState {
        let base = try url(address)
        let body = try await data(from: base.appendingPathComponent("api/v1/getState"))
        guard let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }

        var state = PlayerState()
        state.status = string(json["status"]) ?? "stop"
        state.title = string(json["title"])
        state.artist = string(json["artist"])
        state.album = string(json["album"])
        state.service = string(json["service"])
        state.volume = double(json["volume"]).map { max(0, min(100, Int($0.rounded()))) }
        state.mute = bool(json["mute"]) ?? false
        state.volumeControlDisabled = bool(json["disableVolumeControl"]) ?? false
        if let art = string(json["albumart"]) {
            if art.lowercased().hasPrefix("http") {
                state.albumArtURL = URL(string: art)
            } else {
                state.albumArtURL = URL(string: art.hasPrefix("/") ? art : "/" + art, relativeTo: base)?.absoluteURL
            }
        }
        return state
    }

    /// Sends `/api/v1/commands/?cmd=...`. `volume` is 0-100 or plus/minus/mute/unmute.
    static func command(_ cmd: String, volume: String? = nil, at address: String) async throws {
        let base = try url(address)
        var components = URLComponents(url: base.appendingPathComponent("api/v1/commands/"), resolvingAgainstBaseURL: false)
        var query = [URLQueryItem(name: "cmd", value: cmd)]
        if let volume {
            query.append(URLQueryItem(name: "volume", value: volume))
        }
        components?.queryItems = query
        guard let commandURL = components?.url else { throw URLError(.badURL) }
        _ = try await data(from: commandURL)
    }

    static func imageData(from url: URL) async -> Data? {
        try? await data(from: url)
    }

    // MARK: - Plumbing

    private static func url(_ address: String) throws -> URL {
        guard let base = baseURL(for: address) else { throw URLError(.badURL) }
        return base
    }

    private static func data(from url: URL) async throws -> Data {
        let (body, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return body
    }

    // Volumio sometimes sends numbers as strings, or null.
    private static func string(_ value: Any?) -> String? {
        switch value {
        case let text as String: return text.isEmpty ? nil : text
        case let number as NSNumber: return number.stringValue
        default: return nil
        }
    }

    private static func double(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: return number.doubleValue
        case let text as String: return Double(text.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }

    private static func bool(_ value: Any?) -> Bool? {
        switch value {
        case let number as NSNumber: return number.boolValue
        case let text as String:
            switch text.lowercased() {
            case "true", "1", "yes": return true
            case "false", "0", "no": return false
            default: return nil
            }
        default: return nil
        }
    }
}
