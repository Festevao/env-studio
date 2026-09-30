import Foundation

public enum EnvSectionWriter {
    public static func render(_ document: EnvDocument) -> String {
        var lines: [String] = []
        let keys = orderedKeys(from: document)

        for (index, environment) in EnvStage.ordered.enumerated() {
            if index > 0 {
                lines.append("")
            }
            lines.append(environment.sectionHeaderLine)
            lines.append("")

            if keys.isEmpty {
                continue
            }

            for key in keys {
                guard let variable = document.variable(forKey: key) else { continue }
                let value = variable.values[environment] ?? ""
                let line = "\(key)=\(value)"
                if variable.activeEnvironment == environment {
                    lines.append(line)
                } else {
                    lines.append("#\(line)")
                }
            }
        }

        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func orderedKeys(from document: EnvDocument) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for key in document.keyOrder where !seen.contains(key) {
            seen.insert(key)
            result.append(key)
        }
        for variable in document.variables where !seen.contains(variable.key) {
            seen.insert(variable.key)
            result.append(variable.key)
        }
        return result
    }
}
