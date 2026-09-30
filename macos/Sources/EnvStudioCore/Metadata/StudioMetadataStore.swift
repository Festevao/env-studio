import CryptoKit
import Foundation

public struct StudioMetadata: Codable, Equatable, Sendable {
    public var variables: [String: [String]]
    public var tunnelFlags: [String: String]

    public init(
        variables: [String: [String]] = [:],
        tunnelFlags: [String: String] = [:]
    ) {
        self.variables = variables
        self.tunnelFlags = tunnelFlags
    }

    private enum CodingKeys: String, CodingKey {
        case variables
        case tunnelFlags
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        variables = try container.decodeIfPresent([String: [String]].self, forKey: .variables) ?? [:]
        tunnelFlags = try container.decodeIfPresent([String: String].self, forKey: .tunnelFlags) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(variables, forKey: .variables)
        try container.encode(tunnelFlags, forKey: .tunnelFlags)
    }
}

public enum StudioMetadataStore {
    /// Nome legado — só leitura/migração; o app não grava mais na pasta do projeto.
    public static let legacyFileName = ".env.studio.json"

    public static func legacyFileURL(in folder: URL) -> URL {
        folder.appendingPathComponent(legacyFileName)
    }

    public static func storageFileURL(for workspaceFolder: URL) -> URL {
        let key = workspaceStorageKey(for: workspaceFolder)
        return EnvStudioAppPaths.workspaceMetadataDirectory()
            .appendingPathComponent("\(key).json")
    }

    public static func workspaceStorageKey(for folder: URL) -> String {
        let path = folder.standardizedFileURL.resolvingSymlinksInPath().path
        let digest = SHA256.hash(data: Data(path.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func load(from folder: URL) -> StudioMetadata {
        let appURL = storageFileURL(for: folder)
        if FileManager.default.fileExists(atPath: appURL.path) {
            return decode(from: appURL)
        }
        let legacyURL = legacyFileURL(in: folder)
        if FileManager.default.fileExists(atPath: legacyURL.path) {
            let migrated = decode(from: legacyURL)
            try? save(migrated, to: folder)
            return migrated
        }
        return StudioMetadata()
    }

    public static func save(_ metadata: StudioMetadata, to folder: URL) throws {
        let url = storageFileURL(for: folder)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(metadata)
        try data.write(to: url, options: .atomic)
    }

    private static func decode(from url: URL) -> StudioMetadata {
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(StudioMetadata.self, from: data)
        } catch {
            return StudioMetadata()
        }
    }

    public static func tags(from metadata: StudioMetadata, key: String) -> Set<VariableTag> {
        guard let raw = metadata.variables[key] else { return [] }
        let parsed = Set(raw.compactMap { VariableTag(rawValue: $0) })
        return VariableTag.normalizedSingle(from: parsed)
    }

    public static func applyTags(
        to document: inout EnvDocument,
        metadata: StudioMetadata
    ) {
        for index in document.variables.indices {
            let key = document.variables[index].key
            document.variables[index].tags = tags(from: metadata, key: key)
            let flag = metadata.tunnelFlags[key]?.trimmingCharacters(in: .whitespacesAndNewlines)
            document.variables[index].tunnelFlag = (flag?.isEmpty == false) ? flag : nil
        }
    }

    public static func metadata(from document: EnvDocument) -> StudioMetadata {
        var map: [String: [String]] = [:]
        var flags: [String: String] = [:]
        for variable in document.variables {
            let tags = VariableTag.normalizedSingle(from: variable.tags)
            if let tag = tags.first {
                map[variable.key] = [tag.rawValue]
            }
            if let flag = variable.tunnelFlag?.trimmingCharacters(in: .whitespacesAndNewlines),
                !flag.isEmpty
            {
                flags[variable.key] = flag
            }
        }
        return StudioMetadata(variables: map, tunnelFlags: flags)
    }
}
