import SwiftUI
import AppKit
import EnvStudioCore

@main
struct EnvStudioApp: App {
    @NSApplicationDelegateAdaptor(EnvStudioAppDelegate.self) private var appDelegate
    @StateObject private var store = DocumentStore()
    @StateObject private var connectivity = ConnectivityStore()

    var body: some Scene {
        WindowGroup {
            MainShellView()
                .environmentObject(store)
                .environmentObject(connectivity)
                .frame(minWidth: 960, minHeight: 560)
                .onAppear {
                    AppActivation.activateForUserInput()
                    connectivity.bindTokenSync { flag, stage, escaped in
                        store.applyTunnelToken(
                            flag: flag,
                            stage: stage,
                            escapedPassword: escaped
                        )
                    }
                }
        }
        .commands {
            CommandGroup(replacing: .saveItem) {
                Button("Salvar") {
                    store.save()
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(store.folderURL == nil || !store.hasUnsavedChanges)
                Toggle("Salvar automaticamente", isOn: $store.autoSaveEnabled)
            }
        }
    }
}
