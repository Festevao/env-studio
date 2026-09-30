import EnvStudioConnectivity
import SwiftUI

struct ConnectivityView: View {
    @EnvironmentObject private var connectivity: ConnectivityStore
    @EnvironmentObject private var documentStore: DocumentStore
    @State private var showConfigSheet = false
    @State private var showAddTunnelSheet = false
    @State private var tokenTunnel: TunnelDefinition?
    @State private var editingTunnelFlag: String?
    @State private var tunnelFlagPendingDelete: String?

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 12) {
                header
                if let error = connectivity.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let status = connectivity.statusMessage {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(
                    "Configuração global — vale para qualquer pasta .env aberta no app."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Text("Arquivo: \(ConnectivityPersistence.storageLocationHint)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                tunnelList
                Spacer(minLength: 0)
            }
            .padding(16)
            .opacity(connectivity.isRefreshingEnvironment ? 0.45 : 1)

            if connectivity.isRefreshingEnvironment {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Atualizando ambiente…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.08))
            }
        }
        .onChange(of: connectivity.selectedEnvironment) { _, _ in
            Task { await connectivity.refreshAfterEnvironmentChange() }
        }
        .sheet(isPresented: $showConfigSheet) {
            EnvironmentConfigSheet(isPresented: $showConfigSheet)
                .environmentObject(connectivity)
        }
        .sheet(isPresented: $showAddTunnelSheet) {
            TunnelAddSheet(isPresented: $showAddTunnelSheet)
                .environmentObject(connectivity)
        }
        .sheet(item: $tokenTunnel) { tunnel in
            TokenPanelView(tunnel: tunnel)
                .environmentObject(connectivity)
                .environmentObject(documentStore)
        }
        .sheet(isPresented: Binding(
            get: { editingTunnelFlag != nil },
            set: { if !$0 { editingTunnelFlag = nil } }
        )) {
            if let flag = editingTunnelFlag {
                TunnelEditSheet(
                    isPresented: Binding(
                        get: { editingTunnelFlag != nil },
                        set: { if !$0 { editingTunnelFlag = nil } }
                    ),
                    tunnelFlag: flag
                )
                .environmentObject(connectivity)
            }
        }
        .confirmationDialog(
            "Remover túnel?",
            isPresented: Binding(
                get: { tunnelFlagPendingDelete != nil },
                set: { if !$0 { tunnelFlagPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remover de dev, hom e prod", role: .destructive) {
                guard let flag = tunnelFlagPendingDelete else { return }
                tunnelFlagPendingDelete = nil
                Task { await connectivity.removeTunnelAcrossEnvironments(flag: flag) }
            }
            Button("Cancelar", role: .cancel) {
                tunnelFlagPendingDelete = nil
            }
        } message: {
            Text(
                "Este túnel será removido dos três ambientes (dev, hom e prod). Túneis abertos pelo app serão encerrados."
            )
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Picker("Ambiente", selection: $connectivity.selectedEnvironment) {
                ForEach(TunnelEnvironment.allCases) { env in
                    Text(env.displayName).tag(env)
                }
            }
            .frame(width: 120)
            .disabled(connectivity.isRefreshingEnvironment)
            if let profile = connectivity.currentEnvironmentConfig?.awsProfileName {
                Text("Profile: \(profile)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ssoStatusIndicator
            Button("Login SSO") {
                Task { await connectivity.loginSSO() }
            }
            .disabled(connectivity.isBusy || connectivity.isRefreshingEnvironment)
            Button("Testar profile") {
                Task { await connectivity.testProfile() }
            }
            .disabled(connectivity.isBusy || connectivity.isRefreshingEnvironment)
            Button("Configurar…") {
                showConfigSheet = true
            }
            .disabled(connectivity.isRefreshingEnvironment)
        }
    }

    private var ssoStatusIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(ssoIndicatorColor)
                .frame(width: 8, height: 8)
            Text(ssoIndicatorLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .help(ssoIndicatorHelp)
    }

    private var ssoIndicatorColor: Color {
        switch connectivity.ssoAuthStatus {
        case .valid: return .green
        case .invalid: return .red
        case .unknown: return .gray
        }
    }

    private var ssoIndicatorLabel: String {
        switch connectivity.ssoAuthStatus {
        case .valid: return "SSO OK"
        case .invalid: return "SSO necessário"
        case .unknown: return "SSO —"
        }
    }

    private var ssoIndicatorHelp: String {
        switch connectivity.ssoAuthStatus {
        case .valid:
            return "Credencial AWS válida para o profile deste ambiente (verificado a cada 5 s)."
        case .invalid:
            return "Faça Login SSO e confirme com Testar profile."
        case .unknown:
            return "Aguardando verificação de SSO."
        }
    }

    private var tunnelList: some View {
        Group {
            if let envConfig = connectivity.currentEnvironmentConfig {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Spacer()
                        Button("Adicionar túnel…") {
                            showAddTunnelSheet = true
                        }
                        .disabled(connectivity.isRefreshingEnvironment)
                    }
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(envConfig.tunnels) { tunnel in
                                tunnelRow(tunnel, envConfig: envConfig)
                            }
                        }
                    }
                }
            } else {
                Text("Nenhuma configuração para este ambiente.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func tunnelRow(_ tunnel: TunnelDefinition, envConfig: AwsEnvironmentConfig) -> some View {
        let state = connectivity.listenState(for: tunnel)
        return HStack(spacing: 10) {
            statusDot(for: tunnel)
            VStack(alignment: .leading, spacing: 2) {
                Text(tunnel.title)
                    .fontWeight(.medium)
                if tunnel.isAvailable {
                    tunnelSubtitle(tunnel: tunnel, envConfig: envConfig, state: state)
                } else {
                    Text("Indisponível neste ambiente")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Preencha o host remoto em Editar… para habilitar aqui.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if tunnel.isAvailable {
                tunnelActionButtons(tunnel: tunnel, state: state)
            }
            Button("Editar…") {
                editingTunnelFlag = tunnel.flag
            }
            .disabled(connectivity.isRefreshingEnvironment)
            Button("Excluir…", role: .destructive) {
                tunnelFlagPendingDelete = tunnel.flag
            }
            .disabled(connectivity.isRefreshingEnvironment)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func tunnelActionButtons(tunnel: TunnelDefinition, state: TunnelListenState) -> some View {
        switch state {
        case .listeningOwned:
            Button("Encerrar") {
                connectivity.closeTunnel(tunnel)
            }
            if tunnel.driver == .mysql || tunnel.driver == .postgres {
                Button("Token") {
                    tokenTunnel = tunnel
                }
            }
        case .listeningExternal:
            Button("Copiar PID") {
                connectivity.copyListeningPids(for: tunnel)
            }
        case .closed:
            Button("Abrir") {
                Task { await connectivity.openTunnel(tunnel) }
            }
            .disabled(
                !connectivity.canOpenTunnel(tunnel)
                    || connectivity.isOpeningTunnel(tunnel)
            )
            if tunnel.driver == .mysql || tunnel.driver == .postgres {
                Button("Token") { tokenTunnel = tunnel }
                    .disabled(true)
            }
        case .portUsedByOtherTunnel:
            Button("Copiar PID") {
                connectivity.copyListeningPids(for: tunnel)
            }
            Button("Abrir") {
                Task { await connectivity.openTunnel(tunnel) }
            }
            .disabled(true)
            if tunnel.driver == .mysql || tunnel.driver == .postgres {
                Button("Token") { tokenTunnel = tunnel }
                    .disabled(true)
            }
        }
    }

    private func tunnelSubtitle(
        tunnel: TunnelDefinition,
        envConfig: AwsEnvironmentConfig,
        state: TunnelListenState
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Profile: \(envConfig.awsProfileName)")
            Text("Porta local: \(tunnel.localPort)")
            Text("Porta remota: \(tunnel.remotePort)")
            Text("Host: \(tunnel.remoteHost)")
            Text("SSM target: \(envConfig.ssmTargetInstanceId)")
            if case .portUsedByOtherTunnel(let ownerKey) = state {
                Text(
                    "Porta \(tunnel.localPort) em uso por «\(ownerKey)» — este ambiente não está conectado. Vá à aba do túnel dono para encerrar."
                )
                .foregroundStyle(.orange)
            }
            if case .listeningExternal = state {
                Text(
                    "Porta \(tunnel.localPort) em uso por outro processo — não é o forward deste ambiente no app."
                )
                .foregroundStyle(.yellow)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func statusDot(for tunnel: TunnelDefinition) -> some View {
        if !tunnel.isAvailable {
            Circle()
                .fill(Color.gray.opacity(0.55))
                .frame(width: 10, height: 10)
                .help("Indisponível — configure o host remoto")
        } else {
            let state = connectivity.listenState(for: tunnel)
            let color: Color = {
                switch state {
                case .closed: return .red
                case .listeningOwned: return .green
                case .listeningExternal: return .yellow
                case .portUsedByOtherTunnel: return .orange
                }
            }()
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .help(statusHelp(state))
        }
    }

    private func statusHelp(_ state: TunnelListenState) -> String {
        switch state {
        case .closed: return "Fechado"
        case .listeningOwned: return "Aberto (Env Studio)"
        case .listeningExternal(let pids):
            let pidText = pids.map(String.init).joined(separator: ", ")
            return "Aberto (outro processo) — PID: \(pidText)"
        case .portUsedByOtherTunnel(let ownerKey):
            return "Porta ocupada por «\(ownerKey)»; este túnel não está ativo."
        }
    }
}
