import Foundation

public enum ConnectivityPersistence {
    public static let fileName = "connectivity.json"

    public static func applicationSupportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory())
        let dir = base.appendingPathComponent("EnvStudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// `~/Library/Application Support/EnvStudio/connectivity.json`
    public static var storageLocationHint: String {
        fileURL().path
    }

    public static func fileURL() -> URL {
        applicationSupportDirectory().appendingPathComponent(fileName)
    }

    public static func load() -> ConnectivityConfig {
        let url = fileURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            let seeded = ConnectivityDefaults.seededConfig()
            try? save(seeded)
            return seeded
        }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(ConnectivityConfig.self, from: data)
            return decoded
        } catch {
            return ConnectivityDefaults.seededConfig()
        }
    }

    public static func save(_ config: ConnectivityConfig) throws {
        let url = fileURL()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: url, options: .atomic)
    }
}
