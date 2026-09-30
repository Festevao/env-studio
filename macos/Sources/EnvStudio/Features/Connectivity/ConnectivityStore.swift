import AppKit
import Combine
import EnvStudioConnectivity
import EnvStudioCore
import Foundation

@MainActor
public final class ConnectivityStore: ObservableObject {
    @Published public private(set) var config: ConnectivityConfig
    @Published public var selectedEnvironment: TunnelEnvironment = .dev
    @Published public private(set) var listenStates: [String: TunnelListenState] = [:]
    @Published public private(set) var awsProfiles: [String] = []
    @Published public var statusMessage: String?
    @Published public var errorMessage: String?
    @Published public private(set) var tokenSessions: [String: RdsTokenSession] = [:]
    @Published public private(set) var passwordTests: [String: RdsPasswordTestResult] = [:]
    @Published public private(set) var isBusy = false
    @Published public private(set) var openingTunnelKeys: Set<String> = []
    @Published public private(set) var ssoAuthStatus: SsoAuthStatus = .unknown
    @Published public private(set) var isRefreshingEnvironment = false

    private let tunnelRunner = TunnelRunner()
    private var monitorTask: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?
    private var shellEnvironment: [String: String] = [:]
    private var tokenSync: ((String, EnvStage, String) -> String)?

    public func bindTokenSync(_ handler: @escaping (String, EnvStage, String) -> String) {
        tokenSync = handler
    }

    public func sqlTunnelFlags() -> [String] {
        var flags: [String] = []
        for environment in TunnelEnvironment.allCases {
            guard let envConfig = config.config(for: environment) else { continue }
            for tunnel in envConfig.tunnels where tunnel.driver == .mysql || tunnel.driver == .postgres {
                if !flags.contains(tunnel.flag) {
                    flags.append(tunnel.flag)
                }
            }
        }
        return flags
    }

    public init() {
        config = ConnectivityPersistence.load()
        awsProfiles = AwsConfigReader.listProfileNames()
        EnvStudioAppDelegate.register(connectivity: self)
        startMonitoring()
        startCountdownTicker()
        Task { await refreshSsoStatus() }
    }

    deinit {
        monitorTask?.cancel()
        countdownTask?.cancel()
        EnvStudioAppDelegate.unregister(connectivity: self)
    }

    /// Encerra todos os túneis abertos pelo app (async).
    public func terminateAllOwnedTunnels() async {
        monitorTask?.cancel()
        countdownTask?.cancel()
        await tunnelRunner.closeAll()
        listenStates = [:]
        openingTunnelKeys = []
    }

    /// Quit do app — deve completar antes do processo morrer.
    public func terminateAllOwnedTunnelsSynchronously() {
        monitorTask?.cancel()
        countdownTask?.cancel()
        tunnelRunner.closeAllSynchronously()
        listenStates = [:]
        openingTunnelKeys = []
    }

    public var currentEnvironmentConfig: AwsEnvironmentConfig? {
        config.config(for: selectedEnvironment)
    }

    public func reloadProfiles() {
        awsProfiles = AwsConfigReader.listProfileNames()
    }

    public func saveConfiguration() {
        do {
            try ConnectivityPersistence.save(config)
            statusMessage = "Configuração SSM salva (global)."
            errorMessage = nil
        } catch {
            errorMessage = "Falha ao salvar configuração: \(error.localizedDescription)"
        }
    }

    public func updateEnvironmentConfig(_ envConfig: AwsEnvironmentConfig) {
        config.setConfig(envConfig, for: selectedEnvironment)
        saveConfiguration()
        Task { await refreshListenStates() }
    }

    public func restoreDefaultsForSelectedEnvironment() {
        config.setConfig(
            ConnectivityDefaults.restoreEnvironment(selectedEnvironment),
            for: selectedEnvironment
        )
        saveConfiguration()
    }

    public func listenState(for tunnel: TunnelDefinition) -> TunnelListenState {
        let key = tunnel.tunnelKey(environment: selectedEnvironment)
        return listenStates[key] ?? .closed
    }

    public func isTunnelListening(for tunnel: TunnelDefinition) -> Bool {
        if case .listeningOwned = listenState(for: tunnel) {
            return true
        }
        return false
    }

    public func isOpeningTunnel(_ tunnel: TunnelDefinition) -> Bool {
        let key = tunnel.tunnelKey(environment: selectedEnvironment)
        return openingTunnelKeys.contains(key)
    }

    public func canOpenTunnel(_ tunnel: TunnelDefinition) -> Bool {
        switch listenState(for: tunnel) {
        case .closed:
            return ssoAuthStatus != .invalid
        case .listeningOwned, .listeningExternal, .portUsedByOtherTunnel:
            return false
        }
    }

