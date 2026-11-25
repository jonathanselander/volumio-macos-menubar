import Foundation
import Observation

/// Keeps the list of Volumio players: those found over Bonjour plus any you added by IP.
@MainActor
@Observable
final class DeviceStore {
    private(set) var devices: [VolumioDevice] = []
    /// Shown as a warning in the header when Bonjour discovery isn't working.
    private(set) var discoveryProblem: String?

    private let browser = BonjourBrowser()
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var isVisible = false

    private static let manualHostsKey = "manualHosts"
    /// Poll quickly while the panel is open, slowly otherwise.
    private static let visibleInterval: Duration = .milliseconds(1500)
    private static let hiddenInterval: Duration = .seconds(30)

    init() {
        // BonjourBrowser delivers everything on the main queue.
        browser.onResolved = { [weak self] service in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.upsert(service)
            }
        }
        browser.onServicesChanged = { [weak self] present in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.prune(keeping: present)
            }
        }
        browser.onProblem = { [weak self] problem in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.discoveryProblem = problem
            }
        }
        browser.start()

        for entry in UserDefaults.standard.stringArray(forKey: Self.manualHostsKey) ?? [] {
            addManual(entry)
        }

        restartPolling()
    }

    /// Devices to show, sorted by name. A manually added device is hidden
    /// once the same player (same UUID) is also found over Bonjour.
    var visibleDevices: [VolumioDevice] {
        let discoveredIDs = Set(devices.filter { $0.source == .discovered }.map { $0.id })
        return devices
            .filter { device in
                guard device.source == .manual, let remoteID = device.remoteID else { return true }
                return !discoveredIDs.contains(remoteID)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: - Bonjour

    private func upsert(_ service: DiscoveredService) {
        let id = service.uuid ?? "bonjour:\(service.serviceName)"
        let endpoint = VolumioEndpoint(host: service.host, port: service.port)

        let device: VolumioDevice
        if let existing = devices.first(where: { $0.id == id }) {
            device = existing
            device.name = service.displayName
            device.endpoint = endpoint
        } else {
            device = VolumioDevice(id: id, name: service.displayName, endpoint: endpoint, source: .discovered)
            devices.append(device)
        }
        device.serviceName = service.serviceName
        Task { await device.refresh() }
    }

    private func prune(keeping present: Set<String>) {
        devices.removeAll { device in
            guard device.source == .discovered, let name = device.serviceName else { return false }
            return !present.contains(name)
        }
    }

    // MARK: - Manual devices

    /// Adds a player by IP/hostname. Returns false if the text isn't a usable address.
    @discardableResult
    func addManual(_ text: String) -> Bool {
        guard let endpoint = VolumioEndpoint(parsing: text) else { return false }
        let id = "manual:\(endpoint.storageString)"
        if !devices.contains(where: { $0.id == id }) {
            let device = VolumioDevice(id: id, name: endpoint.displayName, endpoint: endpoint, source: .manual)
            devices.append(device)
            saveManualDevices()
            Task { await device.refresh() }
        }
        return true
    }

    func remove(_ device: VolumioDevice) {
        devices.removeAll { $0.id == device.id }
        saveManualDevices()
    }

    private func saveManualDevices() {
        let hosts = devices.filter { $0.source == .manual }.map { $0.endpoint.storageString }
        UserDefaults.standard.set(hosts, forKey: Self.manualHostsKey)
    }

    // MARK: - Polling

    func setVisible(_ visible: Bool) {
        guard visible != isVisible else { return }
        isVisible = visible
        if visible { refreshAll() }
        restartPolling()
    }

    func refreshAll() {
        Task { await refreshAllNow() }
    }

    private func refreshAllNow() async {
        let current = devices
        await withTaskGroup(of: Void.self) { group in
            for device in current {
                group.addTask { await device.refresh() }
            }
        }
    }

    private func restartPolling() {
        pollTask?.cancel()
        let interval = isVisible ? Self.visibleInterval : Self.hiddenInterval
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self else { return }
                await self.refreshAllNow()
            }
        }
    }
}
