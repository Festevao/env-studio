import Foundation

public struct ShellCommandResult: Sendable {
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String
}

public enum ShellCommandRunner {
    public static func run(
        executable: String,
        arguments: [String],
        environment: [String: String] = [:]
    ) async -> ShellCommandResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                var env = ProcessInfo.processInfo.environment
                for (key, value) in environment {
                    env[key] = value
                }
                process.environment = env

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe

                do {
                    try process.run()
                    process.waitUntilExit()
                    let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    continuation.resume(
                        returning: ShellCommandResult(
                            exitCode: process.terminationStatus,
                            stdout: String(data: outData, encoding: .utf8) ?? "",
                            stderr: String(data: errData, encoding: .utf8) ?? ""
                        )
                    )
                } catch {
                    continuation.resume(
                        returning: ShellCommandResult(
                            exitCode: -1,
                            stdout: "",
                            stderr: error.localizedDescription
                        )
                    )
                }
            }
        }
    }

    public static func resolveAwsExecutable(customPath: String?) -> String {
        if let customPath, !customPath.isEmpty {
            return customPath
        }
        let candidates = [
            "/opt/homebrew/bin/aws",
            "/usr/local/bin/aws",
            "/usr/bin/aws",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return "aws"
    }

    public static func loginShellEnvironment() async -> [String: String] {
        let result = await run(
            executable: "/bin/zsh",
            arguments: ["-l", "-c", "env"],
            environment: [:]
        )
        guard result.exitCode == 0 else {
            return ProcessInfo.processInfo.environment
        }
        var map: [String: String] = [:]
        for line in result.stdout.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            map[String(parts[0])] = String(parts[1])
        }
        return map.merging(ProcessInfo.processInfo.environment) { current, _ in current }
    }

    public static func runAwsViaLoginShell(
        awsExecutable: String,
        arguments: [String],
        environment: [String: String]
    ) async -> ShellCommandResult {
        let command = AwsCommandEnvironment.loginShellCommand(
            awsExecutable: awsExecutable,
            arguments: arguments
        )
        return await run(
            executable: "/bin/zsh",
            arguments: ["-l", "-c", command],
            environment: environment
        )
    }
}