    public func updateTunnel(
        _ tunnel: TunnelDefinition,
        awsProfileName: String,
        ssmTargetInstanceId: String
    ) {
        guard var envConfig = currentEnvironmentConfig else { return }
        envConfig.awsProfileName = awsProfileName
        envConfig.ssmTargetInstanceId = ssmTargetInstanceId
        guard let index = envConfig.tunnels.firstIndex(where: { $0.flag == tunnel.flag }) else {
            return
        }
        envConfig.tunnels[index] = tunnel
        config.setConfig(envConfig, for: selectedEnvironment)
        saveConfiguration()
        Task { await refreshListenStates() }
    }

    public func addTunnelAcrossEnvironments(_ definition: TunnelDefinition) {
        do {
            try config.addTunnelAcrossEnvironments(definition)
            saveConfiguration()
            statusMessage =
                "Túnel «\(definition.title)» adicionado em dev, hom e prod."
            errorMessage = nil
            Task { await refreshListenStates() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func removeTunnelAcrossEnvironments(flag: String) async {
        guard config.containsTunnel(flag: flag) else {
            errorMessage = TunnelCatalogError.tunnelNotFound(flag).errorDescription
            return
        }
        for environment in TunnelEnvironment.allCases {
            guard let tunnel = config.tunnel(flag: flag, environment: environment) else {
                continue
            }
            let key = tunnel.tunnelKey(environment: environment)
            if tunnelRunner.isAppOwned(tunnelKey: key) {
                await tunnelRunner.closeTunnel(
                    tunnelKey: key,
                    localPort: tunnel.localPort
                )
            }
        }
        let suffix = "-\(flag)"
        tokenSessions = tokenSessions.filter { !$0.key.hasSuffix(suffix) }
        passwordTests = passwordTests.filter { !$0.key.hasSuffix(suffix) }
        listenStates = listenStates.filter { !$0.key.hasSuffix(suffix) }
        do {
            try config.removeTunnelAcrossEnvironments(flag: flag)
            saveConfiguration()
            statusMessage = "Túnel removido de dev, hom e prod."
            errorMessage = nil
            await refreshListenStates()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func tokenSession(for tunnel: TunnelDefinition) -> RdsTokenSession? {
        tokenSessions[tunnel.tunnelKey(environment: selectedEnvironment)]
    }

    public func passwordTest(for tunnel: TunnelDefinition) -> RdsPasswordTestResult {
        passwordTests[tunnel.tunnelKey(environment: selectedEnvironment)] ?? .none
    }

    public func loginSSO() async {
        guard let envConfig = currentEnvironmentConfig else { return }
        isBusy = true
        defer { isBusy = false }
        let aws = resolvedAwsPath()
        let env = await awsEnvironment(for: envConfig)
        let result = await ShellCommandRunner.runAwsViaLoginShell(
            awsExecutable: aws,
            arguments: ["sso", "login", "--profile", envConfig.awsProfileName],
            environment: env
        )
        if result.exitCode == 0 {
            await refreshShellEnvironment()
            await refreshSsoStatus()
            if ssoAuthStatus == .valid {
                statusMessage = "SSO OK para profile \(envConfig.awsProfileName)."
                errorMessage = nil
            } else {
                statusMessage = nil
                errorMessage = """
                Login no navegador concluído, mas a AWS ainda não libera credenciais para este profile.
                Verifique sso_role_name em ~/.aws/config (permission set do portal) e use «Testar profile».
                """
            }
        } else {
            errorMessage = AwsCliErrorPresenter.friendlyMessage(
                raw: result.stderr.isEmpty ? "Falha no SSO." : result.stderr
            )
        }
    }

    public func testProfile() async {
        guard let envConfig = currentEnvironmentConfig else { return }
        isBusy = true
        defer { isBusy = false }
        let aws = resolvedAwsPath()
        let env = await awsEnvironment(for: envConfig)
        let result = await ShellCommandRunner.run(
            executable: aws,
            arguments: [
                "sts", "get-caller-identity",
                "--profile", envConfig.awsProfileName,
            ],
            environment: env
        )
        if result.exitCode == 0 {
            statusMessage = "Profile OK: \(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))"
            errorMessage = nil
            await refreshSsoStatus()
        } else {
            errorMessage = AwsCliErrorPresenter.friendlyMessage(
                raw: result.stderr.isEmpty ? "Profile inválido ou SSO expirado." : result.stderr
            )
        }
    }

    public func openTunnel(_ tunnel: TunnelDefinition) async {
        guard let envConfig = currentEnvironmentConfig else { return }
        guard tunnel.isAvailable else {
            errorMessage = "Túnel indisponível neste ambiente."
            return
        }
        let key = tunnel.tunnelKey(environment: selectedEnvironment)
        let state = listenState(for: tunnel)
        switch state {
        case .listeningOwned:
            statusMessage = "Túnel já aberto."
            return
        case .listeningExternal(let pids):
            errorMessage = """
            Porta local \(tunnel.localPort) em uso (PID \(pids.map(String.init).joined(separator: ", "))). Encerre o processo ou escolha outra porta local.
            """
            return
        case .portUsedByOtherTunnel(let ownerKey):
            errorMessage = """
            Porta local \(tunnel.localPort) reservada pelo túnel «\(ownerKey)». Use outra porta local ou encerre o outro túnel.
            """
            return
        case .closed:
            break
        }
        openingTunnelKeys.insert(key)
        defer { openingTunnelKeys.remove(key) }
        do {
            let aws = resolvedAwsPath()
            let env = try await credentialsEnvironment(for: envConfig)
            try await tunnelRunner.openTunnel(
                tunnelKey: key,
                awsExecutable: aws,
                profile: envConfig.awsProfileName,
                region: envConfig.region,
                targetInstanceId: envConfig.ssmTargetInstanceId,
                tunnel: tunnel,
                environment: env
            )
            await refreshListenStates()
            statusMessage = "\(tunnel.title) aberto em localhost:\(tunnel.localPort)"
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func closeTunnel(_ tunnel: TunnelDefinition) {
        let key = tunnel.tunnelKey(environment: selectedEnvironment)
        Task {
            await tunnelRunner.closeTunnel(tunnelKey: key, localPort: tunnel.localPort)
            await refreshListenStates()
        }
        statusMessage = "Encerrando \(tunnel.title)…"
    }

    public func generateToken(for tunnel: TunnelDefinition, force: Bool = false) async {
        guard let envConfig = currentEnvironmentConfig else { return }
        guard tunnel.driver == .mysql || tunnel.driver == .postgres else {
            errorMessage = "Este túnel não suporta token RDS."
            return
        }
        let listen = listenState(for: tunnel)
        switch listen {
        case .closed, .portUsedByOtherTunnel, .listeningExternal:
            errorMessage = "Abra o túnel antes de gerar token."
            return
        case .listeningOwned:
            break
        }
        isBusy = true
        defer { isBusy = false }
        do {
            try await RdsCaManager.ensureCertificate(at: envConfig.rdsCaPath)
            let aws = resolvedAwsPath()
            let env = try await credentialsEnvironment(for: envConfig)
            let token = try await RdsTokenGenerator.generateToken(
                awsExecutable: aws,
                profile: envConfig.awsProfileName,
                region: envConfig.region,
                hostname: tunnel.remoteHost,
                port: tunnel.remotePort,
                username: envConfig.rdsIamUsername,
                environment: env
            )
            let session = RdsTokenGenerator.makeSession(
                token: token,
                tunnel: tunnel,
                username: envConfig.rdsIamUsername,
                sslCertPath: envConfig.rdsCaPath
            )
            let key = tunnel.tunnelKey(environment: selectedEnvironment)
            tokenSessions[key] = session
            passwordTests[key] = RdsPasswordTestResult.none
            let escaped = DatabaseURLBuilder.encodeURIComponent(token)
            var syncNote = ""
            if let stage = selectedEnvironment.envStage, let tokenSync {
                syncNote = tokenSync(tunnel.flag, stage, escaped)
            }
            statusMessage = "Token gerado para \(tunnel.title).\(syncNote)"
            errorMessage = nil
        } catch {
            errorMessage = AwsCliErrorPresenter.friendlyMessage(
                raw: error.localizedDescription
            )
        }
    }

    public func testPassword(for tunnel: TunnelDefinition) async {
        guard let envConfig = currentEnvironmentConfig else { return }
        let key = tunnel.tunnelKey(environment: selectedEnvironment)
        guard let session = tokenSessions[key], !session.isExpired else {
            errorMessage = "Gere um token válido antes de testar."
            return
        }
        switch listenState(for: tunnel) {
        case .listeningOwned:
            break
        case .listeningExternal:
            errorMessage = "Túnel externo na porta — abra pelo app neste ambiente."
            return
        case .closed:
            errorMessage = "Túnel fechado."
            return
        case .portUsedByOtherTunnel:
            errorMessage = "Túnel fechado (porta usada por outro ambiente/túnel)."
            return
        }
        isBusy = true
        defer { isBusy = false }
        let result = await RdsConnectionTester.testConnection(
            tunnel: tunnel,
            username: envConfig.rdsIamUsername,
            token: session.rawToken
        )
        passwordTests[key] = result
        switch result {
        case .success:
            statusMessage = "Teste de senha OK."
            errorMessage = nil
        case .failure(let message, _):
            errorMessage = message
        case .none:
            break
        }
    }

    public func clearToken(for tunnel: TunnelDefinition) {
        let key = tunnel.tunnelKey(environment: selectedEnvironment)
        tokenSessions.removeValue(forKey: key)
        passwordTests.removeValue(forKey: key)
    }

    private func resolvedAwsPath() -> String {
        ShellCommandRunner.resolveAwsExecutable(customPath: config.awsCliPath)
    }

    private func awsEnvironment(for envConfig: AwsEnvironmentConfig) async -> [String: String] {
        let base = await resolvedShellEnvironment()
        return AwsCommandEnvironment.merge(
            base: base,
            profile: envConfig.awsProfileName,
            region: envConfig.region
        )
    }

    private func credentialsEnvironment(for envConfig: AwsEnvironmentConfig) async throws -> [String: String] {
        let base = await resolvedShellEnvironment()
        let aws = resolvedAwsPath()
        switch await AwsSessionCredentials.exportForProfile(
            awsExecutable: aws,
            profile: envConfig.awsProfileName,
            region: envConfig.region,
            baseEnvironment: base
        ) {
        case .success(let env):
            return env
        case .failure(let error):
            switch error {
            case .message(let text):
                throw CredentialsError.message(text)
            }
        }
    }

    public func refreshAfterEnvironmentChange() async {
        isRefreshingEnvironment = true
        listenStates = [:]
        ssoAuthStatus = .unknown
        await refreshSsoStatus()
        await refreshListenStates()
        isRefreshingEnvironment = false
    }

    public func externalPids(for tunnel: TunnelDefinition) -> [Int32] {
        let key = tunnel.tunnelKey(environment: selectedEnvironment)
        if case .listeningExternal(let pids) = listenStates[key] {
            return pids
        }
        return []
    }

    public func copyListeningPids(for tunnel: TunnelDefinition) {
        Task {
            let pids = await PortMonitor.listeningPids(localPort: tunnel.localPort)
            await MainActor.run {
                guard !pids.isEmpty else {
                    errorMessage =
                        "Nenhum processo em LISTEN na porta \(tunnel.localPort)."
                    return
                }
                let text = pids.map(String.init).joined(separator: ", ")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                statusMessage = "PID(s) copiado(s): \(text)"
                errorMessage = nil
            }
        }
    }

    public func copyExternalPids(for tunnel: TunnelDefinition) {
        copyListeningPids(for: tunnel)
    }

    private func refreshSsoStatus() async {
        guard let envConfig = currentEnvironmentConfig else {
            ssoAuthStatus = .unknown
            return
        }
        let aws = resolvedAwsPath()
        let base = await resolvedShellEnvironment()
        let status = await AwsSessionCredentials.verifyProfile(
            awsExecutable: aws,
            profile: envConfig.awsProfileName,
            region: envConfig.region,
            baseEnvironment: base
        )
        ssoAuthStatus = status
        if status == .valid {
            if errorMessage?.contains("GetRoleCredentials") == true
                || errorMessage?.contains("SSO sem acesso") == true
            {
                errorMessage = nil
            }
        }
    }

    private enum CredentialsError: LocalizedError {
        case message(String)
        var errorDescription: String? {
            switch self {
            case .message(let text): return text
            }
        }
    }

    private func refreshShellEnvironment() async {
        shellEnvironment = await ShellCommandRunner.loginShellEnvironment()
    }

    private func resolvedShellEnvironment() async -> [String: String] {
        if shellEnvironment.isEmpty {
            shellEnvironment = await ShellCommandRunner.loginShellEnvironment()
        }
        return shellEnvironment
    }

    private func startMonitoring() {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshListenStates()
                await self?.refreshSsoStatus()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    private func startCountdownTicker() {
        countdownTask?.cancel()
        countdownTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tickTokenExpiry()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func tickTokenExpiry() {
        objectWillChange.send()
    }

    private func refreshListenStates() async {
        guard let envConfig = currentEnvironmentConfig else { return }
        tunnelRunner.pruneDeadProcesses()
        tunnelRunner.pruneStaleOwnership(exemptTunnelKeys: openingTunnelKeys)
        let knownFingerprints = config.allTunnelFingerprints()
        var next: [String: TunnelListenState] = [:]
        for tunnel in envConfig.tunnels where tunnel.isAvailable {
            let key = tunnel.tunnelKey(environment: selectedEnvironment)
            let pids = await PortMonitor.listeningPids(localPort: tunnel.localPort)
            next[key] = tunnelRunner.resolveListenState(
                tunnelKey: key,
                localPort: tunnel.localPort,
                listeningPids: pids,
                knownFingerprints: knownFingerprints
            )
        }
        listenStates = next
    }
}
