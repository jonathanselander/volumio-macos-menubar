import AppKit
import SwiftUI

/// One player in the stack: name, level, slider, mute, ± steps and what's playing.
struct DeviceRow: View {
    @Bindable var device: VolumioDevice
    var onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            titleLine
            controls
            if let nowPlaying = device.nowPlaying {
                playbackLine(nowPlaying)
            }
            statusLine
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .opacity(device.isOnline ? 1 : 0.6)
        .contentShape(Rectangle())
        .contextMenu {
            if let url = device.webURL {
                Button("Open Volumio Web UI") { NSWorkspace.shared.open(url) }
            }
            Text(device.endpoint.displayName)
            if device.source == .manual {
                Divider()
                Button("Remove", role: .destructive, action: onRemove)
            }
        }
    }

    private var titleLine: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(device.isOnline ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 7, height: 7)
            Text(device.name)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 8)
            if let db = device.dbText {
                Text(db)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Text(device.volumeText)
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 30, alignment: .trailing)
        }
    }

    private var controls: some View {
        HStack(spacing: 6) {
            Button {
                device.toggleMute()
            } label: {
                Image(systemName: device.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .frame(width: 18)
            }
            .help(device.isMuted ? "Unmute" : "Mute")

            Slider(value: $device.sliderVolume, in: 0...100)
                .controlSize(.small)
                .tint(device.isMuted ? Color.gray : Color.accentColor)

            Button {
                device.step(up: false)
            } label: {
                Image(systemName: "minus")
            }
            .help("Volume down one step")

            Button {
                device.step(up: true)
            } label: {
                Image(systemName: "plus")
            }
            .help("Volume up one step")
        }
        .buttonStyle(.borderless)
        .disabled(!device.isOnline || device.isVolumeLocked)
    }

    private func playbackLine(_ nowPlaying: String) -> some View {
        HStack(spacing: 6) {
            Button {
                device.togglePlayback()
            } label: {
                Image(systemName: device.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 18)
            }
            .buttonStyle(.borderless)
            .help(device.isPlaying ? "Pause" : "Play")

            Text(nowPlaying)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if !device.isOnline, let error = device.lastError {
            Text("Can't reach \(device.endpoint.displayName): \(error)")
                .font(.caption2)
                .foregroundStyle(.red)
                .lineLimit(2)
        } else if device.isVolumeLocked {
            Text("Volume control is turned off on this player.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
