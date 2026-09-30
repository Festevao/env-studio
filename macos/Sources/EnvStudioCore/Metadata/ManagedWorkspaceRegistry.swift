import Foundation

public struct ManagedWorkspaceFile: Codable, Equatable, Sendable {
    public var folders: [String]

    public init(folders: [String] = []) {
        self.folders = folders
    }
}

public enum ManagedWorkspaceRegistry {
    public static let fileName = "managed-workspaces.json"

    public static func fileURL() -> URL {
        EnvStudioAppPaths.applicationSupportDirectory()
            .appendingPathComponent(fileName)
    }

    public static func load() -> [URL] {
        let url = fileURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(ManagedWorkspaceFile.self, from: data)
            var seen = Set<String>()
            var urls: [URL] = []
            for path in decoded.folders {
                let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
                if seen.insert(standardized).inserted {
                    urls.append(URL(fileURLWithPath: standardized))
                }
            }
            return urls
        } catch {
            return []
        }
    }

    public static func register(folder: URL) {
        let path = folder.standardizedFileURL.resolvingSymlinksInPath().path
        var folders = load().map(\.path)
        if folders.contains(path) { return }
        folders.append(path)
        save(folders)
    }

    public static func remove(folder: URL) {
        let path = folder.standardizedFileURL.resolvingSymlinksInPath().path
        let folders = load().map(\.path).filter { $0 != path }
        save(folders)
    }

    private static func save(_ folders: [String]) {
        let payload = ManagedWorkspaceFile(folders: folders)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload) else { return }
        try? data.write(to: fileURL(), options: .atomic)
    }
}

public struct TunnelWorkspaceSyncResult: Equatable, Sendable {
    public var filesUpdated: Int
    public var variablesUpdated: Int
    public var skipped: Int

    public init(filesUpdated: Int = 0, variablesUpdated: Int = 0, skipped: Int = 0) {
        self.filesUpdated = filesUpdated
        self.variablesUpdated = variablesUpdated
        self.skipped = skipped
    }
}

public enum TunnelLinkedEnvSync {
    public static func apply(
        folders: [URL],
        envFileName: String = ".env",
        tunnelFlag: String,
        stage: EnvStage,
        escapedPassword: String,
        excluding folderToSkip: URL? = nil
    ) -> TunnelWorkspaceSyncResult {
        let skip = folderToSkip?.standardizedFileURL.resolvingSymlinksInPath().path
        var filesUpdated = 0
        var variablesUpdated = 0
        var skipped = 0
        for folder in folders {
            let path = folder.standardizedFileURL.resolvingSymlinksInPath().path
            if path == skip { continue }
            let outcome = applyToFolder(
                URL(fileURLWithPath: path, isDirectory: true),
                envFileName: envFileName,
                tunnelFlag: tunnelFlag,
                stage: stage,
                escapedPassword: escapedPassword
            )
            variablesUpdated += outcome.variablesUpdated
            skipped += outcome.skipped
            if outcome.variablesUpdated > 0 {
                filesUpdated += 1
            }
        }
        return TunnelWorkspaceSyncResult(
            filesUpdated: filesUpdated,
            variablesUpdated: variablesUpdated,
            skipped: skipped
        )
    }

    private static func applyToFolder(
        _ folder: URL,
        envFileName: String,
        tunnelFlag: String,
        stage: EnvStage,
        escapedPassword: String
    ) -> TunnelTokenApplyCounts {
        let envURL = folder.appendingPathComponent(envFileName)
        guard FileManager.default.fileExists(atPath: envURL.path) else {
            return TunnelTokenApplyCounts()
        }
        guard let text = try? String(contentsOf: envURL, encoding: .utf8) else {
            return TunnelTokenApplyCounts()
        }
        let parsed = EnvSectionParser.parse(text)
        var document = parsed.document
        let metadata = StudioMetadataStore.load(from: folder)
        StudioMetadataStore.applyTags(to: &document, metadata: metadata)
        let counts = TunnelLinkedValueUpdater.apply(
            document: &document,
            tunnelFlag: tunnelFlag,
            stage: stage,
            escapedPassword: escapedPassword
        )
        guard counts.variablesUpdated > 0 else { return counts }
        let rendered = EnvSectionWriter.render(document)
        do {
            try rendered.write(to: envURL, atomically: true, encoding: .utf8)
        } catch {
            return TunnelTokenApplyCounts(variablesUpdated: 0, skipped: counts.skipped)
        }
        return counts
    }
}
