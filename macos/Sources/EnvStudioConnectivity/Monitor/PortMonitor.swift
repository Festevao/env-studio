import Foundation

public enum PortMonitor {
    public static func parseListeningPids(lsofOutput: String, localPort: Int) -> [Int32] {
        let portSuffix = ":\(localPort)"
        var pids: [Int32] = []
        for line in lsofOutput.split(separator: "\n").dropFirst() {
            let cols = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard cols.count >= 9 else { continue }
            let name = cols[8]
            guard name == portSuffix || name.hasSuffix(portSuffix) else { continue }
            if let pid = Int32(cols[1]) {
                pids.append(pid)
            }
        }
        return Array(Set(pids))
    }

    public static func isPortListening(localPort: Int) async -> Bool {
        let pids = await listeningPids(localPort: localPort)
        return !pids.isEmpty
    }

    public static func listeningPids(localPort: Int) async -> [Int32] {
        let result = await ShellCommandRunner.run(
            executable: "/usr/sbin/lsof",
            arguments: ["-nP", "-iTCP:\(localPort)", "-sTCP:LISTEN"]
        )
        guard result.exitCode == 0 else { return [] }
        return parseListeningPids(lsofOutput: result.stdout, localPort: localPort)
    }

    /// Para encerramento do app (`applicationWillTerminate` / `deinit`) — não depende de async.
    public static func listeningPidsBlocking(localPort: Int) -> [Int32] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-iTCP:\(localPort)", "-sTCP:LISTEN"]
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else { return [] }
        return parseListeningPids(lsofOutput: text, localPort: localPort)
    }
}
