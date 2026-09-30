import Foundation

public enum EnvSectionParser {
    public struct ParseWarning: Equatable, Sendable {
        public var message: String
    }

    public struct ParseResult: Sendable {
        public var document: EnvDocument
        public var warnings: [ParseWarning]
    }

    public static func parse(_ text: String) -> ParseResult {
        var warnings: [ParseWarning] = []
        var currentSection: EnvStage?
        var valuesByKey: [String: [EnvStage: String]] = [:]
        var activeByKey: [String: EnvStage] = [:]
        var keyOrder: [String] = []

        func registerKey(_ key: String) {
            if !keyOrder.contains(key) {
                keyOrder.append(key)
            }
        }

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)

        for lineSub in lines {
            let line = String(lineSub)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                continue
            }

            if let section = EnvStage.parseSectionHeader(trimmed) {
                currentSection = section
                continue
            }

            guard let assignment = parseAssignmentLine(trimmed) else {
                continue
            }

            let key = assignment.key
            let value = assignment.value
            let isCommented = assignment.isCommented

            registerKey(key)

            if let section = currentSection {
                if valuesByKey[key] == nil {
                    valuesByKey[key] = [:]
                }
                valuesByKey[key]?[section] = value

                if !isCommented {
                    if let previous = activeByKey[key], previous != section {
                        warnings.append(
                            ParseWarning(
                                message:
                                    "Múltiplas linhas ativas para '\(key)'; usando '\(section)'."
                            )
                        )
                    }
                    activeByKey[key] = section
                }
            } else if !isCommented {
                if valuesByKey[key] == nil {
                    valuesByKey[key] = [:]
                }
                valuesByKey[key]?[.local] = value
                activeByKey[key] = .local
            }
        }

        for key in keyOrder {
            if activeByKey[key] == nil {
                if let firstEnv = EnvStage.ordered.first(where: {
                    valuesByKey[key]?[$0] != nil
                }) {
                    activeByKey[key] = firstEnv
                } else {
                    activeByKey[key] = .local
                }
            }
        }

        let variables: [EnvVariable] = keyOrder.map { key in
            EnvVariable(
                key: key,
                values: valuesByKey[key] ?? [:],
                activeEnvironment: activeByKey[key] ?? .local,
                tags: []
            )
        }

        return ParseResult(
            document: EnvDocument(variables: variables, keyOrder: keyOrder),
            warnings: warnings
        )
    }

    private struct AssignmentLine {
        var isCommented: Bool
        var key: String
        var value: String
    }

    private static func parseAssignmentLine(_ trimmed: String) -> AssignmentLine? {
        var body = trimmed
        var isCommented = false

        if body.hasPrefix("#") {
            let afterHash = String(body.dropFirst())
            if isValidKeyPrefix(afterHash), afterHash.contains("=") {
                isCommented = true
                body = afterHash
            } else {
                return nil
            }
        }

        guard let equalIndex = body.firstIndex(of: "=") else { return nil }
        let key = String(body[..<equalIndex]).trimmingCharacters(in: .whitespaces)
        let value = String(body[body.index(after: equalIndex)...])
        guard isValidKey(key) else { return nil }

        return AssignmentLine(isCommented: isCommented, key: key, value: value)
    }

    private static func isValidKeyPrefix(_ text: String) -> Bool {
        guard let first = text.first else { return false }
        return first.isLetter || first == "_"
    }

    private static func isValidKey(_ key: String) -> Bool {
        guard let first = key.first else { return false }
        guard first.isLetter || first == "_" else { return false }
        for character in key.dropFirst() {
            if character.isLetter || character.isNumber || character == "_" {
                continue
            }
            return false
        }
        return true
    }

    /// Importa `.env` flat (KEY=val por linha) para um ambiente alvo.
    public static func parseFlat(
        _ text: String,
        targetEnvironment: EnvStage
    ) -> EnvDocument {
        var keyOrder: [String] = []
        var map: [String: String] = [:]

        for lineSub in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = String(lineSub).trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("#") && !trimmed.dropFirst().contains("=") {
                continue
            }
            guard let assignment = parseAssignmentLine(trimmed), !assignment.isCommented
            else { continue }
            let key = assignment.key
            if !keyOrder.contains(key) { keyOrder.append(key) }
            map[key] = assignment.value
        }

        let variables = keyOrder.map { key in
            EnvVariable(
                key: key,
                values: [targetEnvironment: map[key] ?? ""],
                activeEnvironment: targetEnvironment,
                tags: []
            )
        }

        return EnvDocument(variables: variables, keyOrder: keyOrder)
    }
}
