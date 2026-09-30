import Foundation

public enum TunnelSessionPersistence {
    public static let fileName = "active-tunnel-sessions.json"

    public static func fileURL() -> URL {
        ConnectivityPersistence.applicationSupportDirectory()
            .appendingPathComponent(fileName)
    }

    public static func load() -> [TunnelOpenFingerprint] {
        let url = fileURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(ActiveTunnelSessionsFile.self, from: data)
            return decoded.sessions
        } catch {
            return []
        }
    }

    public static func save(_ sessions: [TunnelOpenFingerprint]) {
        let url = fileURL()
        if sessions.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        do {
            let payload = ActiveTunnelSessionsFile(sessions: sessions)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(payload)
            try data.write(to: url, options: .atomic)
        } catch {
            return
        }
    }

    public static func clear() {
        try? FileManager.default.removeItem(at: fileURL())
    }
}

public final class TunnelSessionRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var byKey: [String: TunnelOpenFingerprint] = [:]
    private var portToKey: [Int: String] = [:]

    public init(loadPersisted: Bool = true) {
        if loadPersisted {
            for fingerprint in TunnelSessionPersistence.load() {
                byKey[fingerprint.tunnelKey] = fingerprint
                portToKey[fingerprint.localPort] = fingerprint.tunnelKey
            }
        }
    }

    public func ownerKey(forLocalPort port: Int) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return portToKey[port]
    }

    public func fingerprint(for tunnelKey: String) -> TunnelOpenFingerprint? {
        lock.lock()
        defer { lock.unlock() }
        return byKey[tunnelKey]
    }

    public func allFingerprints() -> [TunnelOpenFingerprint] {
        lock.lock()
        defer { lock.unlock() }
        return Array(byKey.values)
    }

    public func isRegistered(tunnelKey: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return byKey[tunnelKey] != nil
    }

    public func register(_ fingerprint: TunnelOpenFingerprint) {
        lock.lock()
        byKey[fingerprint.tunnelKey] = fingerprint
        portToKey[fingerprint.localPort] = fingerprint.tunnelKey
        let all = Array(byKey.values)
        lock.unlock()
        TunnelSessionPersistence.save(all)
    }

    public func unregister(tunnelKey: String) {
        lock.lock()
        if let fp = byKey.removeValue(forKey: tunnelKey) {
            if portToKey[fp.localPort] == tunnelKey {
                portToKey.removeValue(forKey: fp.localPort)
            }
        }
        let all = Array(byKey.values)
        lock.unlock()
        TunnelSessionPersistence.save(all)
    }

    public func clearAll() {
        lock.lock()
        byKey.removeAll()
        portToKey.removeAll()
        lock.unlock()
        TunnelSessionPersistence.clear()
    }

    public func pruneStaleOwnership(exemptTunnelKeys: Set<String> = []) {
        lock.lock()
        let entries = portToKey
        lock.unlock()
        for (port, key) in entries {
            if exemptTunnelKeys.contains(key) {
                continue
            }
            let pids = PortMonitor.listeningPidsBlocking(localPort: port)
            if pids.isEmpty {
                unregister(tunnelKey: key)
            }
        }
    }

    public func resolveListenState(
        tunnelKey: String,
        localPort: Int,
        listeningPids: [Int32],
        knownFingerprints: [TunnelOpenFingerprint],
        activeLauncherKeys: Set<String> = []
    ) -> TunnelListenState {
        if listeningPids.isEmpty {
            return .closed
        }
        lock.lock()
        let owner = portToKey[localPort]
        let registeredForKey = byKey[tunnelKey] != nil
        lock.unlock()
        if owner == tunnelKey || registeredForKey {
            return .listeningOwned
        }
        if activeLauncherKeys.contains(tunnelKey) {
            return .listeningOwned
        }
        if let owner, owner != tunnelKey {
            return .portUsedByOtherTunnel(ownerKey: owner)
        }
        if let matchedOwner = TunnelProcessInspector.matchOwnerKey(
            listeningPids: listeningPids,
            localPort: localPort,
            candidates: knownFingerprints
        ) {
            if matchedOwner == tunnelKey {
                if let fingerprint = knownFingerprints.first(where: { $0.tunnelKey == tunnelKey }) {
                    register(fingerprint)
                }
                return .listeningOwned
            }
            return .portUsedByOtherTunnel(ownerKey: matchedOwner)
        }
        return .listeningExternal(pids: listeningPids)
    }
}
