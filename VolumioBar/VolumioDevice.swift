import Foundation
import Observation

/// One Volumio player and its latest known state.
@MainActor
@Observable
final class VolumioDevice: Identifiable {
    enum Source {
        case discovered
        case manual
    }

    /// How long after a local change incoming polls must not overwrite the volume/mute state.
    /// This keeps the slider from jumping back while you drag it.
    private static let holdoff: TimeInterval = 1.5

    nonisolated let id: String
    let source: Source

    var name: String
    var endpoint: VolumioEndpoint
    /// Bonjour service name (discovered devices only).
    var serviceName: String?
    /// UUID reported by the player itself (manual devices), used to hide duplicates.
    var remoteID: String?

    private(set) var state = VolumioState()
    private(set) var isOnline = false
    private(set) var lastError: String?
    /// True right after you moved the slider; hides the (possibly stale) dB readout.
    private(set) var recentlyChanged = false

    @ObservationIgnored private var pendingVolume: Int?
    @ObservationIgnored private var isSending = false
    @ObservationIgnored private var lastLocalChange = Date.distantPast
    @ObservationIgnored private var didFetchInfo = false

    init(id: String, name: String, endpoint: VolumioEndpoint, source: Source) {
        self.id = id
        self.name = name
        self.endpoint = endpoint
        self.source = source
    }

    private var api: VolumioAPI { VolumioAPI(endpoint: endpoint) }

    // MARK: - Derived values for the UI

    var volume: Double { state.volume ?? 0 }
    var isMuted: Bool { state.mute ?? false }
    var isPlaying: Bool { state.status == "play" }
    var isVolumeLocked: Bool { state.disableVolumeControl ?? false }

    /// Binding target for the slider: reading gives the current volume, writing sends it.
    var sliderVolume: Double {
        get { volume }
        set { setVolume(newValue) }
    }

    var volumeText: String {
        isMuted ? "Muted" : "\(Int(volume.rounded()))"
    }

    /// e.g. "−32.5 dB" when the player reports dB (miniDSP SHD and other hardware-volume devices).
    var dbText: String? {
        guard !recentlyChanged, let db = state.dbVolume else { return nil }
        return String(format: "%.1f dB", db)
    }

    var nowPlaying: String? {
        let parts = [state.artist, state.title]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " – ")
    }

    var webURL: URL? {
        VolumioEndpoint(host: endpoint.host, port: 80).url(path: "/")
    }

    // MARK: - Polling

    func refresh() async {
        if source == .manual && !didFetchInfo {
            await fetchInfo()
        }
        do {
            var fresh = try await api.getState()
            let holding = isSending
                || pendingVolume != nil
                || Date().timeIntervalSince(lastLocalChange) < Self.holdoff
            if holding {
                fresh.volume = state.volume
                fresh.dbVolume = state.dbVolume
                fresh.mute = state.mute
            } else if recentlyChanged {
                recentlyChanged = false
            }
            if fresh != state { state = fresh }
            if !isOnline { isOnline = true }
            if lastError != nil { lastError = nil }
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            isOnline = false
            lastError = error.localizedDescription
        }
    }

    private func fetchInfo() async {
        guard let info = try? await api.systemInfo() else { return }
        didFetchInfo = true
        if let name = info.name, !name.isEmpty { self.name = name }
        remoteID = info.id
    }

    // MARK: - Commands

    func setVolume(_ value: Double) {
        let clamped = min(max(Int(value.rounded()), 0), 100)
        // The slider reports fractional values; only send when the integer level changes.
        guard Double(clamped) != state.volume else { return }
        state.volume = Double(clamped)
        markLocalChange()
        pendingVolume = clamped
        flushVolume()
    }

    /// Sends the latest requested volume, coalescing slider drags to one request in flight at a time.
    private func flushVolume() {
        guard !isSending else { return }
        isSending = true
        Task {
            while let value = pendingVolume {
                pendingVolume = nil
                do {
                    try await api.setVolume(value)
                } catch {
                    lastError = error.localizedDescription
                }
            }
            isSending = false
            lastLocalChange = Date()
        }
    }

    func toggleMute() {
        let newValue = !isMuted
        state.mute = newValue
        markLocalChange()
        Task {
            do {
                try await api.volume(newValue ? "mute" : "unmute")
            } catch {
                lastError = error.localizedDescription
            }
            lastLocalChange = Date()
        }
    }

    /// Uses Volumio's own volume step (Settings › Playback options › Volume steps).
    func step(up: Bool) {
        Task {
            do {
                try await api.volume(up ? "plus" : "minus")
                try? await Task.sleep(for: .milliseconds(250))
                lastLocalChange = .distantPast
                await refresh()
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func togglePlayback() {
        state.status = isPlaying ? "pause" : "play"
        Task {
            try? await api.togglePlayback()
            try? await Task.sleep(for: .milliseconds(400))
            await refresh()
        }
    }

    private func markLocalChange() {
        lastLocalChange = Date()
        recentlyChanged = true
    }
}
