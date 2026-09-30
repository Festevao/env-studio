import Foundation

public enum AwsConfigReader {
    public static func listProfileNames(configPath: URL? = nil) -> [String] {
        let url = configPath ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".aws/config")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        var profiles: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "[default]" {
                profiles.append("default")
                continue
            }
            if trimmed.hasPrefix("[profile ") && trimmed.hasSuffix("]") {
                let name = trimmed.dropFirst(9).dropLast()
                profiles.append(String(name))
            }
        }
        return profiles.sorted()
    }
}
