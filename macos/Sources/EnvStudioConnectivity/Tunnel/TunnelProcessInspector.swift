import Foundation

public enum TunnelProcessInspector {
    public struct ParsedSSMParameters: Equatable, Sendable {
        public var host: String
        public var remotePort: Int
        public var localPort: Int
    }

    public static func parseSSMParameters(from commandLine: String) -> ParsedSSMParameters? {
        guard let host = capture(in: commandLine, key: "host") else { return nil }
        guard let remoteText = capture(in: commandLine, key: "portNumber"),
            let remotePort = Int(remoteText)
        else { return nil }
        guard let localText = capture(in: commandLine, key: "localPortNumber"),
            let localPort = Int(localText)
        else { return nil }
        return ParsedSSMParameters(host: host, remotePort: remotePort, localPort: localPort)
    }

    public static func matchOwnerKey(
        listeningPids: [Int32],
        localPort: Int,
        candidates: [TunnelOpenFingerprint]
    ) -> String? {
        for pid in listeningPids {
            for command in commandLinesInProcessTree(rootPid: pid) {
                guard let parsed = parseSSMParameters(from: command) else { continue }
                guard parsed.localPort == localPort else { continue }
                for candidate in candidates {
                    if candidate.matchesSSMParameters(
                        host: parsed.host,
                        remotePort: parsed.remotePort,
                        localPort: parsed.localPort
                    ) {
                        return candidate.tunnelKey
                    }
                }
            }
        }
        return nil
    }

    public static func commandLinesInProcessTree(rootPid: Int32, maxDepth: Int = 10) -> [String] {
        var lines: [String] = []
        var current = rootPid
        var visited = Set<Int32>()
        for _ in 0..<maxDepth {
            if visited.contains(current) { break }
            visited.insert(current)
            if let command = processCommandLine(pid: current), !command.isEmpty {
                lines.append(command)
            }
            guard let parent = parentPid(of: current), parent > 1 else { break }
            current = parent
        }
        return lines
    }

    private static func parentPid(of pid: Int32) -> Int32? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", String(pid), "-o", "ppid="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let value = Int32(text) else { return nil }
        return value
    }

    private static func capture(in text: String, key: String) -> String? {
        let marker = "\(key)="
        guard let range = text.range(of: marker) else { return nil }
        let rest = text[range.upperBound...]
        if let comma = rest.firstIndex(of: ",") {
            return String(rest[..<comma]).trimmingCharacters(in: .whitespaces)
        }
        return String(rest).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func processCommandLine(pid: Int32) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-ww", "-p", String(pid), "-o", "command="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }
}
