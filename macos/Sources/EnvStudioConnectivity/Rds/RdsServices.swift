import Foundation

public enum DatabaseURLBuilder {
    public static let rdsCaDownloadURL =
        "https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem"

    public static func encodeURIComponent(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.!~*'()")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    public static func expandHome(_ path: String) -> String {
        if path.hasPrefix("~/") {
            return NSHomeDirectory() + path.dropFirst()
        }
        if path == "~" {
            return NSHomeDirectory()
        }
        return path
    }

    public static func buildDatabaseURL(
        driver: TunnelDriver,
        username: String,
        token: String,
        localPort: Int,
        database: String,
        sslCertPath: String
    ) -> String {
        let encoded = encodeURIComponent(token)
        let cert = expandHome(sslCertPath)
        switch driver {
        case .mysql:
            return
                "mysql://\(username):\(encoded)@127.0.0.1:\(localPort)/\(database)?sslmode=require&sslaccept=accept_invalid_certs&sslcert=\(cert)"
        case .postgres:
            return
                "postgresql://\(username):\(encoded)@127.0.0.1:\(localPort)/\(database)?sslmode=require&sslcert=\(cert)"
        case .none:
            return ""
        }
    }

    public static func tokenLifetimeSeconds() -> TimeInterval {
        15 * 60
    }
}

public enum RdsCaManager {
    public static func ensureCertificate(at path: String) async throws {
        let expanded = DatabaseURLBuilder.expandHome(path)
        let url = URL(fileURLWithPath: expanded)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let downloadURL = URL(string: DatabaseURLBuilder.rdsCaDownloadURL) else {
            throw RdsError.invalidCaURL
        }
        let (data, response) = try await URLSession.shared.data(from: downloadURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw RdsError.caDownloadFailed
        }
        let temp = url.appendingPathExtension("tmp")
        try data.write(to: temp, options: .atomic)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
    }
}

public enum RdsError: LocalizedError {
    case invalidCaURL
    case caDownloadFailed
    case tokenGenerationFailed(String)
    case unsupportedDriver

    public var errorDescription: String? {
        switch self {
        case .invalidCaURL: return "URL do certificado RDS inválida."
        case .caDownloadFailed: return "Falha ao baixar certificado RDS."
        case .tokenGenerationFailed(let detail):
            return "Falha ao gerar token RDS: \(detail)"
        case .unsupportedDriver: return "Driver não suportado para token RDS."
        }
    }
}

public enum RdsTokenGenerator {
    public static func generateToken(
        awsExecutable: String,
        profile: String,
        region: String,
        hostname: String,
        port: Int,
        username: String,
        environment: [String: String]
    ) async throws -> String {
        let result = await ShellCommandRunner.run(
            executable: awsExecutable,
            arguments: [
                "rds", "generate-db-auth-token",
                "--profile", profile,
                "--hostname", hostname,
                "--port", String(port),
                "--username", username,
                "--region", region,
            ],
            environment: environment
        )
        guard result.exitCode == 0 else {
            let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw RdsError.tokenGenerationFailed(detail.isEmpty ? "aws CLI falhou" : detail)
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func makeSession(
        token: String,
        tunnel: TunnelDefinition,
        username: String,
        sslCertPath: String
    ) -> RdsTokenSession {
        let now = Date()
        let expires = now.addingTimeInterval(DatabaseURLBuilder.tokenLifetimeSeconds())
        let url = buildDatabaseURL(
            tunnel: tunnel,
            token: token,
            username: username,
            sslCertPath: sslCertPath
        )
        return RdsTokenSession(
            rawToken: token,
            databaseURL: url,
            envVarName: tunnel.resolvedEnvVarName,
            generatedAt: now,
            expiresAt: expires
        )
    }

    public static func buildDatabaseURL(
        tunnel: TunnelDefinition,
        token: String,
        username: String,
        sslCertPath: String
    ) -> String {
        DatabaseURLBuilder.buildDatabaseURL(
            driver: tunnel.driver,
            username: username,
            token: token,
            localPort: tunnel.localPort,
            database: tunnel.database,
            sslCertPath: sslCertPath
        )
    }
}

public enum RdsConnectionTester {
    public static func testConnection(
        tunnel: TunnelDefinition,
        username: String,
        token: String,
        timeoutSeconds: Int = 8
    ) async -> RdsPasswordTestResult {
        let testedAt = Date()
        switch tunnel.driver {
        case .mysql:
            return await testMySQL(
                port: tunnel.localPort,
                username: username,
                password: token,
                database: tunnel.database,
                timeout: timeoutSeconds,
                testedAt: testedAt
            )
        case .postgres:
            return await testPostgres(
                port: tunnel.localPort,
                username: username,
                password: token,
                database: tunnel.database,
                timeout: timeoutSeconds,
                testedAt: testedAt
            )
        case .none:
            return .failure("Túnel não é RDS.", testedAt)
        }
    }

    private static func testMySQL(
        port: Int,
        username: String,
        password: String,
        database: String,
        timeout: Int,
        testedAt: Date
    ) async -> RdsPasswordTestResult {
        let mysql = resolveExecutable(["/opt/homebrew/bin/mysql", "/usr/local/bin/mysql", "mysql"])
        guard let mysql else {
            return .failure("Cliente mysql não encontrado no PATH.", testedAt)
        }
        var env = ProcessInfo.processInfo.environment
        env["MYSQL_PWD"] = password
        let result = await ShellCommandRunner.run(
            executable: mysql,
            arguments: [
                "--connect-timeout=\(timeout)",
                "-h", "127.0.0.1",
                "-P", String(port),
                "-u", username,
                database,
                "-e", "SELECT 1",
            ],
            environment: env
        )
        if result.exitCode == 0 {
            return .success(testedAt)
        }
        return .failure("Autenticação ou conexão falhou.", testedAt)
    }

    private static func testPostgres(
        port: Int,
        username: String,
        password: String,
        database: String,
        timeout: Int,
        testedAt: Date
    ) async -> RdsPasswordTestResult {
        let psql = resolveExecutable(["/opt/homebrew/bin/psql", "/usr/local/bin/psql", "psql"])
        guard let psql else {
            return .failure("Cliente psql não encontrado no PATH.", testedAt)
        }
        var env = ProcessInfo.processInfo.environment
        env["PGPASSWORD"] = password
        let result = await ShellCommandRunner.run(
            executable: psql,
            arguments: [
                "-h", "127.0.0.1",
                "-p", String(port),
                "-U", username,
                "-d", database,
                "-c", "SELECT 1",
            ],
            environment: env
        )
        if result.exitCode == 0 {
            return .success(testedAt)
        }
        return .failure("Autenticação ou conexão falhou.", testedAt)
    }

    private static func resolveExecutable(_ candidates: [String]) -> String? {
        for path in candidates {
            if path.contains("/") {
                if FileManager.default.isExecutableFile(atPath: path) { return path }
            }
        }
        return nil
    }
}
