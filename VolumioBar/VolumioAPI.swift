import Foundation

/// Where a Volumio device can be reached. Volumio serves its REST API on port 3000
/// (the same port it advertises over Bonjour).
struct VolumioEndpoint: Hashable {
    static let defaultPort = 3000

    var host: String
    var port: Int

    init(host: String, port: Int = VolumioEndpoint.defaultPort) {
        self.host = host
        self.port = port
    }

    /// Accepts "192.168.1.40", "volumio.local", "192.168.1.40:3000" or "http://192.168.1.40/".
    init?(parsing raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["http://", "https://"] where text.lowercased().hasPrefix(prefix) {
            text.removeFirst(prefix.count)
        }
        if let slash = text.firstIndex(of: "/") {
            text = String(text[..<slash])
        }

        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        if parts.count == 1 {
            host = text
            port = VolumioEndpoint.defaultPort
        } else if parts.count == 2, let parsedPort = Int(parts[1]), (1...65535).contains(parsedPort) {
            host = String(parts[0])
            port = parsedPort
        } else {
            return nil
        }

        guard !host.isEmpty, !host.contains(" ") else { return nil }
    }

    /// Short form for display: the port is only shown when it isn't the default.
    var displayName: String {
        port == VolumioEndpoint.defaultPort ? host : "\(host):\(port)"
    }

    /// Form used when saving manually added devices.
    var storageString: String { "\(host):\(port)" }

    func url(path: String, query: [URLQueryItem]? = nil) -> URL? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port
        components.path = path
        components.queryItems = query
        return components.url
    }
}

/// The subset of `/api/v1/getState` that the app uses.
/// Decoding is lenient because older Volumio builds sometimes send numbers as strings or null.
struct VolumioState: Decodable, Equatable {
    var status: String?
    var title: String?
    var artist: String?
    var service: String?
    var volume: Double?
    var dbVolume: Double?
    var mute: Bool?
    var disableVolumeControl: Bool?

    private enum CodingKeys: String, CodingKey {
        case status, title, artist, service, volume, dbVolume, mute, disableVolumeControl
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = container.lenientString(.status)
        title = container.lenientString(.title)
        artist = container.lenientString(.artist)
        service = container.lenientString(.service)
        volume = container.lenientDouble(.volume)
        dbVolume = container.lenientDouble(.dbVolume)
        mute = container.lenientBool(.mute)
        disableVolumeControl = container.lenientBool(.disableVolumeControl)
    }
}

/// The subset of `/api/v1/getSystemInfo` that the app uses (name and UUID of the player).
struct VolumioSystemInfo: Decodable {
    var id: String?
    var name: String?

    private enum CodingKeys: String, CodingKey {
        case id, name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.lenientString(.id)
        name = container.lenientString(.name)
    }
}

/// Thin wrapper around Volumio's REST API.
/// Volume commands: `/api/v1/commands/?cmd=volume&volume=<0-100|plus|minus|mute|unmute|toggle>`
struct VolumioAPI {
    let endpoint: VolumioEndpoint

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3
        configuration.timeoutIntervalForResource = 6
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    func getState() async throws -> VolumioState {
        try await fetch(VolumioState.self, path: "/api/v1/getState")
    }

    func systemInfo() async throws -> VolumioSystemInfo {
        try await fetch(VolumioSystemInfo.self, path: "/api/v1/getSystemInfo")
    }

    func setVolume(_ value: Int) async throws {
        try await command("volume", volume: String(value))
    }

    /// `keyword` is one of: plus, minus, mute, unmute, toggle.
    func volume(_ keyword: String) async throws {
        try await command("volume", volume: keyword)
    }

    func togglePlayback() async throws {
        try await command("toggle")
    }

    // MARK: - Plumbing

    private func command(_ cmd: String, volume: String? = nil) async throws {
        var query = [URLQueryItem(name: "cmd", value: cmd)]
        if let volume {
            query.append(URLQueryItem(name: "volume", value: volume))
        }
        _ = try await data(path: "/api/v1/commands/", query: query)
    }

    private func fetch<T: Decodable>(_ type: T.Type, path: String) async throws -> T {
        let body = try await data(path: path)
        return try JSONDecoder().decode(T.self, from: body)
    }

    private func data(path: String, query: [URLQueryItem]? = nil) async throws -> Data {
        guard let url = endpoint.url(path: path, query: query) else {
            throw URLError(.badURL)
        }
        let (body, response) = try await Self.session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return body
    }
}

// MARK: - Lenient JSON helpers

extension KeyedDecodingContainer {
    func lenientString(_ key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return String(value) }
        return nil
    }

    func lenientDouble(_ key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return value }
        if let text = try? decodeIfPresent(String.self, forKey: key) {
            return Double(text.trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    func lenientBool(_ key: Key) -> Bool? {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return value != 0 }
        if let text = try? decodeIfPresent(String.self, forKey: key) {
            switch text.lowercased() {
            case "true", "1", "yes": return true
            case "false", "0", "no": return false
            default: return nil
            }
        }
        return nil
    }
}
