import EnvStudioConnectivity
import SwiftUI

struct TunnelEditSheet: View {
    @EnvironmentObject private var connectivity: ConnectivityStore
    @Binding var isPresented: Bool
    let tunnelFlag: String

    @State private var draftTunnel: TunnelDefinition?
    @State private var profileName = ""
    @State private var ssmTarget = ""
    @State private var titleText = ""
    @State private var localPortText = ""
    @State private var remotePortText = ""
    @State private var remoteHost = ""
    @State private var driver: TunnelDriver = .none
    @State private var generateToken = false
    @State private var database = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Editar conexão")
                .font(.title2)
            Text(
                "Alterações valem só para o ambiente \(connectivity.selectedEnvironment.displayName). Profile e SSM target são compartilhados por todos os túneis deste ambiente."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            if draftTunnel != nil {
                Form {
                    TextField("Profile AWS", text: $profileName)
                    TextField("SSM target (instance ID)", text: $ssmTarget)
                    TextField("Título", text: $titleText)
                    TextField("Host remoto", text: $remoteHost)
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
            } else {
                Text("Túnel não encontrado.")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancelar") { isPresented = false }
                Button("Salvar") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draftTunnel == nil)
            }
        }
        .padding(20)
        .frame(width: 520, height: 460)
        .onAppear { loadDraft() }
    }

    private func loadDraft() {
        guard let env = connectivity.currentEnvironmentConfig,
            let tunnel = env.tunnels.first(where: { $0.flag == tunnelFlag })
        else {
            draftTunnel = nil
            return
        }
        draftTunnel = tunnel
        profileName = env.awsProfileName
        ssmTarget = env.ssmTargetInstanceId
        titleText = tunnel.title
        remoteHost = tunnel.remoteHost
        localPortText = String(tunnel.localPort)
        remotePortText = String(tunnel.remotePort)
        driver = tunnel.driver
        generateToken = tunnel.generateToken
        database = tunnel.database
    }

    private func save() {
        guard var tunnel = draftTunnel else { return }
        let trimmedTitle = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
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
        tunnel.title = trimmedTitle
        tunnel.remoteHost = remoteHost.trimmingCharacters(in: .whitespacesAndNewlines)
        tunnel.localPort = localPort
        tunnel.remotePort = remotePort
        tunnel.driver = driver
        tunnel.generateToken = generateToken && (driver == .mysql || driver == .postgres)
        tunnel.database = database.trimmingCharacters(in: .whitespaces)
        let profile = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = ssmTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !profile.isEmpty, !target.isEmpty else {
            connectivity.errorMessage = "Profile e SSM target são obrigatórios."
            return
        }
        connectivity.updateTunnel(
            tunnel,
            awsProfileName: profile,
            ssmTargetInstanceId: target
        )
        connectivity.errorMessage = nil
        isPresented = false
    }
}
