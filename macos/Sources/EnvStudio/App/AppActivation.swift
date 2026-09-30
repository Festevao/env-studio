import AppKit

enum AppActivation {
    static func activateForUserInput() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.keyWindow?.makeKeyAndOrderFront(nil)
    }
}

final class EnvStudioAppDelegate: NSObject, NSApplicationDelegate {
    private static weak var connectivityStore: ConnectivityStore?

    static func register(connectivity: ConnectivityStore) {
        connectivityStore = connectivity
    }

    static func unregister(connectivity: ConnectivityStore) {
        if connectivityStore === connectivity {
            connectivityStore = nil
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppActivation.activateForUserInput()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard let store = Self.connectivityStore else { return }
        let shutdown = {
            store.terminateAllOwnedTunnelsSynchronously()
        }
        if Thread.isMainThread {
            MainActor.assumeIsolated { shutdown() }
        } else {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated { shutdown() }
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        NSApp.keyWindow?.makeKeyAndOrderFront(nil)
    }
}
