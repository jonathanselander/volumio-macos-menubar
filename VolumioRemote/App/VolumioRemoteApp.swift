import SwiftUI
import WidgetKit

@main
struct VolumioRemoteApp: App {
    var body: some Scene {
        WindowGroup {
            RemoteView()
        }
    }
}

/// The app is mostly a host for the widget. It lets you test the address,
/// asks for Local Network access (which the widget then shares), and works as
/// a simple remote.
struct RemoteView: View {
    @AppStorage("address") private var address = "volumio.local"
    @Environment(\.scenePhase) private var scenePhase
    @State private var state: PlayerState?
    @State private var artwork: UIImage?
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("192.168.1.40 or volumio.local", text: $address)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { Task { await refresh() } }
                    Button("Connect") { Task { await refresh() } }
                } header: {
                    Text("Player address")
                } footer: {
                    Text("Use the same address in the widget: long-press the widget › Edit Widget › Address.")
                }

                if let error {
                    Section {
                        Label(error, systemImage: "wifi.exclamationmark")
                            .foregroundStyle(.red)
                    }
                }

                if let state {
                    Section("Now playing") {
                        HStack(spacing: 14) {
                            Group {
                                if let artwork {
                                    Image(uiImage: artwork).resizable().scaledToFill()
                                } else {
                                    Image(systemName: "music.note")
                                        .font(.largeTitle)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .background(Color.secondary.opacity(0.15))
                                }
                            }
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(state.title ?? "Nothing playing").font(.headline)
                                if let artist = state.artist { Text(artist).foregroundStyle(.secondary) }
                                Text(state.statusText).font(.caption).foregroundStyle(.secondary)
                            }
                        }

                        HStack(spacing: 40) {
                            Spacer()
                            controlButton("backward.fill", PlayerAction.previous)
                            controlButton(state.isPlaying ? "pause.circle.fill" : "play.circle.fill", PlayerAction.toggle, size: 44)
                            controlButton("forward.fill", PlayerAction.next)
                            Spacer()
                        }
                        .padding(.vertical, 6)
                    }

                    Section("Volume") {
                        if state.volumeControlDisabled {
                            Text("Volume control is off on this player.")
                        } else {
                            HStack(spacing: 24) {
                                controlButton(state.mute ? "speaker.slash.fill" : "speaker.wave.2.fill", PlayerAction.mute, size: 20)
                                controlButton("minus", PlayerAction.volumeDown, size: 20)
                                Text(state.mute ? "Muted" : "\(state.volume ?? 0)")
                                    .font(.title2.monospacedDigit().weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                controlButton("plus", PlayerAction.volumeUp, size: 20)
                            }
                        }
                    }
                }

                Section("Adding the widget") {
                    Text("Long-press the home screen, tap Edit › Add Widget, pick Volumio Remote and choose the large size. Then long-press the widget › Edit Widget and enter the address above.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Volumio Remote")
            .refreshable { await refresh() }
            .disabled(busy)
        }
        .task { await refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refresh() } }
        }
    }

    private func controlButton(_ systemImage: String, _ action: String, size: CGFloat = 26) -> some View {
        Button {
            Task {
                busy = true
                defer { busy = false }
                do {
                    try await PlayerAction.perform(action, at: address)
                    try? await Task.sleep(nanoseconds: 300_000_000)
                } catch {
                    self.error = "Couldn't send the command: \(error.localizedDescription)"
                }
                await refresh()
            }
        } label: {
            Image(systemName: systemImage).font(.system(size: size))
        }
        .buttonStyle(.borderless)
    }

    private func refresh() async {
        do {
            let newState = try await VolumioClient.state(at: address)
            if newState.albumArtURL != state?.albumArtURL {
                artwork = nil
                if let url = newState.albumArtURL, let data = await VolumioClient.imageData(from: url) {
                    artwork = UIImage(data: data)
                }
            }
            state = newState
            error = nil
        } catch {
            state = nil
            self.error = "Can't reach \(address). Check that you're on the same Wi-Fi and allowed Local Network access in Settings › Volumio Remote."
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
