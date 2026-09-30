import Foundation

public enum ConnectionStringPassword {
    /// Troca só `user:senha@` pela senha já escapada. Devolve nil se não houver userinfo com senha.
    public static func replacingPassword(in url: String, escapedPassword: String) -> String? {
        guard let schemeEnd = url.range(of: "://") else { return nil }
        let afterScheme = url[schemeEnd.upperBound...]
        guard let atIndex = afterScheme.firstIndex(of: "@") else { return nil }
        let userinfo = afterScheme[..<atIndex]
        guard let colon = userinfo.firstIndex(of: ":") else { return nil }
        let user = userinfo[..<colon]
        let suffix = afterScheme[afterScheme.index(after: atIndex)...]
        return "\(url[..<schemeEnd.upperBound])\(user):\(escapedPassword)@\(suffix)"
    }
}

public struct TunnelTokenApplyCounts: Equatable, Sendable {
    public var variablesUpdated: Int
    public var skipped: Int

    public init(variablesUpdated: Int = 0, skipped: Int = 0) {
        self.variablesUpdated = variablesUpdated
        self.skipped = skipped
    }
}

public enum TunnelLinkedValueUpdater {
    public static func apply(
        document: inout EnvDocument,
        tunnelFlag: String,
        stage: EnvStage,
        escapedPassword: String
    ) -> TunnelTokenApplyCounts {
        var updated = 0
        var skipped = 0
        for index in document.variables.indices {
            guard document.variables[index].tunnelFlag == tunnelFlag else { continue }
            let tags = VariableTag.normalizedSingle(from: document.variables[index].tags)
            if tags.contains(.sqlPassword) {
                document.variables[index].values[stage] = escapedPassword
                updated += 1
                continue
            }
            if tags.contains(.sqlStringConn) {
                let current = document.variables[index].values[stage] ?? ""
                guard let next = ConnectionStringPassword.replacingPassword(
                    in: current,
                    escapedPassword: escapedPassword
                ) else {
                    skipped += 1
                    continue
                }
                document.variables[index].values[stage] = next
                updated += 1
            }
        }
        return TunnelTokenApplyCounts(variablesUpdated: updated, skipped: skipped)
    }
}
