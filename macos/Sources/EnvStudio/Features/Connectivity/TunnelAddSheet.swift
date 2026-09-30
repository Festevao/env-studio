import EnvStudioConnectivity
import SwiftUI

struct TunnelAddSheet: View {
    @EnvironmentObject private var connectivity: ConnectivityStore
    @Binding var isPresented: Bool

    @State private var flagText = ""
    @State private var titleText = ""
    @State private var aliasesText = ""
    @State private var remoteHost = ""
    @State private var localPortText = ""
    @State private var remotePortText = ""
    @State private var driver: TunnelDriver = .none
    @State private var generateToken = false
    @State private var database = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Adicionar túnel SSM")
                .font(.title2)
            Text(
                "Será criado em dev, hom e prod com estes valores iniciais. Ajuste host e portas por ambiente depois em Editar…"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Form {
                TextField("Identificador (flag)", text: $flagText)
                TextField("Título", text: $titleText)
                TextField("Aliases (opcional)", text: $aliasesText)
                TextField("Host remoto (opcional)", text: $remoteHost)
                TextField("Porta local", text: $localPortText)
                TextField("Porta remota", text: $remotePortText)
                Picker("Driver", selection: $driver) {
                    Text("Nenhum").tag(TunnelDriver.none)
                    Text("MySQL").tag(TunnelDriver.mysql)
                    Text("Postgres").tag(TunnelDriver.postgres)
                }
                if driver == .mysql || driver == .postgres {
                    Toggle("Gerar token RDS", isOn: $generateToken)
                    TextField("Database", text: $database)
                }
            }
            HStack {
                Spacer()
                Button("Cancelar") { isPresented = false }
                Button("Adicionar") { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520, height: 480)
    }

    private func save() {
        guard let flag = TunnelFlagValidator.normalize(flagText) else {
            connectivity.errorMessage = TunnelCatalogError.invalidFlag.errorDescription
            return
        }
        let title = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            connectivity.errorMessage = TunnelCatalogError.emptyTitle.errorDescription
            return
        }
        guard let localPort = Int(localPortText.trimmingCharacters(in: .whitespaces)),
            let remotePort = Int(remotePortText.trimmingCharacters(in: .whitespaces)),
            (1...65_535).contains(localPort),
            (1...65_535).contains(remotePort)
        else {
            connectivity.errorMessage = TunnelCatalogError.invalidPorts.errorDescription
            return
        }
        let host = remoteHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let definition = TunnelDefinition(
            flag: flag,
            aliases: aliasesText.trimmingCharacters(in: .whitespaces),
            title: title,
            remoteHost: host,
            remotePort: remotePort,
            localPort: localPort,
            generateToken: generateToken && (driver == .mysql || driver == .postgres),
            database: database.trimmingCharacters(in: .whitespaces),
            driver: driver
        )
        connectivity.addTunnelAcrossEnvironments(definition)
        if connectivity.errorMessage == nil {
            isPresented = false
        }
    }
}
