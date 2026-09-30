import SwiftUI

struct MainShellView: View {
    @EnvironmentObject private var documentStore: DocumentStore
    @EnvironmentObject private var connectivity: ConnectivityStore

    var body: some View {
        TabView {
            DocumentView()
                .tabItem {
                    Label(".env", systemImage: "doc.text")
                }
            ConnectivityView()
                .tabItem {
                    Label("Conexões", systemImage: "network")
                }
        }
        .environmentObject(documentStore)
        .environmentObject(connectivity)
    }
}
