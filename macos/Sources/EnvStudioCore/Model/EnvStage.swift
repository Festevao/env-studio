import Foundation

public enum EnvStage: String, CaseIterable, Identifiable, Codable, Sendable {
    case local
    case dev
    case hom
    case prod

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .local: return "local"
        case .dev: return "dev"
        case .hom: return "hom"
        case .prod: return "prod"
        }
    }

    public static let ordered: [EnvStage] = [.local, .dev, .hom, .prod]

    public static func parseSectionHeader(_ line: String) -> EnvStage? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return nil }
        let body = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
        guard body.contains("-") else { return nil }
        let namePart = body.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            .first?
            .trimmingCharacters(in: .whitespaces)
            .lowercased() ?? ""
        return EnvStage(rawValue: namePart)
    }

    public var sectionHeaderLine: String {
        let dashes = String(repeating: "-", count: 56)
        return "# \(displayName) \(dashes)"
    }
}

public enum MasterEnvironmentSelection: Equatable, Sendable {
    case uniform(EnvStage)
    case mixed
}
