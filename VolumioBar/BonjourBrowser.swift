import Foundation
import Network

/// A Volumio player found over Bonjour and resolved to an IPv4 address.
struct DiscoveredService: Equatable {
    /// The Bonjour service instance name (normally the player's name).
    let serviceName: String
    /// `UUID` from the TXT record: stable across renames and IP changes.
    let uuid: String?
    /// `volumioName` from the TXT record.
    let displayName: String
    let host: String
    let port: Int
}

/// Browses for `_Volumio._tcp` (the service every Volumio 2/3 player advertises on port 3000)
/// and resolves each result to an IPv4 address the REST API can be called on.
///
/// All callbacks are delivered on the main queue.
final class BonjourBrowser {
    static let serviceType = "_Volumio._tcp"

    var onResolved: ((DiscoveredService) -> Void)?
    /// Called with the full set of service names currently on the network.
    var onServicesChanged: ((Set<String>) -> Void)?
    /// nil when discovery is healthy, otherwise a short explanation for the UI.
    var onProblem: ((String?) -> Void)?

    private var browser: NWBrowser?
    private var resolving: [String: NWConnection] = [:]

    func start() {
        stop()

        let parameters = NWParameters()
        parameters.includePeerToPeer = false
        let browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: Self.serviceType, domain: nil),
            using: parameters
        )

        browser.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.onProblem?(nil)
            case .waiting(let error):
                self.onProblem?(Self.describe(error))
            case .failed(let error):
                self.onProblem?(Self.describe(error))
                // Try again in a bit (network changes, mDNSResponder restarts, ...).
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                    self?.start()
                }
            default:
                break
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, changes in
            guard let self else { return }
            let present = Set(results.compactMap { Self.serviceName(of: $0.endpoint) })
            self.onServicesChanged?(present)

            for change in changes {
                switch change {
                case .added(let result):
                    self.resolve(result)
                case .changed(_, let result, _):
                    self.resolve(result)
                default:
                    break
                }
            }
        }

        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
        resolving.values.forEach { $0.cancel() }
        resolving.removeAll()
    }

    // MARK: - Resolving

    private func resolve(_ result: NWBrowser.Result) {
        guard let name = Self.serviceName(of: result.endpoint) else { return }

        var txt: [String: String] = [:]
        if case let .bonjour(record) = result.metadata {
            txt = record.dictionary
        }
        let uuid = txt["UUID"]
        let displayName = txt["volumioName"] ?? name

        resolving[name]?.cancel()

        // Open (and immediately close) a TCP connection to the service to learn its IPv4 address.
        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = 5
        let parameters = NWParameters(tls: nil, tcp: tcp)
        if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ip.version = .v4
        }

        let connection = NWConnection(to: result.endpoint, using: parameters)
        resolving[name] = connection

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .ready:
                if let remote = connection.currentPath?.remoteEndpoint,
                   case let .hostPort(host, port) = remote,
                   let hostString = Self.string(for: host) {
                    self.onResolved?(DiscoveredService(
                        serviceName: name,
                        uuid: uuid,
                        displayName: displayName,
                        host: hostString,
                        port: Int(port.rawValue)
                    ))
                }
                self.finishResolving(name, connection)
            case .failed, .waiting:
                self.finishResolving(name, connection)
            default:
                break
            }
        }
        connection.start(queue: .main)
    }

    private func finishResolving(_ name: String, _ connection: NWConnection) {
        connection.cancel()
        if resolving[name] === connection {
            resolving[name] = nil
        }
    }

    // MARK: - Helpers

    private static func serviceName(of endpoint: NWEndpoint) -> String? {
        if case let .service(name, _, _, _) = endpoint { return name }
        return nil
    }

    private static func string(for host: NWEndpoint.Host) -> String? {
        switch host {
        case .ipv4(let address):
            // Build the dotted quad from raw bytes so no "%en0" interface suffix sneaks in.
            return address.rawValue.map { String($0) }.joined(separator: ".")
        case .name(let name, _):
            return name
        case .ipv6:
            return nil
        @unknown default:
            return nil
        }
    }

    private static func describe(_ error: NWError) -> String {
        // kDNSServiceErr_PolicyDenied: the user hasn't allowed Local Network access.
        if case let .dns(code) = error, code == -65570 {
            return "Local Network access is off. Turn on VolumioBar in System Settings › Privacy & Security › Local Network."
        }
        return "Discovery problem: \(error.localizedDescription)"
    }
}
