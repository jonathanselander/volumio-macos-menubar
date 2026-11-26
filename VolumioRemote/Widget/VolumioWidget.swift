import AppIntents
import SwiftUI
import UIKit
import WidgetKit

@main
struct VolumioWidgetBundle: WidgetBundle {
    var body: some Widget {
        VolumioWidget()
    }
}

struct VolumioWidget: Widget {
    let kind = "VolumioWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: PlayerConfigIntent.self, provider: PlayerProvider()) { entry in
            PlayerWidgetView(entry: entry)
        }
        .configurationDisplayName("Volumio")
        .description("What's playing, with playback and volume controls.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

// MARK: - Timeline

struct PlayerEntry: TimelineEntry {
    var date: Date
    /// nil until the address is set in Edit Widget.
    var address: String?
    var state: PlayerState?
    var artwork: UIImage?
    var error: String?
}

struct PlayerProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> PlayerEntry {
        PlayerEntry(date: .now, address: "volumio.local", state: .preview)
    }

    func snapshot(for configuration: PlayerConfigIntent, in context: Context) async -> PlayerEntry {
        if context.isPreview {
            return placeholder(in: context)
        }
        return await load(configuration.playerAddress)
    }

    func timeline(for configuration: PlayerConfigIntent, in context: Context) async -> Timeline<PlayerEntry> {
        let entry = await load(configuration.playerAddress)
        // iOS decides the real refresh rate. Taps on the buttons reload right away.
        let next = Date().addingTimeInterval(entry.state?.isPlaying == true ? 5 * 60 : 15 * 60)
        return Timeline(entries: [entry], policy: .after(next))
    }

    private func load(_ address: String?) async -> PlayerEntry {
        guard let address else {
            return PlayerEntry(date: .now, address: nil)
        }
        do {
            let state = try await VolumioClient.state(at: address)
            var artwork: UIImage?
            if let url = state.albumArtURL, let data = await VolumioClient.imageData(from: url) {
                // Widgets have a small memory budget, so shrink the cover first.
                artwork = UIImage(data: data)?.preparingThumbnail(of: CGSize(width: 300, height: 300))
            }
            return PlayerEntry(date: .now, address: address, state: state, artwork: artwork)
        } catch {
            return PlayerEntry(date: .now, address: address, error: "Can't reach \(address)")
        }
    }
}

// MARK: - Views

private let accent = Color(red: 0.33, green: 0.78, blue: 0.53)

struct PlayerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PlayerEntry

    var body: some View {
        Group {
            if let address = entry.address, let state = entry.state {
                switch family {
                case .systemSmall: SmallPlayerView(entry: entry, address: address, state: state)
                case .systemMedium: MediumPlayerView(entry: entry, address: address, state: state)
                default: LargePlayerView(entry: entry, address: address, state: state)
                }
            } else if let address = entry.address {
                ErrorView(address: address, message: entry.error)
            } else {
                SetupView()
            }
        }
        .foregroundStyle(.white)
        .containerBackground(for: .widget) {
            WidgetBackground(artwork: entry.artwork)
        }
    }
}

struct WidgetBackground: View {
    let artwork: UIImage?

    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.09, blue: 0.11)
            if let artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 40)
                    .opacity(0.55)
            }
            LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
        }
    }
}

struct Artwork: View {
    let image: UIImage?
    let size: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Color.white.opacity(0.12)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.4))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.1, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
    }
}

struct TrackText: View {
    let state: PlayerState
    var titleFont: Font = .headline
    var lines = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(state.title ?? "Nothing playing")
                .font(titleFont)
                .lineLimit(lines)
            if let artist = state.artist {
                Text(artist)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            }
        }
    }
}

/// A button that runs a player command in place.
struct ControlButton: View {
    let address: String
    let action: String
    let systemImage: String
    var size: CGFloat = 20
    var tint: Color = .white

