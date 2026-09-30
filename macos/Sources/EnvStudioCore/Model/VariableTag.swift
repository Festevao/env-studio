import Foundation

public enum VariableTag: String, CaseIterable, Identifiable, Codable, Sendable {
    case secret
    case sqlStringConn
    case sqlPassword
    case mongoStringConn
    case redisStringConn
    case amqpStringConn

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .secret: return "secret"
        case .sqlStringConn: return "sqlStringConn"
        case .sqlPassword: return "senha SQL"
        case .mongoStringConn: return "mongoStringConn"
        case .redisStringConn: return "redisStringConn"
        case .amqpStringConn: return "amqpStringConn"
        }
    }

    /// Uma variável aceita no máximo uma tag; `secret` tem prioridade sobre metadados legados.
    public static func normalizedSingle(from tags: Set<VariableTag>) -> Set<VariableTag> {
        guard !tags.isEmpty else { return [] }
        if tags.contains(.secret) { return [.secret] }
        if let chosen = allCases.first(where: { tags.contains($0) }) {
            return [chosen]
        }
        return []
    }
}
