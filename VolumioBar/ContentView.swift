import AppKit
import Combine
import ServiceManagement
import SwiftUI

/// The panel that drops down from the menu bar icon.
struct ContentView: View {
    @Environment(DeviceStore.self) private var store

    @State private var isAdding = false
    @State private var newHost = ""
    @State private var invalidHost = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        let devices = store.visibleDevices

        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if let problem = store.discoveryProblem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                Divider()
            }

            if devices.isEmpty {
                emptyState
            } else {
                ForEach(devices) { device in
                    VStack(spacing: 0) {
                        if device.id != devices.first?.id {
                            Divider().padding(.horizontal, 12)
                        }
                        DeviceRow(device: device, onRemove: { store.remove(device) })
                    }
                }
            }

            Divider()
            footer
        }
        .frame(width: 320)
        .onAppear {
            store.setVisible(true)
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
        .onDisappear { store.setVisible(false) }
        // The MenuBarExtra window becomes key while it's open, so this tells us when to poll fast.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            store.setVisible(true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            store.setVisible(false)
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "hifispeaker.2.fill")
                .foregroundStyle(.secondary)
            Text("Volumio")
                .font(.headline)
            Spacer()
            Button {
                store.refreshAll()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh now")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Looking for Volumio players…")
                .font(.callout)
            Text("Not showing up? Add it by IP address below.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isAdding {
                HStack(spacing: 6) {
                    TextField("IP address, e.g. 192.168.1.40", text: $newHost)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addHost)
                    Button("Add", action: addHost)
                        .disabled(newHost.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Cancel") {
                        isAdding = false
                        newHost = ""
                        invalidHost = false
                    }
                }
                .controlSize(.small)

                if invalidHost {
                    Text("That doesn't look like an IP address or hostname.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            HStack(spacing: 12) {
                if !isAdding {
                    Button("Add by IP…") { isAdding = true }
                }
                Spacer()
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .toggleStyle(.checkbox)
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onChange(of: launchAtLogin) { _, enabled in
            setLaunchAtLogin(enabled)
        }
    }

    // MARK: - Actions

    private func addHost() {
        if store.addManual(newHost) {
            newHost = ""
            invalidHost = false
            isAdding = false
        } else {
            invalidHost = true
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        guard enabled != (service.status == .enabled) else { return }
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            launchAtLogin = service.status == .enabled
        }
    }
}
