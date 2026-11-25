import SwiftUI

/// Menu bar app that discovers every Volumio player on the LAN (Bonjour `_Volumio._tcp`)
/// and shows a stacked volume slider for each one.
@main
struct VolumioBarApp: App {
    @State private var store = DeviceStore()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environment(store)
        } label: {
            Image(systemName: "hifispeaker.2.fill")
        }
        .menuBarExtraStyle(.window)
    }
}
