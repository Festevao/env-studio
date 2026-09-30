import Foundation

public enum TunnelCatalogError: LocalizedError, Equatable {
    case invalidFlag
    case duplicateFlag(String)
    case invalidPorts
    case emptyTitle
    case tunnelNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .invalidFlag:
            return "Identificador (flag) inválido — use letras minúsculas, números e hífens."
        case .duplicateFlag(let flag):
            return "Já existe um túnel com o identificador «\(flag)»."
        case .invalidPorts:
            return "Portas locais e remotas devem estar entre 1 e 65535."
        case .emptyTitle:
            return "Informe um título para o túnel."
        case .tunnelNotFound(let flag):
            return "Túnel «\(flag)» não encontrado."
        }
    }
}

public enum TunnelFlagValidator {
    private static let pattern = try? NSRegularExpression(
        pattern: "^[a-z0-9]([a-z0-9-]*[a-z0-9])?$"
    )

    public static func normalize(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let pattern, pattern.firstMatch(in: trimmed, range: range) != nil else {
            return nil
        }
        return trimmed
    }
}

public extension ConnectivityConfig {
    func containsTunnel(flag: String) -> Bool {
        TunnelEnvironment.allCases.contains { environment in
            tunnel(flag: flag, environment: environment) != nil
        }
    }

    func tunnel(flag: String, environment: TunnelEnvironment) -> TunnelDefinition? {
        config(for: environment)?.tunnels.first { $0.flag == flag }
    }

    mutating func addTunnelAcrossEnvironments(_ definition: TunnelDefinition) throws {
        guard !definition.title.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw TunnelCatalogError.emptyTitle
        }
        guard let normalizedFlag = TunnelFlagValidator.normalize(definition.flag) else {
            throw TunnelCatalogError.invalidFlag
        }
        guard Self.portsAreValid(definition) else {
            throw TunnelCatalogError.invalidPorts
        }
        if containsTunnel(flag: normalizedFlag) {
            throw TunnelCatalogError.duplicateFlag(normalizedFlag)
        }
        var draft = definition
        draft.flag = normalizedFlag
        for environment in TunnelEnvironment.allCases {
            var envConfig =
                config(for: environment)
                ?? ConnectivityDefaults.restoreEnvironment(environment)
            envConfig.tunnels.append(draft)
            setConfig(envConfig, for: environment)
        }
    }

    mutating func removeTunnelAcrossEnvironments(flag: String) throws {
        guard containsTunnel(flag: flag) else {
            throw TunnelCatalogError.tunnelNotFound(flag)
        }
        for environment in TunnelEnvironment.allCases {
            guard var envConfig = config(for: environment) else { continue }
            envConfig.tunnels.removeAll { $0.flag == flag }
            setConfig(envConfig, for: environment)
        }
    }

    private static func portsAreValid(_ tunnel: TunnelDefinition) -> Bool {
        (1...65_535).contains(tunnel.localPort) && (1...65_535).contains(tunnel.remotePort)
    }
}
