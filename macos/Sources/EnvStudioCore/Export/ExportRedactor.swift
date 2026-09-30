import Foundation

public struct ExportOptions: Sendable {
    public var omitSecretLines: Bool

    public init(omitSecretLines: Bool = false) {
        self.omitSecretLines = omitSecretLines
    }
}

public enum ExportRedactor {
    public static func exportFlat(
        document: EnvDocument,
        options: ExportOptions = ExportOptions()
    ) -> String {
        var lines: [String] = []
        let keys = document.keyOrder.isEmpty
            ? document.variables.map(\.key)
            : document.keyOrder

        for key in keys {
            guard let variable = document.variable(forKey: key) else { continue }
            let raw = variable.values[variable.activeEnvironment] ?? ""
            let tags = VariableTag.normalizedSingle(from: variable.tags)

            if tags.contains(.secret) {
                if options.omitSecretLines { continue }
                lines.append("\(key)=")
                continue
            }

            let redacted = redact(value: raw, tags: tags)
            lines.append("\(key)=\(redacted)")
        }

        return lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
    }

    public static func redact(value: String, tags: Set<VariableTag>) -> String {
        let tags = VariableTag.normalizedSingle(from: tags)
        if tags.contains(.secret) { return "" }

        var result = value
        if tags.contains(.sqlStringConn) {
            result = redactConnectionValue(
                result,
                schemes: ["mysql", "postgresql", "postgres"]
            )
        } else if tags.contains(.mongoStringConn) {
            result = redactConnectionValue(
                result,
                schemes: ["mongodb", "mongodb+srv"]
            )
        } else if tags.contains(.redisStringConn) {
            result = redactConnectionValue(result, schemes: ["redis", "rediss"])
        } else if tags.contains(.amqpStringConn) {
            result = redactConnectionValue(result, schemes: ["amqp", "amqps"])
        }
        return result
    }

    private static func redactConnectionValue(
        _ value: String,
        schemes: [String]
    ) -> String {
        let schemeRedacted = redactURLUserPassword(value, schemes: schemes)
        if schemeRedacted != value {
            return schemeRedacted
        }
        return redactGenericURLCredentials(value)
    }

    static func redactGenericURLCredentials(_ value: String) -> String {
        guard let schemeEnd = value.range(of: "://") else { return value }
        let rest = value[schemeEnd.upperBound...]
        guard let atIndex = rest.firstIndex(of: "@") else { return value }
        let prefix = value[..<schemeEnd.upperBound]
        let afterAt = rest[rest.index(after: atIndex)...]
        return "\(prefix)<user>:<password>@\(afterAt)"
    }

    static func redactURLUserPassword(_ value: String, schemes: [String]) -> String {
        for scheme in schemes {
            let prefix = "\(scheme)://"
            guard value.lowercased().hasPrefix(prefix.lowercased()) else { continue }

            if let url = URL(string: value), let host = url.host {
                let schemePart = url.scheme ?? scheme
                var path = url.path
                if path.isEmpty { path = "" }
                let query = url.query.map { "?\($0)" } ?? ""
                let fragment = url.fragment.map { "#\($0)" } ?? ""
                let portPart = url.port.map { ":\($0)" } ?? ""
                if url.user != nil || url.password != nil {
                    return
                        "\(schemePart)://<user>:<password>@\(host)\(portPart)\(path)\(query)\(fragment)"
                }
                return value
            }

            return regexRedactAuthority(value: value, schemePrefix: prefix)
        }
        return value
    }

    private static func regexRedactAuthority(value: String, schemePrefix: String) -> String {
        guard value.count >= schemePrefix.count else { return value }
        let rest = String(value.dropFirst(schemePrefix.count))
        guard let atIndex = rest.firstIndex(of: "@") else { return value }
        let afterAt = rest[rest.index(after: atIndex)...]
        return "\(schemePrefix)<user>:<password>@\(afterAt)"
    }
}
