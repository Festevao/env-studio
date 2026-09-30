import Foundation

public enum SsoAuthStatus: Equatable, Sendable {
    case unknown
    case valid
    case invalid
}

public enum AwsCredentialsExportError: Error, Sendable {
    case message(String)
}

public enum AwsSessionCredentials {
    public static func exportForProfile(
        awsExecutable: String,
        profile: String,
        region: String,
        baseEnvironment: [String: String]
    ) async -> Result<[String: String], AwsCredentialsExportError> {
        let merged = AwsCommandEnvironment.merge(
            base: baseEnvironment,
            profile: profile,
            region: region
        )
        let result = await ShellCommandRunner.runAwsViaLoginShell(
            awsExecutable: awsExecutable,
            arguments: [
                "configure", "export-credentials",
                "--profile", profile,
                "--format", "env-no-export",
            ],
            environment: merged
        )
        guard result.exitCode == 0 else {
            let message = AwsCliErrorPresenter.friendlyMessage(
                raw: result.stderr.isEmpty ? result.stdout : result.stderr
            )
            return .failure(.message(message))
        }
        let parsed = parseEnvLines(result.stdout)
        guard parsed["AWS_ACCESS_KEY_ID"] != nil else {
            return .failure(.message("export-credentials não retornou chaves de sessão."))
        }
        var env = merged
        for (key, value) in parsed {
            env[key] = value
        }
        return .success(env)
    }

    public static func verifyProfile(
        awsExecutable: String,
        profile: String,
        region: String,
        baseEnvironment: [String: String]
    ) async -> SsoAuthStatus {
        let merged = AwsCommandEnvironment.merge(
            base: baseEnvironment,
            profile: profile,
            region: region
        )
        let export = await exportForProfile(
            awsExecutable: awsExecutable,
            profile: profile,
            region: region,
            baseEnvironment: baseEnvironment
        )
        let envForSts: [String: String]
        switch export {
        case .success(let creds):
            envForSts = creds
        case .failure:
            envForSts = merged
        }
        let result = await ShellCommandRunner.run(
            executable: awsExecutable,
            arguments: [
                "sts", "get-caller-identity",
                "--profile", profile,
            ],
            environment: envForSts
        )
        if result.exitCode == 0 {
            return .valid
        }
        let combined = result.stderr + result.stdout
        if combined.contains("ForbiddenException")
            || combined.contains("ExpiredToken")
            || combined.contains("Unable to locate credentials")
            || combined.contains("SSO")
        {
            return .invalid
        }
        return .invalid
    }

    public static func parseEnvLines(_ text: String) -> [String: String] {
        var map: [String: String] = [:]
        for line in text.split(separator: "\n") {
            var trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("export ") {
                trimmed = String(trimmed.dropFirst(7))
            }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0])
            var value = String(parts[1])
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            map[key] = value
        }
        return map
    }
}