    var body: some View {
        Button(intent: PlayerCommandIntent(address: address, action: action)) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(tint)
                .frame(minWidth: 36, minHeight: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct TransportControls: View {
    let address: String
    let state: PlayerState
    var scale: CGFloat = 1

    var body: some View {
        HStack(spacing: 22 * scale) {
            ControlButton(address: address, action: PlayerAction.previous, systemImage: "backward.fill", size: 20 * scale)
            ControlButton(address: address, action: PlayerAction.toggle,
                          systemImage: state.isPlaying ? "pause.circle.fill" : "play.circle.fill",
                          size: 44 * scale)
            ControlButton(address: address, action: PlayerAction.next, systemImage: "forward.fill", size: 20 * scale)
        }
    }
}

/// Mute, -, ten tappable level segments, +, and the level as a number.
struct VolumeControls: View {
    let address: String
    let state: PlayerState
    var showSegments = true

    var body: some View {
        if state.volumeControlDisabled {
            Text("Volume control is off on this player")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        } else {
            let volume = state.volume ?? 0
            HStack(spacing: 4) {
                ControlButton(address: address, action: PlayerAction.mute,
                              systemImage: state.mute ? "speaker.slash.fill" : "speaker.wave.2.fill",
                              size: 15, tint: state.mute ? accent : .white)
                ControlButton(address: address, action: PlayerAction.volumeDown, systemImage: "minus", size: 15)
                if showSegments {
                    HStack(spacing: 3) {
                        ForEach(1...10, id: \.self) { step in
                            let level = step * 10
                            Button(intent: PlayerCommandIntent(address: address, action: PlayerAction.setVolume(level))) {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(volume >= level - 5 ? (state.mute ? Color.white.opacity(0.45) : accent) : Color.white.opacity(0.2))
                                    .frame(height: 14)
                                    .frame(maxWidth: .infinity, minHeight: 36)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                ControlButton(address: address, action: PlayerAction.volumeUp, systemImage: "plus", size: 15)
                Text(state.mute ? "Muted" : "\(volume)")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .frame(minWidth: 28, alignment: .trailing)
                    .padding(.trailing, 2)
            }
        }
    }
}

struct LargePlayerView: View {
    let entry: PlayerEntry
    let address: String
    let state: PlayerState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                Artwork(image: entry.artwork, size: 136)
                VStack(alignment: .leading, spacing: 6) {
                    TrackText(state: state, titleFont: .title3.weight(.bold), lines: 3)
                    if let album = state.album {
                        Text(album)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                    Text(state.statusText)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 8)
            HStack {
                Spacer()
                TransportControls(address: address, state: state, scale: 1.25)
                Spacer()
            }
            Spacer(minLength: 8)
            VolumeControls(address: address, state: state)
        }
        .padding(16)
    }
}

struct MediumPlayerView: View {
    let entry: PlayerEntry
    let address: String
    let state: PlayerState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                Artwork(image: entry.artwork, size: 86)
                VStack(alignment: .leading, spacing: 3) {
                    TrackText(state: state, titleFont: .headline, lines: 2)
                    Text(state.statusText)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                TransportControls(address: address, state: state, scale: 0.7)
                Spacer(minLength: 8)
                VolumeControls(address: address, state: state, showSegments: false)
                    .fixedSize()
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 18)
        .padding(.vertical, 12)
    }
}

struct SmallPlayerView: View {
    let entry: PlayerEntry
    let address: String
    let state: PlayerState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Artwork(image: entry.artwork, size: 52)
                Spacer(minLength: 0)
                ControlButton(address: address, action: PlayerAction.toggle,
                              systemImage: state.isPlaying ? "pause.circle.fill" : "play.circle.fill", size: 34)
            }
            Spacer(minLength: 0)
            Text(state.title ?? "Nothing playing")
                .font(.footnote.weight(.bold))
                .lineLimit(2)
            Text(state.mute ? "Muted" : "Volume \(state.volume ?? 0)")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(14)
    }
}

struct ErrorView: View {
    let address: String
    let message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Volumio", systemImage: "wifi.exclamationmark")
                .font(.headline)
            Text(message ?? "Can't reach \(address)")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))
            Text("Works on the same Wi-Fi as the player. Long-press › Edit Widget to change the address.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
            Spacer(minLength: 0)
            Button(intent: PlayerCommandIntent(address: address, action: "refresh")) {
                Label("Try again", systemImage: "arrow.clockwise")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
    }
}

/// Shown until the widget has an address.
struct SetupView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Volumio", systemImage: "hifispeaker.fill")
                .font(.headline)
            Text("Set the player's address")
                .font(.subheadline.weight(.semibold))
            Text("Long-press this widget › Edit Widget › Address, and enter the same address as in the app, e.g. 192.168.1.40.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.65))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
    }
}
