import AppIntents
import WidgetKit

/// The widget's settings (long-press the widget › Edit Widget).
struct PlayerConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Volumio player"
    static var description = IntentDescription("Which Volumio player the widget shows and controls.")

    @Parameter(title: "Address", description: "IP address or hostname, e.g. 192.168.1.40", default: "volumio.local")
    var address: String

    init() {}

    init(address: String) {
        self.address = address
    }
}

/// What a widget button does. Kept as a string so one intent type covers every button.
enum PlayerAction {
    static let toggle = "toggle"
    static let previous = "prev"
    static let next = "next"
    static let volumeUp = "up"
    static let volumeDown = "down"
    static let mute = "mute"

    static let volumeStep = 5

    static func setVolume(_ level: Int) -> String { "vol:\(level)" }

    /// Sends the command for `action` to the player at `address`.
    static func perform(_ action: String, at address: String) async throws {
        switch action {
        case toggle, previous, next:
            try await VolumioClient.command(action, at: address)
        case volumeUp, volumeDown, mute:
            let state = try await VolumioClient.state(at: address)
            if action == mute {
                try await VolumioClient.command("volume", volume: state.mute ? "unmute" : "mute", at: address)
            } else {
                let current = state.volume ?? 0
                let delta = action == volumeUp ? volumeStep : -volumeStep
                let target = max(0, min(100, current + delta))
                try await VolumioClient.command("volume", volume: String(target), at: address)
            }
        default:
            if action.hasPrefix("vol:"), let level = Int(action.dropFirst(4)) {
                try await VolumioClient.command("volume", volume: String(max(0, min(100, level))), at: address)
            }
        }
    }
}

/// Runs from a widget button without opening the app. WidgetKit reloads the
/// widget when it returns, so the new state shows right away.
struct PlayerCommandIntent: AppIntent {
    static var title: LocalizedStringResource = "Control Volumio"
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Address")
    var address: String

    @Parameter(title: "Action")
    var action: String

    init() {}

    init(address: String, action: String) {
        self.address = address
        self.action = action
    }

    func perform() async throws -> some IntentResult {
        try await PlayerAction.perform(action, at: address)
        // Give Volumio a moment so the reload sees the new state.
        try? await Task.sleep(nanoseconds: 350_000_000)
        return .result()
    }
}
