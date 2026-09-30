import Foundation

public final class TunnelRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var processes: [String: Process] = [:]
    private let sessionRegistry: TunnelSessionRegistry

    public init(sessionRegistry: TunnelSessionRegistry = TunnelSessionRegistry()) {
        self.sessionRegistry = sessionRegistry
    }

    public func ownerKey(forLocalPort port: Int) -> String? {
        sessionRegistry.ownerKey(forLocalPort: port)
    }

    public func isAppOwned(tunnelKey: String) -> Bool {
        sessionRegistry.isRegistered(tunnelKey: tunnelKey)
    }

    public func ownedProcessId(for tunnelKey: String) -> Int32? {
        lock.lock()
        defer { lock.unlock() }
        return processes[tunnelKey]?.processIdentifier
    }

    public func isActiveTunnel(tunnelKey: String, localPort: Int) async -> Bool {
        guard sessionRegistry.isRegistered(tunnelKey: tunnelKey) else { return false }
        return await PortMonitor.isPortListening(localPort: localPort)
    }

    public func pruneDeadProcesses() {
        lock.lock()
        defer { lock.unlock() }
        for (key, process) in processes where !process.isRunning {
            processes.removeValue(forKey: key)
        }
    }

    public func resolveListenState(
        tunnelKey: String,
        localPort: Int,
        listeningPids: [Int32],
        knownFingerprints: [TunnelOpenFingerprint]
    ) -> TunnelListenState {
        sessionRegistry.resolveListenState(
            tunnelKey: tunnelKey,
            localPort: localPort,
            listeningPids: listeningPids,
            knownFingerprints: knownFingerprints,
            activeLauncherKeys: activeLauncherTunnelKeys()
        )
    }

    public func pruneStaleOwnership(exemptTunnelKeys: Set<String> = []) {
        var exempt = exemptTunnelKeys
        exempt.formUnion(activeLauncherTunnelKeys())
        sessionRegistry.pruneStaleOwnership(exemptTunnelKeys: exempt)
    }

    private func activeLauncherTunnelKeys() -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return Set(processes.filter { $0.value.isRunning }.map(\.key))
    }

    private func trackLauncherProcess(_ process: Process, tunnelKey: String) {
        lock.lock()
        processes[tunnelKey] = process
        lock.unlock()
    }

    public func revokeOwnership(tunnelKey: String, localPort: Int) {
        sessionRegistry.unregister(tunnelKey: tunnelKey)
        lock.lock()
        processes.removeValue(forKey: tunnelKey)
        lock.unlock()
        _ = localPort
    }

    public func openTunnel(
        tunnelKey: String,
        awsExecutable: String,
        profile: String,
        region: String,
        targetInstanceId: String,
        tunnel: TunnelDefinition,
        environment: [String: String]
    ) async throws {
        pruneDeadProcesses()
        pruneStaleOwnership()

        if await isActiveTunnel(tunnelKey: tunnelKey, localPort: tunnel.localPort) {
            throw TunnelRunnerError.tunnelAlreadyOpen(tunnelKey)
        }

        if sessionRegistry.isRegistered(tunnelKey: tunnelKey),
            !(await PortMonitor.isPortListening(localPort: tunnel.localPort))
        {
            revokeOwnership(tunnelKey: tunnelKey, localPort: tunnel.localPort)
        }

        if await PortMonitor.isPortListening(localPort: tunnel.localPort) {
            if let owner = ownerKey(forLocalPort: tunnel.localPort) {
                if owner == tunnelKey {
                    throw TunnelRunnerError.tunnelAlreadyOpen(tunnelKey)
                }
                throw TunnelRunnerError.portUsedByOtherTunnel(owner)
            }
            throw TunnelRunnerError.portAlreadyInUse(tunnel.localPort)
        }

        let arguments = [
            "ssm", "start-session",
            "--profile", profile,
            "--region", region,
            "--target", targetInstanceId,
            "--document-name", "AWS-StartPortForwardingSessionToRemoteHost",
            "--parameters",
            "host=\(tunnel.remoteHost),portNumber=\(tunnel.remotePort),localPortNumber=\(tunnel.localPort)",
        ]
        let shellCommand = AwsCommandEnvironment.loginShellCommand(
            awsExecutable: awsExecutable,
            arguments: arguments
        )

        let process = Process()
        if environment["AWS_ACCESS_KEY_ID"] != nil {
            process.executableURL = URL(fileURLWithPath: awsExecutable)
            process.arguments = arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-l", "-c", shellCommand]
        }
        let env = AwsCommandEnvironment.merge(
            base: environment,
            profile: profile,
            region: region
        )
        process.environment = env

        let errPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError = errPipe

        try process.run()
        trackLauncherProcess(process, tunnelKey: tunnelKey)

        let fingerprint = TunnelOpenFingerprint.make(
            tunnelKey: tunnelKey,
            tunnel: tunnel,
            awsProfileName: profile,
            region: region,
            ssmTargetInstanceId: targetInstanceId
        )

        try await Task.sleep(nanoseconds: 2_000_000_000)
        let listening = await PortMonitor.isPortListening(localPort: tunnel.localPort)
        if !listening {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errText = String(data: errData, encoding: .utf8) ?? ""
            await closeTunnel(tunnelKey: tunnelKey, localPort: tunnel.localPort)
            throw TunnelRunnerError.startFailed(
                AwsCliErrorPresenter.friendlyMessage(raw: errText.isEmpty ? "Porta não abriu." : errText)
            )
        }
        sessionRegistry.register(fingerprint)
    }

    public func closeTunnel(tunnelKey: String, localPort: Int) async {
        lock.lock()
        let process = processes.removeValue(forKey: tunnelKey)
        lock.unlock()
        sessionRegistry.unregister(tunnelKey: tunnelKey)
        process?.terminate()
        let pids = await PortMonitor.listeningPids(localPort: localPort)
        for pid in pids where pid != ProcessInfo.processInfo.processIdentifier {
            kill(pid, SIGTERM)
        }
    }

    public func closeAll() async {
        let snapshot = drainOwnedSessions()
        for process in snapshot.processes {
            process.terminate()
        }
        for port in snapshot.localPorts {
            await terminateListeners(onLocalPort: port)
        }
        sessionRegistry.clearAll()
    }

    public func closeAllSynchronously() {
        let snapshot = drainOwnedSessions()
        for process in snapshot.processes {
            process.terminate()
        }
        for port in snapshot.localPorts {
            terminateListenersBlocking(onLocalPort: port)
        }
        sessionRegistry.clearAll()
    }

    private struct OwnedSessionSnapshot {
        var processes: [Process]
        var localPorts: [Int]
    }

    private func drainOwnedSessions() -> OwnedSessionSnapshot {
        lock.lock()
        let fingerprints = sessionRegistry.allFingerprints()
        let ports = Array(Set(fingerprints.map(\.localPort)))
        let all = Array(processes.values)
        processes.removeAll()
        lock.unlock()
        return OwnedSessionSnapshot(processes: all, localPorts: ports)
    }

    private func terminateListeners(onLocalPort port: Int) async {
        let pids = await PortMonitor.listeningPids(localPort: port)
        terminatePids(pids)
    }

    private func terminateListenersBlocking(onLocalPort port: Int) {
        let pids = PortMonitor.listeningPidsBlocking(localPort: port)
        terminatePids(pids)
    }

    private func terminatePids(_ pids: [Int32]) {
        let selfPid = ProcessInfo.processInfo.processIdentifier
        for pid in pids where pid != selfPid {
            kill(pid, SIGTERM)
        }
    }
}

public enum TunnelRunnerError: LocalizedError {
    case portAlreadyInUse(Int)
    case portUsedByOtherTunnel(String)
    case tunnelAlreadyOpen(String)
    case startFailed(String)

    public var errorDescription: String? {
        switch self {
        case .portAlreadyInUse(let port):
            return "Porta local \(port) já está em uso (outro processo). Use «Copiar PID» se for externo."
        case .portUsedByOtherTunnel(let owner):
            return """
            Porta local já usada pelo túnel «\(owner)». Só um listener por porta — escolha outra porta local ou encerre o outro túnel.
            """
        case .tunnelAlreadyOpen(let key):
            return "O túnel «\(key)» já está aberto neste ambiente."
        case .startFailed(let detail):
            return detail
        }
    }
}
